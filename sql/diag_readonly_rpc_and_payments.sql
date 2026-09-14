-- =====================================================
-- DIAG — READ-ONLY (Dashboard → SQL Editor) — لا تنفيذ كتابة
-- يعطي التوقيع الفعلي في Production لـ approve_payment_atomic
-- =====================================================
SELECT
  p.oid::regprocedure::text AS signature,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS result,
  p.prosecdef AS is_security_definer,
  (SELECT array_agg(g.groname) FROM pg_roles g
    JOIN aclexplode(p.proacl) a ON a.grantee = g.oid
    WHERE a.privilege_type = 'EXECUTE') AS execute_grantees
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'approve_payment_atomic';

-- =====================================================
-- DIAG — READ-ONLY — المخطط الفعلي لـ payments
-- =====================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'payments'
ORDER BY ordinal_position;

-- =====================================================
-- DIAG — READ-ONLY — constraints ذات العلاقة (payments + contracts)
-- =====================================================
SELECT 'payments' AS tbl, conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint WHERE conrelid = 'public.payments'::regclass
UNION ALL
SELECT 'contracts' AS tbl, conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint WHERE conrelid = 'public.contracts'::regclass
ORDER BY tbl, conname;
