-- =====================================================
-- 019 — activity_log foundation (Minimal · Production-safe · Idempotent)
--
-- لماذا هذا الملف؟
--   Production لا يحتوي public.activity_log (42P01 — أثبته التشخيص المباشر).
--   كل مسارات الدفع الصالحة في 017 تصل حتى INSERT activity_log ثم تفشل
--   ⇒ Rollback كامل للدفعة (لحسن الحظ — لكن لا اعتماد مالي يُسجل).
--
-- أين كان يفترض أن يُنشأ؟
--   - sql/000_new_project.sql:134  (بعمود entity)   — جيل قديم لم يُطبق على Production
--   - sql/001_foundation.sql:167   (بعمود entity_type + سياسة auth_all_activity مفتوحة)
--   الجيلان بنفس مشكلة payments: bootstrap قديم لم يصل لإنتاج UUID.
--
-- الاستخدامات الفعلية الحالية (كلها INSERT، لا يوجد أي قارئ في الكود):
--   - 017 approve_payment_atomic:  (action, entity, details) أساسي + fallback entity_type
--   - 014 log_email_activity:      (action, entity, details) أساسي + fallback entity_type
--   - coverage-confirm (Edge):     (action, entity, details)
--   - payment-approve (Edge):      (action, entity, details)
--   - receipt-submit (Edge):       عبر log_email_activity فقط
--   ⇒ الشكل CANONICAL هو (action, entity, details) — في كل المسارات الأساسية.
--   entity_id لا يستخدمه أي كاتب (014 يدمجه عمدًا داخل details لأن عمود BIGINT
--   لا يتسع لمعرفات UUID) · user_email لا يستخدمه أي كاتب · لا يوجد أي قارئ.
--
-- القرار: عمود canonical واحد هو entity — لا entity_type (لا غموض تصميمي).
--   الـfallbacks في 017/014 تصبح مسارات ميتة دفاعية — بلا أي تعديل عليهما.
--
-- التشغيل: Dashboard → SQL Editor → لصق كامل → Run (تكراره آمن — idempotent)
-- =====================================================

BEGIN;

-- 1) الجدول — أعمدة الاستخدام الفعلي فقط
CREATE TABLE IF NOT EXISTS public.activity_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    action TEXT NOT NULL,
    entity TEXT,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2) لا فهارس إضافية: لا يوجد أي قارئ في الكود الحالي (PK كافٍ)
--    يُضاف فهرس زمني فقط عند ظهور أول قارئ فعلي.

-- 3) RLS مفعل بلا أي سياسة ⇒ رفض شامل لكل من لا يملك BYPASSRLS
ALTER TABLE public.activity_log ENABLE ROW LEVEL SECURITY;

-- دفاع إضافي: سياسات الجيل القديم المفتوحة (نمط 001/004) تُساق إن وُجدت
DROP POLICY IF EXISTS "auth_all_activity" ON public.activity_log;
DROP POLICY IF EXISTS "team_all_activity_log" ON public.activity_log;

-- 4) Privileges صريحة: سجل داخلي append-only — SELECT/INSERT لـservice_role فقط
--    لا UPDATE ولا DELETE لأي دور (إن لزم تنظيف صفوف اختبار يومًا: SQL Editor بصلاحية المالك فقط)
REVOKE ALL ON public.activity_log FROM PUBLIC;
REVOKE ALL ON public.activity_log FROM anon;
REVOKE ALL ON public.activity_log FROM authenticated;
GRANT SELECT, INSERT ON public.activity_log TO service_role;
REVOKE UPDATE, DELETE ON public.activity_log FROM service_role;

-- الـIdentity sequence للاستخدام المباشر عبر REST بـservice_role (الـDEFINER لا يحتاجه)
GRANT USAGE, SELECT ON SEQUENCE public.activity_log_id_seq TO service_role;
REVOKE ALL ON SEQUENCE public.activity_log_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE public.activity_log_id_seq FROM anon;
REVOKE ALL ON SEQUENCE public.activity_log_id_seq FROM authenticated;

COMMIT;

-- إعادة تحميل كاش PostgREST
NOTIFY pgrst, 'reload schema';
