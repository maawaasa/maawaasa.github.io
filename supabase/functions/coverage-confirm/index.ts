// =====================================================
// MAAWAA — coverage-confirm (Edge Function — ملاك/خدمة فقط)
// الخطوة المحورية: تأكيد تغطية الجلسة
//   1) تحقق الحالة: الطلب في 'new' فقط (لا مرحلة قديمة)
//   2) تعيين المصور المسؤول بشكل محايد (assignments)
//   3) تحويل الحالة إلى awaiting_payment + بدء Hold لـ24 ساعة
//   4) توليد رابط رفع إيصال آمن وإرسال C-04 للعميل
//   5) Activity Log
// Auth: service_role أو مستخدم authenticated (ملاك عبر admin)
// =====================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SITE = 'https://maawaa.sa';

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// تفويض فعلي: التمييز بين غير مصادق (401) ومصادق غير عضو فريق (403)
async function resolveTeamMember(
  db: any,
  jwt: string
): Promise<'ok' | 'unauthenticated' | 'not_member'> {
  const { data, error } = await db.auth.getUser(jwt);
  const u = data?.user;
  if (error || !u) return 'unauthenticated';
  const email = (u.email ?? '').toLowerCase();
  const conds = [`auth_user_id.eq.${u.id}`];
  if (email) conds.push(`email.ilike.${email}`);
  const { data: emp } = await db.from('employees')
    .select('id')
    .eq('is_active', true)
    .or(conds.join(','))
    .maybeSingle();
  return emp ? 'ok' : 'not_member';
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

  // مصادقة مزدوجة: service_role أو عضو فريق نشط
  // 401 = غير مصادق (توكن غير صالح/anon) · 403 = مصادق غير عضو فريق
  if (!isService) {
    if (!cred) return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: CORS });
    const member = await resolveTeamMember(db, cred);
    if (member === 'unauthenticated') {
      return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: CORS });
    }
    if (member === 'not_member') {
      return new Response(JSON.stringify({ error: 'forbidden_not_team_member' }), { status: 403, headers: CORS });
    }
  }

  let body: { contract_id?: string; photographer_employee_id?: number | null; equipment_note?: string; start_time?: string; end_time?: string };
  try { body = await req.json(); } catch { return new Response(JSON.stringify({ error: 'bad_json' }), { status: 400, headers: CORS }); }
  const contractId = String(body.contract_id || '');
  if (!contractId) return new Response(JSON.stringify({ error: 'contract_id_required' }), { status: 400, headers: CORS });

  // 1) الطلب الحالي — يجب أن يكون في 'new' (منع المراحل القديمة)
  const { data: contract } = await db.from('contracts')
    .select('id, contract_number, status, client_id, total_amount, service_type, shoot_date, property_location, shoot_start_time, shoot_end_time')
    .eq('id', contractId).maybeSingle();
  if (!contract) return new Response(JSON.stringify({ error: 'contract_not_found' }), { status: 404, headers: CORS });
  const c = contract as { id: string; contract_number: string | null; status: string; client_id: string; total_amount: number; service_type: string | null; shoot_date: string | null; property_location: string | null; shoot_start_time: string | null; shoot_end_time: string | null };
  if (c.status !== 'new') {
    return new Response(JSON.stringify({ error: 'outdated_state', status: c.status }), { status: 409, headers: CORS });
  }

  // 2) تعيين المصور المسؤول (محايد — إن لم يُحدد يدويًا يُختار مصور نشط بالتناوب)
  let photographerId = body.photographer_employee_id ?? null;
  if (!photographerId) {
    const { data: employees } = await db.from('employees')
      .select('id').eq('role', 'photographer').eq('is_active', true).order('sort_order');
    const list = (employees ?? []) as Array<{ id: number }>;
    if (list.length) {
      const { count } = await db.from('assignments').select('id', { count: 'exact', head: true });
      photographerId = list[(count ?? 0) % list.length].id;
    }
  }
  if (photographerId) {
    await db.from('assignments').upsert(
      { contract_id: c.id, employee_id: photographerId, role_in_job: 'photographer' },
      { onConflict: 'contract_id,employee_id' }
    );
  }
  let photographerName: string | null = null;
  if (photographerId) {
    const { data: emp } = await db.from('employees').select('name').eq('id', photographerId).maybeSingle();
    photographerName = (emp as { name: string } | null)?.name ?? null;
  }

  // ===== نافذة الجلسة — المصدر بالترتيب: body → contracts (من Booking Request) → يوم كامل =====
  // الموقعتان تُحفظان Structured في contracts (submit_lead p_shoot_start_time) منذ 016
  const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
  const bodyStart = String((body as { start_time?: string }).start_time ?? '');
  const bodyEnd = String((body as { end_time?: string }).end_time ?? '');
  let startTime = (bodyStart || String(c.shoot_start_time ?? '')).slice(0, 5);
  let endTime = (bodyEnd || String(c.shoot_end_time ?? '')).slice(0, 5);
  let timeSource: 'body' | 'contract' | 'full_day_fallback' = 'contract';
  if (bodyStart) timeSource = 'body';
  if (!TIME_RE.test(startTime) || !TIME_RE.test(endTime) || endTime <= startTime) {
    // Fallback محافظ: يوم كامل — يمنع التعارض ولا يعطل الإنتاج (يُستبدل تلقائيًا
    // بمجرد حفظ وقت البداية من طلب الحجز). لا نرجع 400 في Production.
    startTime = '00:00'; endTime = '23:59';
    timeSource = 'full_day_fallback';
  }

  // ===== Final Availability Check — تعارض زمني فعلي وليس حظر يوم كامل =====
  // المقارنة: [start_time → end_time] للجلسة الجديدة مقابل جلسات المصور
  // الموجودة في schedule لنفس التاريخ (غير الملغاة/المؤجلة).
  // شرط التداخل: existing.start < new.end AND COALESCE(existing.end,'23:59') > new.start
  // استبعاد الجلسة الحالية: contract_id.is.null أو contract_id.neq الحالي
  // (NULL-safe — الصفوف بلا عقد مثل الأوقات المحجوبة يدويًا تُعتبر تعارضًا صحيحًا)
  // Fail-closed: أي خطأ في استعلام التوفر ⇒ 500 ولا يبدأ Hold أبدًا
  if (photographerId && c.shoot_date) {
    const { data: conflicts, error: conflictErr } = await db.from('schedule')
      .select('id, contract_id, start_time, end_time')
      .eq('employee_id', photographerId)
      .eq('job_date', c.shoot_date)
      .not('status', 'in', '("cancelled","postponed")')
      .or(`contract_id.is.null,contract_id.neq.${c.id}`)
      .lt('start_time', endTime)
      .or(`end_time.is.null,end_time.gt.${startTime}`)
      .limit(1);
    if (conflictErr) {
      // Fail-closed: لا نبدأ Hold على فحص توفر فاشل
      return new Response(JSON.stringify({
        error: 'availability_check_failed',
        detail: conflictErr.message,
      }), { status: 500, headers: CORS });
    }
    if (conflicts && conflicts.length > 0) {
      const conflict = conflicts[0] as { id: number; contract_id: number | string; start_time: string | null; end_time: string | null };
      return new Response(JSON.stringify({
        error: 'photographer_unavailable',
        detail: 'تداخل زمني مع جلسة أخرى لنفس المصور في نفس التاريخ',
        conflict: { schedule_id: conflict.id, contract_id: conflict.contract_id, start_time: conflict.start_time, end_time: conflict.end_time },
        proposed: { date: c.shoot_date, start_time: startTime, end_time: endTime },
      }), { status: 409, headers: CORS });
    }
  }

  // ===== Equipment MVP — تحقق التوفر ثم الحجز (قبل بدء الـHold) =====
  // منع التداخل مضمون بقيد DB: equipment_no_double_booking (EXCLUDE gist)
  const requiredEquip: Array<{ id: string; name: string }> = [];
  try {
    const { data: reqRows } = await db.from('contract_equipment')
      .select('equipment_id, equipment(id, name, active)')
      .eq('contract_id', c.id);
    for (const r of (reqRows ?? []) as unknown as Array<{ equipment_id: string; equipment: { id: string; name: string; active: boolean } | Array<{ id: string; name: string; active: boolean }> | null }>) {
      const eq = Array.isArray(r.equipment) ? r.equipment[0] ?? null : r.equipment;
      if (eq?.active) requiredEquip.push({ id: eq.id, name: eq.name });
    }
  } catch { /* جدول المعدات غير موجود بعد ⇒ لا معدات مطلوبة */ }

  const insertedReservations: string[] = [];
  function buildWindowIso(date: string, time: string): string {
    return `${date}T${time}:00+03:00`;
  }
  const windowStartIso = c.shoot_date ? buildWindowIso(c.shoot_date, startTime) : '';
  const windowEndIso = c.shoot_date ? buildWindowIso(c.shoot_date, endTime) : '';

  if (requiredEquip.length && c.shoot_date) {
    for (const eq of requiredEquip) {
      const { data: clash } = await db.from('equipment_reservations')
        .select('id, contract_id')
        .eq('equipment_id', eq.id)
        .eq('status', 'active')
        .neq('contract_id', c.id)
        .lt('start_at', windowEndIso)
        .gt('end_at', windowStartIso)
        .limit(1);
      if (clash && clash.length > 0) {
        if (insertedReservations.length) {
          await db.from('equipment_reservations').delete().in('id', insertedReservations);
        }
        return new Response(JSON.stringify({
          error: 'equipment_unavailable',
          detail: `قطعة المعدات «${eq.name}» محجوزة في نفس الفترة`,
          equipment: { id: eq.id, name: eq.name },
          proposed: { date: c.shoot_date, start_time: startTime, end_time: endTime },
        }), { status: 409, headers: CORS });
      }
      const ins = await db.from('equipment_reservations').insert({
        contract_id: c.id,
        equipment_id: eq.id,
        start_at: windowStartIso,
        end_at: windowEndIso,
        status: 'active',
      }).select('id').single();
      if (ins.error) {
        // تداخل سباقي (قيد EXCLUDE) — نظف الدفعة وارفض
        if (insertedReservations.length) {
          await db.from('equipment_reservations').delete().in('id', insertedReservations);
        }
        return new Response(JSON.stringify({
          error: 'equipment_unavailable',
          detail: `قطعة المعدات «${eq.name}» حُجزت للتو — أعد المحاولة بمعدات أخرى`,
          equipment: { id: eq.id, name: eq.name },
        }), { status: 409, headers: CORS });
      }
      insertedReservations.push(String((ins.data as { id: string }).id));
    }
  }

  // 3) الحالة + Hold 24 ساعة (قفل شرطي — منع سباق تأكيدَين)
  const now = new Date();
  const expires = new Date(now.getTime() + 24 * 3600_000);
  const upd = await db.from('contracts')
    .update({
      status: 'awaiting_payment',
      hold_started_at: now.toISOString(),
      hold_expires_at: expires.toISOString(),
      deposit_review_status: null,
    })
    .eq('id', c.id)
    .eq('status', 'new')
    .select('id')
    .maybeSingle();
  if (!upd.data) {
    // إطلاق حجوزات المعدات — الـHold لم يبدأ فعليًا
    if (insertedReservations.length) {
      await db.from('equipment_reservations').update({ status: 'released' }).in('id', insertedReservations);
    }
    return new Response(JSON.stringify({ error: 'outdated_state', detail: 'changed_concurrently' }), { status: 409, headers: CORS });
  }

  // 4) بريد العميل + رابط رفع الإيصال الآمن + C-04
  const { data: client } = await db.from('clients').select('email, full_name').eq('id', c.client_id).maybeSingle();
  const email = (client as { email: string | null } | null)?.email ?? '';
  let depositUrl = `${SITE}/receipt.html`;
  let tokenNote = 'no_email_or_token_skipped';
  if (email) {
    const raw = crypto.getRandomValues(new Uint8Array(32));
    const token = [...raw].map((b) => b.toString(16).padStart(2, '0')).join('');
    const tokenHash = await sha256Hex(token);
    const ins = await db.from('action_tokens').insert({
      token_hash: tokenHash,
      purpose: 'deposit_receipt',
      entity_type: 'contract',
      entity_id: c.id,
      expires_at: new Date(now.getTime() + 24 * 3600_000).toISOString(), // = مدة الـHold بالضبط
    }).select('id').single();
    if (!ins.error) {
      depositUrl = `${SITE}/receipt.html?t=${token}&p=deposit_receipt`;
      tokenNote = 'token_created';
    }
    await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-email`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        event_type: 'C-04',
        entity_type: 'contract',
        entity_id: c.id,
        to: email,
        to_name: (client as { full_name: string | null } | null)?.full_name ?? '',
        data: {
          contract_number: c.contract_number,
          client_name: (client as { full_name: string | null } | null)?.full_name,
          total: c.total_amount,
          deposit: Math.round(Number(c.total_amount) * 0.25),
          remaining: Number(c.total_amount) - Math.round(Number(c.total_amount) * 0.25),
          services: c.service_type,
          shoot_date: c.shoot_date,
          location: c.property_location,
          deposit_upload_url: depositUrl,
        },
      }),
    }).then((r) => r.text()).catch(() => 'send_failed');
  }

  // 5) Activity Log
  try {
    await db.from('activity_log').insert({
      action: 'coverage_confirmed',
      entity: 'contracts',
      details: {
        contract_id: c.id,
        contract_number: c.contract_number,
        photographer_employee_id: photographerId,
        photographer_name: photographerName,
        hold_expires_at: expires.toISOString(),
        availability_window: startTime ? { date: c.shoot_date, start_time: startTime, end_time: endTime } : null,
        equipment_note: body.equipment_note ?? null,
      },
    });
  } catch { /* اختياري */ }

  return new Response(JSON.stringify({
    ok: true,
    contract_number: c.contract_number,
    status: 'awaiting_payment',
    hold_expires_at: expires.toISOString(),
    assigned_photographer: photographerName,
    customer_email_sent: email ? 'yes' : tokenNote,
    checks: {
      contract_status: 'ok',
      photographer_schedule: timeSource === 'full_day_fallback'
        ? 'date_only_fallback'
        : (photographerId && c.shoot_date ? 'checked_time_overlap' : 'skipped'),
      equipment: requiredEquip.length ? `reserved(${insertedReservations.length})` : 'none_required',
      time_source: timeSource,
    },
  }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
});
