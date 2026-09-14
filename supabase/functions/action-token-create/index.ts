// =====================================================
// MAAWAA — action-token-create (Edge Function — داخلية فقط)
// توليد رابط فعل آمن لعميل (إيصال عربون/رصيد، عقد، تسليم...)
// Input (service_role فقط):
//   { purpose, entity_id, entity_type?, ttl_hours? , base_url? }
// Output: { token, url, expires_at }
// الرمز الخام يُعاد مرة واحدة — يُخزن sha256 فقط
// =====================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SITE = 'https://maawaa.sa';
const PURPOSE_PAGE: Record<string, string> = {
  deposit_receipt: 'receipt.html',
  balance_receipt: 'receipt.html',
  contract_access: 'contract.html',
  delivery_access: 'delivery.html',
  rating: 'rating.html',
  calendar: 'calculator.html',
};

// TTL الافتراضي لكل غرض (ساعات) — قرار تشغيلي معتمد:
//   deposit_receipt = مدة الـHold (24h) — بعد تحرره يرفض receipt-submit الرمز
//   balance_receipt = 72h للسداد النهائي
//   contract_access = 7 أيام · delivery_access = 14 يومًا (الحفظ 30 يومًا)
//   rating = 14 يومًا · calendar = 72h
const PURPOSE_TTL_HOURS: Record<string, number> = {
  deposit_receipt: 24,
  balance_receipt: 72,
  contract_access: 168,
  delivery_access: 336,
  rating: 336,
  calendar: 72,
};

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  // Bearer parsing صريح + مقارنة Exact — لا substring matching
  const m = /^Bearer\s+(.+)$/i.exec((req.headers.get('Authorization') ?? '').trim());
  const cred = m?.[1] ?? '';
  if (cred === '' || cred !== SERVICE_KEY) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: CORS });
  }

  let body: { purpose: string; entity_id: string; entity_type?: string; ttl_hours?: number; base_url?: string };
  try { body = await req.json(); } catch { return new Response('bad_json', { status: 400, headers: CORS }); }

  const purpose = String(body.purpose || '');
  const entityId = String(body.entity_id || '');
  const entityType = body.entity_type === 'quote' ? 'quote' : 'contract';
  const ttlHours = Math.min(
    Math.max(Number(body.ttl_hours) || PURPOSE_TTL_HOURS[purpose] || 72, 1),
    720
  );
  if (!PURPOSE_PAGE[purpose] || !entityId) {
    return new Response(JSON.stringify({ error: 'invalid_purpose_or_entity' }), { status: 400, headers: CORS });
  }
  // entity_id يجب أن يكون UUID صالحًا
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(entityId)) {
    return new Response(JSON.stringify({ error: 'invalid_entity_id' }), { status: 400, headers: CORS });
  }

  // رمز عشوائي قوي — يُخزن الهاش فقط
  const raw = crypto.getRandomValues(new Uint8Array(32));
  const token = [...raw].map((b) => b.toString(16).padStart(2, '0')).join('');
  const tokenHash = await sha256Hex(token);
  const expiresAt = new Date(Date.now() + ttlHours * 3600_000).toISOString();

  const db = createClient(Deno.env.get('SUPABASE_URL')!, SERVICE_KEY);

  // لا orphan tokens: الكيان يجب أن يكون موجودًا فعليًا
  const entityTable = entityType === 'quote' ? 'quotes' : 'contracts';
  const { data: ent } = await db.from(entityTable).select('id').eq('id', entityId).maybeSingle();
  if (!ent) {
    return new Response(JSON.stringify({ error: 'entity_not_found', entity_type: entityType, entity_id: entityId }), {
      status: 404, headers: CORS,
    });
  }
  const ins = await db.from('action_tokens').insert({
    token_hash: tokenHash,
    purpose,
    entity_type: entityType,
    entity_id: entityId,
    expires_at: expiresAt,
  }).select('id, expires_at').single();
  if (ins.error) return new Response(JSON.stringify({ error: 'insert_failed' }), { status: 500, headers: CORS });

  const base = body.base_url || SITE;
  const url = `${base}/${PURPOSE_PAGE[purpose]}?t=${token}`;
  return new Response(JSON.stringify({ token, url, expires_at: ins.data.expires_at, id: ins.data.id }), {
    status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
  });
});
