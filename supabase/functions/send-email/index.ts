// =====================================================
// MAAWAA — send-email (Edge Function)
// المرسل الموحد لأنظمة الإيميل — Phase 1 Email-First
//
// القواعد المنفذة:
//   - Idempotency: entity:entity_id:event_type:event_version — الإدراج قفل
//   - Retry لا يرسل Duplicate
//   - outdated-event prevention: فحص حالة الكيان قبل الإرسال
//   - لا إرسال مباشر من المتصفح — يُستدعى من دوال/ويبهوكات خادمية فقط
//     (يتطلب Authorization: Bearer SERVICE_ROLE key)
//
// Secrets المطلوبة (يضيفها المالك):
//   RESEND_API_KEY
//   EMAIL_FROM_CUSTOMER  مثال: "مأوى للتصوير العقاري <info@maawaa.sa>"
//   EMAIL_FROM_OPERATIONS مثال: "مأوى للتصوير العقاري <operations@maawaa.sa>"
// =====================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  C01_quoteReady, C02_quoteExpired, C03_bookingReceived, C04_depositHold,
  C05_receiptReceived, C06_receiptCorrection, C07_holdExpired, C08_bookingConfirmed,
  C09_contractReady, C10_appointmentUpdated, C11_shootReminder, C12_operationalUpdate,
  C13_processingStarted, C14_readyBalance, C15_finalReceiptReceived, C16_finalReceiptCorrection,
  C17_delivery, C18_retentionReminder, C19_v360Expiry, C20_rating,
  O01_newOrder, O02_assigned, O03_receiptReview, O04_orderNeedsAction, O05_bookingConfirmed,
  O06_operationalUpdate, O07_photographer24h, O08_photographerReminder,
  O09_filesMissing, O10_qualityReview, O11_deliveryDelayRisk, O12_deliveryClosure,
  type QuoteCtx, type ContractCtx, type C12Variant,
} from '../_shared/templates.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const FROM_CUSTOMER = Deno.env.get('EMAIL_FROM_CUSTOMER') ?? 'مأوى للتصوير العقاري <info@maawaa.sa>';
const FROM_OPERATIONS = Deno.env.get('EMAIL_FROM_OPERATIONS') ?? 'مأوى للتصوير العقاري <operations@maawaa.sa>';

const db = createClient(SUPABASE_URL, SERVICE_KEY);

type Req = {
  event_type: string;           // C-01 .. O-08
  event_version?: number;       // default 1
  entity_type: 'quote' | 'contract' | 'none';
  entity_id: string | null;
  to: string;                   // بريد المستلم
  to_name?: string;
  data: Record<string, unknown>;// متغيرات القالب
};

// حالات الكيان المسموح إرسال الحدث عندها — منع الأحداث القديمة
const CONTRACT_EVENT_STATUS: Record<string, string[]> = {
  'C-03': ['new'],
  'C-04': ['new', 'awaiting_payment'],
  'C-05': ['awaiting_payment'],
  'C-06': ['awaiting_payment'],
  'C-07': ['new', 'awaiting_payment'],
  'C-08': ['awaiting_payment', 'deposit_paid'],
  'C-09': ['deposit_paid', 'in_progress'],
  'C-10': ['deposit_paid', 'in_progress', 'awaiting_payment'],
  'C-11': ['deposit_paid', 'in_progress'],
  'C-13': ['in_progress'],
  'C-14': ['in_progress', 'fully_paid'],
  'C-15': ['in_progress', 'fully_paid'],
  'C-16': ['in_progress', 'fully_paid'],
  'C-17': ['fully_paid'],
  'C-18': ['completed', 'fully_paid'],
  'O-01': ['new'],
  'O-03': ['new', 'awaiting_payment'],
  'O-04': ['new', 'awaiting_payment', 'deposit_paid'],
  'O-05': ['awaiting_payment', 'deposit_paid'],
  'O-06': ['*'],
  'O-07': ['deposit_paid', 'in_progress'],
  'O-08': ['deposit_paid', 'in_progress'],
  'O-09': ['in_progress'],
  'O-10': ['in_progress'],
  'O-11': ['in_progress'],
  'O-12': ['*'],
  'C-12': ['*'], // كل الحالات — المتغير يشرح الأثر نفسه
};
const QUOTE_EVENT_STATUS: Record<string, string[]> = {
  'C-01': ['active'],
  'C-02': ['active', 'expired'],
  'O-02': ['*'],
};

function render(event: string, data: Record<string, unknown>): { subject: string; html: string; text: string } {
  const q = data as unknown as QuoteCtx;
  const c = data as unknown as ContractCtx;
  switch (event) {
    case 'C-01': return C01_quoteReady(q);
    case 'C-02': return C02_quoteExpired(q);
    case 'C-03': return C03_bookingReceived(c);
    case 'C-04': return C04_depositHold(c);
    case 'C-05': return C05_receiptReceived(c);
    case 'C-06': return C06_receiptCorrection(c);
    case 'C-07': return C07_holdExpired(c);
    case 'C-08': return C08_bookingConfirmed(c);
    case 'C-09': return C09_contractReady(c);
    case 'C-10': return C10_appointmentUpdated(c);
    case 'C-11': return C11_shootReminder(c);
    case 'C-13': return C13_processingStarted(c);
    case 'C-14': return C14_readyBalance(c);
    case 'C-15': return C15_finalReceiptReceived(c);
    case 'C-16': return C16_finalReceiptCorrection(c);
    case 'C-17': return C17_delivery(c);
    case 'C-18': return C18_retentionReminder(c);
    case 'C-19': return C19_v360Expiry(c);
    case 'C-20': return C20_rating(c);
    case 'O-01': return O01_newOrder(c);
    case 'O-02': return O02_assigned(c);
    case 'O-03': return O03_receiptReview(c);
    case 'O-04': return O04_orderNeedsAction(c);
    case 'O-05': return O05_bookingConfirmed(c);
    case 'O-07': return O07_photographer24h(c);
    case 'O-08': return O08_photographerReminder(c);
    case 'O-09': return O09_filesMissing(c);
    case 'O-10': return O10_qualityReview(c);
    case 'O-11': return O11_deliveryDelayRisk(c);
    case 'O-12': return O12_deliveryClosure(c);
    case 'C-12':
    case 'O-06': {
      const variant = String(data.variant || '');
      if (event === 'C-12') return C12_operationalUpdate(c, variant as C12Variant);
      const o6 = variant as 'cancellation' | 'reschedule' | 'force_majeure' | 'visit_fee' | 'late' | 'no_show';
      if (!['cancellation','reschedule','force_majeure','visit_fee','late','no_show'].includes(o6)) {
        throw new Error('unknown_o06_variant');
      }
      return O06_operationalUpdate(c, o6);
    }
    default: throw new Error(`unknown_event:${event}`);
  }
}

async function isOutdated(req: Req): Promise<boolean> {
  try {
    if (req.entity_type === 'contract' && req.entity_id && CONTRACT_EVENT_STATUS[req.event_type]) {
      const { data } = await db.from('contracts').select('status').eq('id', req.entity_id).maybeSingle();
      if (!data) return true; // الكيان اختفى/ألغي
      const allowed = CONTRACT_EVENT_STATUS[req.event_type];
      return !allowed.includes(String((data as { status: string }).status));
    }
    if (req.entity_type === 'quote' && req.entity_id && QUOTE_EVENT_STATUS[req.event_type]) {
      const { data } = await db.from('quotes').select('status').eq('id', req.entity_id).maybeSingle();
      if (!data) return true;
      const allowed = QUOTE_EVENT_STATUS[req.event_type];
      return allowed[0] !== '*' && !allowed.includes(String((data as { status: string }).status));
    }
  } catch (_e) {
    // عند فشل الفحص نعتبره قديمًا (الأكثر أمانًا)
    return true;
  }
  return false;
}

async function sendViaResend(to: string, toName: string, from: string, subject: string, html: string, text: string) {
  if (!RESEND_API_KEY) {
    // وضع التجهيز: لا مفتاح بعد — يسجل كـsent محليًا بلا إرسال فعلي حتى لا يتكرر لاحقًا
    return { ok: true, dry: true as const, id: null as string | null };
  }
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      html,
      text,
      headers: { 'X-Entity-Ref': 'maawaa-phase1' },
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`resend_${res.status}:${JSON.stringify(body).slice(0, 300)}`);
  return { ok: true as const, dry: false as const, id: (body as { id?: string }).id ?? null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return new Response('method_not_allowed', { status: 405, headers: CORS });

  // حماية: service_role فقط — Bearer parsing صريح + مقارنة Exact
  const m = /^Bearer\s+(.+)$/i.exec((req.headers.get('Authorization') ?? '').trim());
  if (!m || m[1] !== SERVICE_KEY) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: CORS });
  }

  let body: Req;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad_json' }), { status: 400, headers: CORS });
  }

  const version = body.event_version ?? 1;
  const key = `${body.entity_type}:${body.entity_id ?? 'none'}:${body.event_type}:v${version}`;

  // ===== Idempotency: الإدراج هو القفل =====
  const claim = await db
    .from('email_log')
    .insert({
      idempotency_key: key,
      event_type: body.event_type,
      event_version: version,
      entity_type: body.entity_type,
      entity_id: body.entity_id,
      recipient: body.to,
      status: 'pending',
      payload: body.data ?? {},
    })
    .select('id')
    .maybeSingle();

  if (claim.error || !claim.data) {
    return new Response(JSON.stringify({ result: 'skipped_duplicate', key }), { status: 200, headers: CORS });
  }
  const logId = (claim.data as { id: string }).id;

  // مستلم غير صالح → تخطٍّ موثق
  if (!body.to || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(body.to)) {
    await db.from('email_log').update({ status: 'failed', error: 'invalid_recipient' }).eq('id', logId);
    return new Response(JSON.stringify({ result: 'skipped_invalid_recipient', key }), { status: 200, headers: CORS });
  }

  // ===== منع الأحداث القديمة =====
  if (await isOutdated(body)) {
    await db.from('email_log').update({ status: 'skipped_outdated' }).eq('id', logId);
    return new Response(JSON.stringify({ result: 'skipped_outdated', key }), { status: 200, headers: CORS });
  }

  // ===== الرسم + الإرسال =====
  try {
    const rendered = render(body.event_type, body.data);
    const from = body.event_type.startsWith('O-') ? FROM_OPERATIONS : FROM_CUSTOMER;
    const sent = await sendViaResend(body.to, body.to_name ?? '', from, rendered.subject, rendered.html, rendered.text);
    await db.from('email_log').update({
      status: 'sent',
      sent_at: new Date().toISOString(),
      payload: { ...body.data, _resend_id: sent.id, _dry: sent.dry },
    }).eq('id', logId);
    return new Response(JSON.stringify({ result: sent.dry ? 'sent_dry(no RESEND_API_KEY)' : 'sent', key }), {
      status: 200, headers: CORS,
    });
  } catch (e) {
    await db.from('email_log').update({ status: 'failed', error: String(e).slice(0, 500) }).eq('id', logId);
    return new Response(JSON.stringify({ result: 'failed', error: String(e).slice(0, 200) }), {
      status: 500, headers: CORS,
    });
  }
});
