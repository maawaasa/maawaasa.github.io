-- =====================================================
-- 013b — إغلاق الإدخال المجهول المباشر (نسخة ديناميكية محصّنة)
-- =====================================================
-- لماذا هذا الملف؟
-- تشغيل 013 على الإنتاج طبّق quotes/submit_quote/sanitize_units، لكن سياسات
-- anon-INSERT ما زالت مفتوحة على clients/contracts/contract_services —
-- لأن أسماء السياسات في الإنتاج لا تطابق الأسماء التي أسقطتها 013 نصيًا،
-- وDROP IF EXISTS الصامت لم يفعل شيئًا.
--
-- هذا الملف يسقط ديناميكيًا أي سياسة INSERT/ALL تمنح anon على الجداول الثلاثة
-- مهما كان اسمها، ثم يضمن سياسات INSERT لـauthenticated (admin.html)،
-- ثم يطلب من PostgREST إعادة تحميل الـschema ليظهر quotes وsubmit_quote
-- عبر REST فورًا.
--
-- التشغيل: Supabase → SQL Editor → لصق كامل → Run (تكراره آمن)
-- =====================================================

BEGIN;

-- 1) إسقاط ديناميكي: أي سياسة تمنح anon INSERT (أو ALL تشمل INSERT) على الجداول الثلاثة
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('clients', 'contracts', 'contract_services')
          AND 'anon' = ANY(roles)
          AND cmd IN ('INSERT', 'ALL')
    LOOP
        RAISE NOTICE 'إسقاط سياسة anon: % على %', r.policyname, r.tablename;
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

-- 2) ضمان سياسات INSERT للفريق (authenticated) — admin.html يعتمد عليها
DROP POLICY IF EXISTS "auth_insert_clients" ON public.clients;
CREATE POLICY "auth_insert_clients" ON public.clients
    FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_insert_contracts" ON public.contracts;
CREATE POLICY "auth_insert_contracts" ON public.contracts
    FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_insert_cs" ON public.contract_services;
CREATE POLICY "auth_insert_cs" ON public.contract_services
    FOR INSERT TO authenticated WITH CHECK (true);

-- 3) إعادة تحميل schema الـPostgREST — ليظهر quotes وsubmit_quote عبر REST فورًا
NOTIFY pgrst, 'reload schema';

COMMIT;

-- =====================================================
-- تحقق بعد التشغيل (SQL Editor):
-- SELECT tablename, policyname FROM pg_policies
--  WHERE schemaname='public'
--    AND tablename IN ('clients','contracts','contract_services')
--    AND 'anon' = ANY(roles);
-- ⇒ يجب أن يعيد صفر صفوف.
-- =====================================================
