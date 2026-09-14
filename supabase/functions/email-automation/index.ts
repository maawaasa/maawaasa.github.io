// =====================================================
// MAAWAA — email-automation (Edge Function — مجدولة/يدوية)
// الأحداث الزمنية:
//   C-02 Quote Expired : عروض active تجاوزت valid_until → تعليم expired + إيميل
//   C-07 Hold Expired  : عقود انتهى hold_expires_at دون رفع إيصال → تحرير + إيميل
// قواعد:
//   - Idempotency عبر send-email (مفتاح ثابت للحدث)
//   - رفع الإيصال قبل انتهاء المهلة يلغي الحدث (لا C-07)
//   - لا تُنسخ رسالة لمرحلة قديمة
//
// التشغيل: Supabase Scheduler (كل ساعة) أو استدعاء يدوي بـAUTOMATION_SECRET
// Auth: Exact Bearer match ضد AUTOMATION_SECRET (ثابت — لا auto-rotation)
// verify_jwt=false مقصود: المصادقة داخل الدالة نفسها
// =====================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const AUTOMATION_SECRET = Deno.env.get('AUTOMATION_SECRET')!;
const SITE = 'https://maawaa.sa';

const db = createClient(SUPABASE_URL, SERVICE_KEY);

type QuoteRow = { id: string; quote_number: string; total_amount: number; valid_until: string; clients: { email: string | null } | null };
type ContractRow = {
  id: string; contract_number: string | null; status: string;
  hold_expires_at: string | null; receipt_uploaded_at: string | null;
  shoot_date: string | null; clients: { email: string | null; full_name: string | null } | null;
};

// supabase-js قد يعيد العلاقة ككائن أو مصفوفة حسب الكشف
function one<T>(rel: T | T[] | null | undefined): T | null {
  if (!rel) return null;
  return Array.isArray(rel) ? (rel[0] ?? null) : rel;
}

async function callSendEmail(payload: Record<string, unknown>): Promise<string> {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return await res.text();
}

async function expireQuotes(): Promise<number> {
  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await db
    .from('quotes')
    .select('id, quote_number, total_amount, valid_until, clients(email)')
    .eq('status', 'active')
    .lt('valid_until', today)
    .is('expired_notified_at', null)
    .limit(100);
  if (error || !data) return 0;

  let sent = 0;
  for (const qRaw of data) {
    const q = qRaw as unknown as QuoteRow;
    const to = one(q.clients)?.email ?? '';
    if (!to) {
      await db.from('quotes').update({ status: 'expired', expired_notified_at: new Date().toISOString() }).eq('id', q.id).eq('status', 'active');
      continue;
    }
    // قفل التنفيذ: علّم منتهيًا أولًا لمنع السباق مع أي حدث آخر
    const upd = await db
      .from('quotes')
      .update({ status: 'expired', expired_notified_at: new Date().toISOString() })
      .eq('id', q.id)
      .eq('status', 'active')
      .select('id')
      .maybeSingle();
    if (!upd.data) continue;

    const result = await callSendEmail({
      event_type: 'C-02',
      entity_type: 'quote',
      entity_id: q.id,
      to,
      data: {
        quote_number: q.quote_number,
        total: q.total_amount,
        valid_until: q.valid_until,
        quote_url: `${SITE}/quote.html?ref=${q.id}`,
      },
    });
    sent += result.includes('sent') ? 1 : 0;
  }
  return sent;
}

async function expireHolds(): Promise<number> {
  const now = new Date().toISOString();
  const { data, error } = await db
    .from('contracts')
    .select('id, contract_number, status, hold_expires_at, receipt_uploaded_at, shoot_date, clients(email, full_name)')
    .in('status', ['new', 'awaiting_payment'])
    .not('hold_expires_at', 'is', null)
    .lt('hold_expires_at', now)
    .is('receipt_uploaded_at', null)
    .limit(100);
  if (error || !data) return 0;

  let sent = 0;
  for (const cRaw of data) {
    const c = cRaw as unknown as ContractRow;
    const client = one(c.clients);
    const to = client?.email ?? '';
    if (!to) {
      await db.from('contracts').update({ hold_started_at: null, hold_expires_at: null }).eq('id', c.id).is('receipt_uploaded_at', null);
      continue;
    }
    // قفل التنفيذ: صفّر Hold أولًا — رفع الإيصال قبل انتهاء المهلة يكون قد غيّر الحالة
    const upd = await db
      .from('contracts')
      .update({ hold_started_at: null, hold_expires_at: null })
      .eq('id', c.id)
      .in('status', ['new', 'awaiting_payment'])
      .is('receipt_uploaded_at', null)
      .select('id')
      .maybeSingle();
    if (!upd.data) continue; // رفع إيصال أو تغير حالة قبل المعالجة → لا C-07

    // G) تحرير حجوزات المعدات المرتبطة بالـHold المنتهي
    await db.from('equipment_reservations')
      .update({ status: 'released' })
      .eq('contract_id', c.id)
      .eq('status', 'active');

    const result = await callSendEmail({
      event_type: 'C-07',
      entity_type: 'contract',
      entity_id: c.id,
      to,
      data: {
        contract_number: c.contract_number,
        client_name: client?.full_name,
        shoot_date: c.shoot_date,
        calendar_url: `${SITE}/calculator.html`,
      },
    });
    sent += result.includes('sent') ? 1 : 0;
  }
  return sent;
}

// ===== تذكير 24 ساعة قبل الجلسة: C-11 للعميل + O-07 للمصور =====
async function remindShoot(): Promise<{
  sent: number; c11: number; o07: number; assignments_error: string | null;
}> {
  const pad = (n: number) => String(n).padStart(2, '0');
  const tomorrow = (() => { const d = new Date(Date.now() + 86400_000); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; })();
  // العقود فقط — بلا embed assignments: لا FK بين contracts وassignments في Production
  // (كان embed يرمي PGRST200 ويُسقط الاستعلام كله ⇒ صفر تذكيرات بصمت)
  const { data, error } = await db
    .from('contracts')
    .select('id, contract_number, status, shoot_date, service_type, property_location, clients(email, full_name)')
    .in('status', ['deposit_paid', 'in_progress'])
    .eq('shoot_date', tomorrow)
    .limit(100);
  if (error || !data) {
    return { sent: 0, c11: 0, o07: 0, assignments_error: 'contracts_query_failed: ' + String(error?.message ?? '').slice(0, 200) };
  }

  // المصورون: استعلام ثانٍ عبر علاقة assignments→employees (مؤكدة تعمل)
  // فشل هذا الاستعلام لا يمنع C-11 — يُسجل صراحة ويُعتبر O-07 غير متاح
  const photographerByContract = new Map<string, { name: string | null; email: string | null }>();
  const contractIds = (data as Array<{ id: string }>).map((c) => c.id);
  let assignmentsAvailable = true;
  if (contractIds.length > 0) {
    const { data: asg, error: asgError } = await db
      .from('assignments')
      .select('contract_id, employees(id, name, email)')
      .in('contract_id', contractIds);
    if (asgError || !asg) {
      assignmentsAvailable = false;
      console.error('assignments_lookup_failed — O-07 غير متاح، C-11 مستمر:',
        String(asgError?.message ?? asgError).slice(0, 300));
    } else {
      type AssignmentRow = { contract_id: string; employees: { id: number; name: string | null; email: string | null } | null };
      for (const aRaw of asg as unknown as AssignmentRow[]) {
        const emp = one(aRaw.employees);
        if (emp?.email) photographerByContract.set(aRaw.contract_id, { name: emp.name, email: emp.email });
      }
    }
  }

  let sent = 0; let c11Sent = 0; let o07Sent = 0;
  for (const rowRaw of data) {
    const c = rowRaw as unknown as {
      id: string; contract_number: string | null; shoot_date: string | null;
      service_type: string | null; property_location: string | null;
      clients: { email: string | null; full_name: string | null } | null;
    };
    const client = one(c.clients);

    if (client?.email) {
      const res = await callSendEmail({
        event_type: 'C-11', entity_type: 'contract', entity_id: c.id, to: client.email,
        data: {
          contract_number: c.contract_number, client_name: client.full_name,
          shoot_date: c.shoot_date, location: c.property_location,
          maps_url: `${SITE}/calculator.html`,
        },
      });
      if (res.includes('sent')) { sent++; c11Sent++; }
    }
    // O-07 فقط عند توفر بريد مصور صالح لهذا العقد — مستقل عن C-11
    const photographer = photographerByContract.get(c.id) ?? null;
    if (photographer?.email) {
      const res = await callSendEmail({
        event_type: 'O-07', entity_type: 'contract', entity_id: c.id, to: photographer.email,
        data: {
          contract_number: c.contract_number, photographer_name: photographer.name,
          shoot_date: c.shoot_date, services: c.service_type, location: c.property_location,
          maps_url: `${SITE}/calculator.html`,
        },
      });
      if (res.includes('sent')) { sent++; o07Sent++; }
    } else if (!assignmentsAvailable) {
      console.error('O-07_skipped_no_assignments_lookup contract=', c.id);
    }
  }
  return {
    sent, c11: c11Sent, o07: o07Sent,
    assignments_error: assignmentsAvailable ? null : 'assignments_lookup_failed',
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });

  // Auth gate — Exact Bearer match ضد AUTOMATION_SECRET فقط
  // (ثابت — لا auto-rotation — لا يعتمد على service_role)
  const m = /^Bearer\s+(.+)$/i.exec((req.headers.get('Authorization') ?? '').trim());
  const cred = m?.[1] ?? '';
  if (!cred || cred !== AUTOMATION_SECRET) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  // ?auth_probe=1 ⇒ تحقق auth فقط — صفر آثار جانبية (لا معالجة rows)
  const url = new URL(req.url);
  if (url.searchParams.get('auth_probe') === '1') {
    return new Response(JSON.stringify({ ok: true, auth_probe: true }), {
      status: 200, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const quotesExpired = await expireQuotes();
  const holdsExpired = await expireHolds();
  const shoot = await remindShoot();

  return new Response(
    JSON.stringify({
      ok: true,
      quotes_expired: quotesExpired,
      holds_expired: holdsExpired,
      shoot_c11_sent: shoot.c11,
      shoot_o07_sent: shoot.o07,
      assignments_error: shoot.assignments_error,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }
  );
});
