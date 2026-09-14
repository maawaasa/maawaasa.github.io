// =====================================================
// MAAWAA — payment-approve (Edge Function — ملاك/خدمة فقط)
// اعتماد الدفعة بعد مراجعة الإيصال:
//   عربون ≥25% ⇒ status='deposit_paid' + Booking Confirmed (C-08)
//   سداد نهائي ⇒ status='fully_paid' + Paid in Full → C-17 مسار التسليم
// Auth: service_role أو مستخدم authenticated (الملاك عبر admin)
// =====================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SITE = 'https://maawaa.sa';

// تفويض فعلي: المستخدم يجب أن يكون عضو فريق نشطًا — لا مجرد JWT صالح
async function isTeamMember(db: any, jwt: string): Promise<boolean> {
  const { data } = await db.auth.getUser(jwt);
  const u = data?.user;
  if (!u) return false;
  const email = (u.email ?? '').toLowerCase();
  const conds = [`auth_user_id.eq.${u.id}`];
  if (email) conds.push(`email.ilike.${email}`);
  const { data: emp } = await db.from('employees')
    .select('id')
    .eq('is_active', true)
    .or(conds.join(','))
    .maybeSingle();
  return !!emp;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return new Response('method_not_allowed', { status: 405, headers: CORS });

  const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  // Bearer parsing صريح + مقارنة Exact — لا substring matching
  const bearerMatch = /^Bearer\s+(.+)$/i.exec((req.headers.get('Authorization') ?? '').trim());
  const cred = bearerMatch?.[1] ?? '';
  const isService = cred !== '' && cred === SERVICE_KEY;
  const db = createClient(Deno.env.get('SUPABASE_URL')!, SERVICE_KEY);

  // تفويض فعلي: service_role أو عضو فريق نشط (لا مجرد JWT صالح)
  if (!isService) {
    if (!cred) return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: CORS });
    if (!(await isTeamMember(db, cred))) {
      return new Response(JSON.stringify({ error: 'forbidden_not_team_member' }), { status: 403, headers: CORS });
    }
  }

  let body: { contract_id?: string; kind?: 'deposit' | 'balance' | 'correction'; payment_reference?: string; amount?: number };
  try { body = await req.json(); } catch { return new Response(JSON.stringify({ error: 'bad_json' }), { status: 400, headers: CORS }); }
  const contractId = String(body.contract_id || '');
  const kind = ['deposit', 'balance', 'correction'].includes(String(body.kind)) ? String(body.kind) : 'deposit';
  if (!contractId) return new Response(JSON.stringify({ error: 'contract_id_required' }), { status: 400, headers: CORS });

  const { data: contract } = await db.from('contracts')
    .select('id, contract_number, status, client_id, total_amount, service_type, shoot_date, property_location, deposit_review_status')
    .eq('id', contractId).maybeSingle();
  if (!contract) return new Response(JSON.stringify({ error: 'contract_not_found' }), { status: 404, headers: CORS });
  const c = contract as { id: string; contract_number: string | null; status: string; client_id: string; total_amount: number; service_type: string | null; shoot_date: string | null; property_location: string | null; deposit_review_status: string | null };

  // ===== مسار التصحيح: إيصال تحت المراجعة يُرفض ⇒ رمز جديد + C-06 =====
  if (kind === 'correction') {
    if (!['awaiting_payment', 'new'].includes(c.status)) {
      return new Response(JSON.stringify({ error: 'outdated_state', status: c.status }), { status: 409, headers: CORS });
    }
    if (c.deposit_review_status !== 'receipt_under_review') {
      return new Response(JSON.stringify({ error: 'no_receipt_under_review' }), { status: 409, headers: CORS });
    }
    const upd = await db.from('contracts')
      .update({ deposit_review_status: 'correction_requested' })
      .eq('id', c.id)
      .eq('deposit_review_status', 'receipt_under_review') // قفل تزامن
      .select('id')
      .maybeSingle();
    if (!upd.data) return new Response(JSON.stringify({ error: 'outdated_state', detail: 'changed_concurrently' }), { status: 409, headers: CORS });

    // رمز جديد (الرمز المستهلك لا يُعاد استخدامه أبدًا)
    const raw = crypto.getRandomValues(new Uint8Array(32));
    const token = [...raw].map((b) => b.toString(16).padStart(2, '0')).join('');
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
    const tokenHash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
    const tokenIns = await db.from('action_tokens').insert({
      token_hash: tokenHash,
      purpose: 'deposit_receipt',
      entity_type: 'contract',
      entity_id: c.id,
      expires_at: new Date(Date.now() + 24 * 3600_000).toISOString(),
    }).select('id').single();
    const depositUrl = tokenIns.error ? `${SITE}/receipt.html` : `${SITE}/receipt.html?t=${token}&p=deposit_receipt`;

    const { data: client2 } = await db.from('clients').select('email, full_name').eq('id', c.client_id).maybeSingle();
    const cl = client2 as { email: string | null; full_name: string | null } | null;
    if (cl?.email) {
      await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-email`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          event_type: 'C-06', entity_type: 'contract', entity_id: c.id, to: cl.email, to_name: cl.full_name,
          data: { contract_number: c.contract_number, deposit_upload_url: depositUrl },
        }),
      }).then((r) => r.text()).catch(() => 'send_failed');
    }
    try {
      await db.from('activity_log').insert({
        action: 'receipt_correction_requested',
        entity: 'contracts',
        details: { contract_id: c.id, contract_number: c.contract_number },
      });
    } catch { /* اختياري */ }
    return new Response(JSON.stringify({ ok: true, state: 'correction_requested', new_token_issued: !tokenIns.error }), {
      status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  // ===== مسارا الاعتماد: deposit / balance — Atomic RPC داخل DB =====
  // القفل والتحقق والإدراج وحساب paid_total وتحديد الحالة تتم كلها داخل
  // approve_payment_atomic (FOR UPDATE + معاملة واحدة + Rollback كامل عند أي فشل)
  // المبلغ المعتمد يُدخل من المالك (بعد مراجعة الإيصال) — إلزامي

  const approvedAmount = Math.round(Number(body.amount) * 100) / 100;
  if (!Number.isFinite(approvedAmount) || approvedAmount <= 0) {
    return new Response(JSON.stringify({ error: 'amount_required' }), { status: 400, headers: CORS });
  }

  // فحص سريع لرفض واضح قبل النداء — القرار النهائي داخل الـRPC المقفلة
  if (kind === 'deposit' && !['awaiting_payment', 'new'].includes(c.status)) {
    return new Response(JSON.stringify({ error: 'outdated_state', status: c.status }), { status: 409, headers: CORS });
  }
  if (kind === 'balance' && !['deposit_paid', 'in_progress'].includes(c.status)) {
    return new Response(JSON.stringify({ error: 'outdated_state', status: c.status }), { status: 409, headers: CORS });
  }

  const rpc = await db.rpc('approve_payment_atomic', {
    p_contract_id: c.id,
    p_amount: approvedAmount,
    p_kind: kind,
    p_payment_reference: body.payment_reference ?? null,
  });

  if (rpc.error) {
    const msg = String(rpc.error.message);
    const known = ['amount_exceeds_total', 'outdated_state', 'contract_not_found', 'invalid_amount', 'duplicate_reference', 'insufficient_balance'];
    if (known.some((k) => msg.includes(k))) {
      return new Response(JSON.stringify({ error: msg, status: c.status }), { status: 409, headers: CORS });
    }
    return new Response(JSON.stringify({ error: 'rpc_failed', detail: msg.slice(0, 200) }), { status: 500, headers: CORS });
  }

  const res = rpc.data as { state: string; status: string; paid_total: number; total_amount: number; contract_number: string | null };
  const confirmed = res.state !== 'payment_recorded';

  // إيميل العميل: C-08 (تأكيد الحجز عند deposit_paid/fully_paid عبر عربون) أو C-17 (Paid in Full)
  const { data: client } = await db.from('clients').select('email, full_name').eq('id', c.client_id).maybeSingle();
  const email = (client as { email: string | null } | null)?.email ?? '';
  const sendC = confirmed && !(kind === 'deposit' && res.state === 'payment_recorded');
  if (email && sendC) {
    await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-email`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        event_type: res.state === 'fully_paid' ? 'C-17' : 'C-08',
        entity_type: 'contract',
        entity_id: c.id,
        to: email,
        to_name: (client as { full_name: string | null } | null)?.full_name ?? '',
        data: {
          contract_number: res.contract_number,
          client_name: (client as { full_name: string | null } | null)?.full_name,
          total: res.total_amount,
          deposit: res.paid_total,
          remaining: Math.max(0, res.total_amount - res.paid_total),
          services: c.service_type,
          shoot_date: c.shoot_date,
          location: c.property_location,
          contract_url: `${SITE}/approve-contract.html?ref=${c.id}`,
          delivery_url: `${SITE}/delivery.html?ref=${c.id}`,
        },
      }),
    }).then((r) => r.text()).catch(() => 'send_failed');
  }

  try {
    await db.rpc('log_email_activity', {
      p_action: `payment_approved:${kind}`,
      p_entity: 'contracts',
      p_entity_id: c.id,
      p_details: {
        contract_number: res.contract_number,
        state: res.state,
        paid_total: res.paid_total,
        payment_reference: body.payment_reference ?? null,
      },
    });
  } catch { /* اختياري */ }

  return new Response(JSON.stringify({
    ok: true,
    contract_number: res.contract_number,
    state: res.state,
    status: res.status,
    paid_total: res.paid_total,
  }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
});
