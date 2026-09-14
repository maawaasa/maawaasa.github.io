// =====================================================
// MAAWAA — receipt-submit (Edge Function — عام عبر رمز آمن)
// رفع إيصال عربون (deposit) أو سداد نهائي (balance) من صفحة receipt.html
// Input: { token, image_data_url }  (data:image/jpeg;base64,...)
//
// القواعد المنفذة:
//   - الرمز: استخدام واحد Atomically — كل الشروط في UPDATE واحد:
//       token_hash + used_at IS NULL + expires_at > now() + purpose + entity_type
//   - deposit_receipt:
//       * مقبول فقط أثناء Hold نشط، أو أثناء مراجعة/تصحيح قائم
//         (إعادة رفع التصحيح بعد correction_requested)
//       * بعد انتهاء الـHold وتحريره (C-07) ⇒ رفض hold_expired
//   - balance_receipt: بعد اعتماد العربون (deposit_paid/in_progress)
//   - الرفع إلى حاوية receipts الخاصة
//   - رفع الإيصال يوقف انتهاء الـHold (hold_expires_at → NULL) —
//     الموعد محفوظ أثناء المراجعة، وReceipt Upload ≠ Payment Approved
// =====================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MAX_BYTES = 8 * 1024 * 1024; // 8MB

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function bad(code: string) {
  return new Response(JSON.stringify({ error: code }), { status: 400, headers: CORS });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return new Response('method_not_allowed', { status: 405, headers: CORS });

  const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(Deno.env.get('SUPABASE_URL')!, SERVICE_KEY);

  let body: { token?: string; image_data_url?: string };
  try { body = await req.json(); } catch { return bad('bad_json'); }
  const token = String(body.token || '');
  const dataUrl = String(body.image_data_url || '');
  if (!token || !dataUrl.startsWith('data:image/')) return bad('invalid_input');

  // الحجم والنوع قبل أي كتابة — فشل الإدخال لا يحرق الرمز
  const mime = dataUrl.slice(5, dataUrl.indexOf(';'));
  const EXT_BY_MIME: Record<string, string> = {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };
  const ext = EXT_BY_MIME[mime];
  if (!ext) return bad('unsupported_image_type');
  const base64 = dataUrl.split(',')[1] ?? '';
  const bytes = Math.floor((base64.length * 3) / 4);
  if (bytes < 1024) return bad('image_too_small');
  if (bytes > MAX_BYTES) return bad('image_too_large');

  // ===== 1) Claim ذري — كل الشروط في UPDATE واحد (لا TOCTOU) =====
  const nowIso = new Date().toISOString();
  const claim = await db.from('action_tokens')
    .update({ used_at: nowIso })
    .eq('token_hash', await sha256Hex(token))
    .is('used_at', null)
    .gt('expires_at', nowIso)
    .in('purpose', ['deposit_receipt', 'balance_receipt'])
    .eq('entity_type', 'contract')
    .select('id, purpose, entity_id')
    .maybeSingle();

  if (!claim.data) return bad('invalid_or_used_token');
  const claimId = String((claim.data as { id: string }).id);
  const purpose = String((claim.data as { purpose: string }).purpose) as 'deposit_receipt' | 'balance_receipt';
  const contractId = String((claim.data as { entity_id: string }).entity_id);

  // ===== 2) حالة الطلب — منع المراحل القديمة + قواعد Hold =====
  const { data: cur } = await db.from('contracts')
    .select('id, status, contract_number, hold_expires_at, deposit_review_status')
    .eq('id', contractId)
    .maybeSingle();
  if (!cur) return bad('contract_not_found');
  const status = String((cur as { status: string }).status);
  const holdExpires = String((cur as { hold_expires_at: string | null }).hold_expires_at ?? '');
  const reviewStatus = String((cur as { deposit_review_status: string | null }).deposit_review_status ?? '');
  const holdActive = holdExpires !== '' && new Date(holdExpires).getTime() > Date.now();

  if (purpose === 'deposit_receipt') {
    // مقبول: أثناء Hold نشط، أو أثناء مراجعة/تصحيح قائم (إعادة رفع التصحيح)
    if (!['new', 'awaiting_payment'].includes(status)) return bad('outdated_state');
    if (!holdActive && !['receipt_under_review', 'correction_requested'].includes(reviewStatus)) {
      return bad('hold_expired'); // الـHold انتهى وتحرر الحجز — يلزم مسار جديد
    }
  } else {
    // balance_receipt: بعد اعتماد العربون فقط
    if (!['deposit_paid', 'in_progress'].includes(status)) return bad('outdated_state');
  }

  // ===== 3) الرفع إلى الحاوية الخاصة =====
  try {
    const kind = purpose === 'deposit_receipt' ? 'deposit' : 'balance';
    const path = `${contractId}/${kind}-${Date.now()}.${ext}`; // ext/mime تحققا قبل الـClaim
    const bin = Uint8Array.from(atob(base64), (ch) => ch.charCodeAt(0));
    const up = await db.storage.from('receipts').upload(path, bin, {
      contentType: mime,
      upsert: false,
    });
    if (up.error) throw new Error('storage_upload_failed');

    // ===== 4) تحديث الطلب — Receipt Under Review + إيقاف انتهاء الـHold =====
    const patch: Record<string, unknown> = {
      receipt_uploaded_at: nowIso,
      receipt_image_url: path,
      deposit_review_status: 'receipt_under_review',
      hold_expires_at: null, // الإيصال قبل انتهاء المهلة يوقف الانتهاء — الموعد محفوظ أثناء المراجعة
    };
    const upd = await db.from('contracts')
      .update(patch)
      .eq('id', contractId)
      .in('status', ['new', 'awaiting_payment', 'deposit_paid', 'in_progress'])
      .select('id, contract_number')
      .maybeSingle();
    if (!upd.data) throw new Error('contract_update_failed');
    const contractNumber = (upd.data as { contract_number: string | null }).contract_number;

    // ===== 5) Activity Log (عبر log_email_activity محصّنة service_role) =====
    try {
      await db.rpc('log_email_activity', {
        p_action: `receipt_uploaded:${kind}`,
        p_entity: 'contracts',
        p_entity_id: contractId,
        p_details: { contract_number: contractNumber, path, bytes, purpose },
      });
    } catch { /* activity_log اختياري — لا يفشل الرفع */ }

    return new Response(JSON.stringify({
      ok: true,
      contract_number: contractNumber,
      state: 'receipt_under_review',
      message: 'تم استلام الإيصال وهو تحت المراجعة — الموعد محفوظ',
    }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
  } catch (e) {
    // Failure handling: فشل مؤقت في Storage/DB بعد الـClaim لا يحرق الرمز —
    // نطلقه شرطيًا بمطابقة used_at بنفس القيمة التي وضعناها (ملكية الـClaim مثبتة،
    // ولا يمكن لأي طلب آخر استغلال الإطلاق — الـClaim يظل ذريًا للجميع)
    await db.from('action_tokens')
      .update({ used_at: null })
      .eq('id', claimId)
      .eq('used_at', nowIso);
    return new Response(JSON.stringify({ error: 'server_error', detail: String(e).slice(0, 200) }), {
      status: 500, headers: CORS,
    });
  }
});
