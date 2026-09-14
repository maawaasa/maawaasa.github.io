-- =====================================================
-- VERIFY 018 — READ-ONLY (يُشغَّل بعد اعتماد 018 فقط)
-- كل استعلام يجب أن يطابق النتيجة المتوقعة المكتوبة أمامه.
-- =====================================================

-- [1] الجدول موجود ⇒ payments_table = public.payments
SELECT to_regclass('public.payments') AS payments_table;

-- [2] الأعمدة المطلوبة (7) — يجب أن يرجع: ALL_COLUMNS_OK
SELECT CASE WHEN COUNT(*) = 0 THEN 'ALL_COLUMNS_OK'
            ELSE 'MISSING: ' || string_agg(name, ', ') END AS columns_check
FROM (VALUES ('id'),('contract_id'),('amount'),('method'),
             ('is_deposit'),('note'),('created_at')) AS c(name)
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema='public' AND table_name='payments' AND column_name = c.name);

-- [3] تفصيل الأعمدة والأنواع (للمطابقة البصرية مع 017)
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='payments'
ORDER BY ordinal_position;

-- [4] FK + CHECK + UNIQUE ⇒ يجب أن يشمل:
--     payments_contract_id_fkey → FOREIGN KEY (contract_id) REFERENCES contracts(id)
--     payments_amount_check     → CHECK (amount > 0)
--     payments_method_check     → CHECK (method IN (...))
--     payments_contract_note_unique / قيود الجدول الأخرى
SELECT conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint
WHERE conrelid = 'public.payments'::regclass
ORDER BY conname;

-- [5] الفهارس ⇒ idx_payments_contract + uq_payments_contract_ref (partially)
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND tablename='payments'
ORDER BY indexname;

-- [6] RLS مفعل ⇒ يجب true (وforce اختياري)
SELECT relrowsecurity AS rls_enabled, relforcerowsecurity AS rls_forced
FROM pg_class WHERE oid = 'public.payments'::regclass;

-- [7] لا سياسات إطلاقًا ⇒ يجب 0 صفوف
SELECT policyname, roles FROM pg_policies
WHERE schemaname='public' AND tablename='payments';

-- [8] Privileges ⇒ كل القيم المطلوبة false إلا service_role true
SELECT
  has_table_privilege('anon','public.payments','SELECT')          AS anon_select,      -- f
  has_table_privilege('anon','public.payments','INSERT')          AS anon_insert,      -- f
  has_table_privilege('authenticated','public.payments','SELECT') AS auth_select,      -- f
  has_table_privilege('authenticated','public.payments','INSERT') AS auth_insert,      -- f
  has_table_privilege('authenticated','public.payments','UPDATE') AS auth_update,      -- f
  has_table_privilege('authenticated','public.payments','DELETE') AS auth_delete,      -- f
  has_table_privilege('service_role','public.payments','SELECT')  AS svc_select,       -- t
  has_table_privilege('service_role','public.payments','INSERT')  AS svc_insert,       -- t
  has_table_privilege('service_role','public.payments','UPDATE')  AS svc_update,       -- t
  has_table_privilege('service_role','public.payments','DELETE')  AS svc_delete,       -- t
  has_sequence_privilege('service_role','public.payments_id_seq','USAGE') AS svc_seq;  -- t

-- [9] توقيع 017 لم يتغير وEXECUTE لـservice_role فقط
SELECT p.oid::regprocedure::text AS signature,
       (SELECT array_agg(g.rolname) FROM aclexplode(p.proacl) a
          JOIN pg_roles g ON g.oid = a.grantee
         WHERE a.privilege_type = 'EXECUTE') AS execute_grantees
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='approve_payment_atomic';
