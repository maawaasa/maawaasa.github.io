-- =====================================================
-- 018 — payments foundation (Minimal · Production-safe · Idempotent)
--
-- لماذا هذا الملف؟
--   Production لا يحتوي public.payments (PGRST205 / 42P01).
--   النسختان الأصليتان غير قابلتين للتطبيق على Production:
--     - sql/000_new_project.sql:89  → أعمدة تتطابق مع 017 لكن contract_id BIGINT
--                                     بينما contracts.id في Production UUID
--     - sql/001_foundation.sql:109  → contract_id BIGINT + أعمدة reference/paid_at
--                                     لا يستخدمها أي كود حالي ولا تطابق 017
--   018 يبني الجدول من الاستخدامات الفعلية فقط (017 + smoke):
--     contract_id · amount · method · is_deposit · note (+ id/created_at قياسية)
--   لا يُنشئ: invoice_id / reference / paid_at — لا كود في المشروع يستخدمها.
--
-- التشغيل: Dashboard → SQL Editor → لصق كامل → Run (تكراره آمن — idempotent)
-- =====================================================

BEGIN;

-- 1) الجدول — أعمدة الاستخدام الفعلي فقط، وأنواع متطابقة مع 017 حرفيًا
CREATE TABLE IF NOT EXISTS public.payments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id UUID NOT NULL REFERENCES public.contracts(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method TEXT NOT NULL DEFAULT 'transfer' CHECK (method IN ('transfer','cash','card')),
    is_deposit BOOLEAN NOT NULL DEFAULT false,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2) فهرس الـFK (Postgres لا ينشئه تلقائيًا) — تستخدمه SUM وduplicate-check في 017
CREATE INDEX IF NOT EXISTS idx_payments_contract ON public.payments(contract_id);

-- 3) حماية مرجع فريد لكل عقد — defense-in-depth مطابق لمنطق duplicate_reference في 017
--    جزئيّة عمدًا: تستثني note الافتراضي الذي يولّده 017 عند غياب المرجع
--    ('approved via approve_payment_atomic (...)') كي لا يتعارض مع أكثر من دفعة بلا مرجع
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_contract_ref
    ON public.payments(contract_id, note)
    WHERE note IS NOT NULL
      AND note NOT LIKE 'approved via approve_payment_atomic%';

-- 4) RLS مفعل بلا أي سياسة ⇒ رفض شامل لكل من لا يملك BYPASSRLS
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- دفاع إضافي: أي سياسة قديمة محتملة (نمط 001) تُساق — الجدول لا يُفتح لـauthenticated
DROP POLICY IF EXISTS "auth_all_payments" ON public.payments;

-- 5) Privileges صريحة (مطابقة لقواعد المستودع: لا PUBLIC/anon/authenticated)
REVOKE ALL ON public.payments FROM PUBLIC;
REVOKE ALL ON public.payments FROM anon;
REVOKE ALL ON public.payments FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO service_role;

-- الـIdentity sequence للاستخدام المباشر عبر REST بـservice_role (الـRPC DEFINER لا يحتاجه)
GRANT USAGE, SELECT ON SEQUENCE public.payments_id_seq TO service_role;
-- لا وصول للـsequence لأي طرف آخر (explicit — لا اعتماد على defaults)
REVOKE ALL ON SEQUENCE public.payments_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE public.payments_id_seq FROM anon;
REVOKE ALL ON SEQUENCE public.payments_id_seq FROM authenticated;

COMMIT;

-- إعادة تحميل كاش PostgREST
NOTIFY pgrst, 'reload schema';
