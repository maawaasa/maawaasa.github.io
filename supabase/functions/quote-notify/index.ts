// =====================================================
// MAAWAA — quote-notify (Edge Function)
// يُستدعى من الحاسبة بعد نجاح submit_quote — يرسل C-01 «عرض السعر جاهز».
//
// القواعد:
//   - المصدر الوحيد للحقيقة: DB (quotes + clients) — لا يُقبل أي
//     quote_number/total/email من المتصفح
//   - الإدخال الوحيد: quote_id (UUID)
//   - Idempotency: quote:<quote_id>:C-01:v1 عبر send-email (الحارس النهائي) —
//     فحص email_log مسبق = optimization فقط
//   - فشل الإيميل لا يغيّر حالة العرض إطلاقًا
//   - الردود بسيطة بلا PII: sent / skipped_duplicate / skipped_outdated / errors
// verify_jwt=false مقصود — الاستدعاء العام بمفتاح anon (نمط notify-lead)،
// والحماية: UUID غير قابل للتخمين + SoT + Idempotency + لا PII في الردود.
// =====================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SITE = 'https://maawaa.sa';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const db = createClient(SUPABASE_URL, SERVICE_KEY);

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers: CORS });
  }

  // 1) validate quote_id — الإدخال الوحيد المقبول
  let quoteId = '';
  try {
    const body = await req.json();
    quoteId = String((body as { quote_id?: string }).quote_id ?? '');
  } catch {
    return new Response(JSON.stringify({ error: 'bad_json' }), { status: 400, headers: CORS });
  }
  if (!UUID_RE.test(quoteId)) {
    return new Response(JSON.stringify({ error: 'invalid_quote_id' }), { status: 400, headers: CORS });
  }

  // 2+3) Source of Truth: العرض + بريد العميل من DB حصريًا
  const { data: quote, error: qErr } = await db
    .from('quotes')
    .select('id, quote_number, total_amount, valid_until, status, service_type, payload, clients(email, full_name)')
    .eq('id', quoteId)
    .maybeSingle();
  if (qErr) {
    return new Response(JSON.stringify({ error: 'lookup_failed' }), { status: 500, headers: CORS });
  }
  if (!quote) {
    // رد عام — لا يكشف وجود/عدم وجود أي كيانات أخرى
    return new Response(JSON.stringify({ error: 'not_found' }), { status: 404, headers: CORS });
  }
  const q = quote as unknown as {
    id: string; quote_number: string; total_amount: number; valid_until: string;
    status: string; service_type: string | null;
    payload: { summary?: string } | null;
    clients: { email: string | null; full_name: string | null } | null;
  };

  // 4) الحالة: active فقط (منتهٍ/منفّي → بلا إرسال)
  if (q.status !== 'active') {
    return new Response(JSON.stringify({ result: 'skipped_outdated', status: q.status }), {
      status: 200, headers: CORS,
    });
  }

  const client = q.clients ?? null;
  const clientRec = Array.isArray(client) ? client[0] : client;
  const email = clientRec?.email ?? '';
  const toName = clientRec?.full_name ?? '';
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return new Response(JSON.stringify({ error: 'recipient_missing' }), { status: 422, headers: CORS });
  }

  // Idempotency pre-check — optimization فقط؛ send-email هو الحارس النهائي
  const { data: existing } = await db.from('email_log')
    .select('id').eq('idempotency_key', `quote:${q.id}:C-01:v1`).limit(1).maybeSingle();
  if (existing) {
    return new Response(JSON.stringify({ result: 'skipped_duplicate' }), { status: 200, headers: CORS });
  }

  // 5+6+7) C-01 من بيانات DB فقط — بلا quote_url (لا Portal، لا زر «تفاصيل»)
  const summary = String((q.payload as { summary?: string } | null)?.summary ?? q.service_type ?? '');
  const sr = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      event_type: 'C-01',
      entity_type: 'quote',
      entity_id: q.id,
      to: email,
      to_name: toName,
      data: {
        quote_number: q.quote_number,
        total: Number(q.total_amount || 0),
        valid_until: q.valid_until,
        summary,
      },
    }),
  });
  const body = await sr.json().catch(() => ({}) as { result?: string });
  const result = String((body as { result?: string }).result ?? '');

  if (sr.ok && ['sent', 'skipped_duplicate', 'skipped_outdated'].includes(result)) {
    return new Response(JSON.stringify({ result }), { status: 200, headers: CORS });
  }
  // فشل الإرسال — لا تغيير في حالة العرض؛ الاستدعاء التالي يعيد المحاولة
  console.error('quote-notify: send_failed', q.quote_number, sr.status, result);
  return new Response(JSON.stringify({ error: 'send_failed' }), { status: 502, headers: CORS });
});
