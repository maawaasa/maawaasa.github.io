-- =====================================================
-- VERIFY 018 — SINGLE RESULT · READ-ONLY (SELECT فقط)
-- استعلام واحد ⇒ صف واحد ⇒ شبكة نتائج واحدة في SQL Editor
-- المتوقع: كل boolean كما يشير اسمه (…_false=false، …_true=true، exists/enabled/zero=true)
-- =====================================================
SELECT
  -- [table / columns]
  to_regclass('public.payments') IS NOT NULL                                            AS payments_table_exists,
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='payments'
             AND column_name='contract_id' AND data_type='uuid')                        AS contract_id_is_uuid,
  EXISTS (SELECT 1 FROM pg_constraint c
            JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attname = 'contract_id'
           WHERE c.conrelid = to_regclass('public.payments')
             AND c.contype = 'f'
             AND c.confrelid = to_regclass('public.contracts')
             AND a.attnum = ANY (c.conkey))                                             AS contract_fk_exists,
  EXISTS (SELECT 1 FROM pg_constraint
           WHERE conrelid = to_regclass('public.payments') AND contype = 'c'
             AND pg_get_constraintdef(oid) ILIKE '%amount%>%')                          AS amount_check_exists,
  EXISTS (SELECT 1 FROM pg_constraint
           WHERE conrelid = to_regclass('public.payments') AND contype = 'c'
             AND pg_get_constraintdef(oid) ILIKE '%method%')                            AS method_check_exists,
  EXISTS (SELECT 1 FROM pg_indexes
           WHERE schemaname='public' AND tablename='payments'
             AND (indexname = 'uq_payments_contract_ref'
               OR (indexdef ILIKE 'CREATE UNIQUE INDEX%'
                   AND indexdef ILIKE '%(contract_id, note)%'
                   AND indexdef ILIKE '%WHERE%')))                                      AS unique_reference_index_exists,

  -- [RLS]
  COALESCE((SELECT relrowsecurity FROM pg_class
             WHERE oid = to_regclass('public.payments')), false)                        AS rls_enabled,
  (SELECT count(*) = 0 FROM pg_policies
    WHERE schemaname='public' AND tablename='payments')                                 AS policy_count_zero,

  -- [anon privileges]
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('anon','public.payments','SELECT')  END                 AS anon_select_false,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('anon','public.payments','INSERT')  END                 AS anon_insert_false,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('anon','public.payments','UPDATE')  END                 AS anon_update_false,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('anon','public.payments','DELETE')  END                 AS anon_delete_false,

  -- [authenticated privileges]
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.payments','SELECT')  END        AS authenticated_select_false,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.payments','INSERT')  END        AS authenticated_insert_false,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.payments','UPDATE')  END        AS authenticated_update_false,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.payments','DELETE')  END        AS authenticated_delete_false,

  -- [service_role privileges]
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.payments','SELECT')  END         AS service_role_select_true,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.payments','INSERT')  END         AS service_role_insert_true,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.payments','UPDATE')  END         AS service_role_update_true,
  CASE WHEN to_regclass('public.payments') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.payments','DELETE')  END         AS service_role_delete_true,

  -- [identity sequence]
  to_regclass('public.payments_id_seq') IS NOT NULL                                     AS sequence_exists,
  CASE WHEN to_regclass('public.payments_id_seq') IS NULL THEN false
       ELSE has_sequence_privilege('anon','public.payments_id_seq','USAGE') END         AS anon_sequence_usage_false,
  CASE WHEN to_regclass('public.payments_id_seq') IS NULL THEN false
       ELSE has_sequence_privilege('authenticated','public.payments_id_seq','USAGE') END AS authenticated_sequence_usage_false,
  CASE WHEN to_regclass('public.payments_id_seq') IS NULL THEN false
       ELSE has_sequence_privilege('service_role','public.payments_id_seq','USAGE') END AS service_role_sequence_usage_true,

  -- [017 RPC]
  to_regprocedure('public.approve_payment_atomic(uuid,numeric,text,text)') IS NOT NULL  AS approve_payment_rpc_exists,
  CASE WHEN to_regprocedure('public.approve_payment_atomic(uuid,numeric,text,text)') IS NULL THEN false
       ELSE has_function_privilege('anon','public.approve_payment_atomic(uuid,numeric,text,text)','EXECUTE') END          AS rpc_anon_execute_false,
  CASE WHEN to_regprocedure('public.approve_payment_atomic(uuid,numeric,text,text)') IS NULL THEN false
       ELSE has_function_privilege('authenticated','public.approve_payment_atomic(uuid,numeric,text,text)','EXECUTE') END AS rpc_authenticated_execute_false,
  CASE WHEN to_regprocedure('public.approve_payment_atomic(uuid,numeric,text,text)') IS NULL THEN false
       ELSE has_function_privilege('service_role','public.approve_payment_atomic(uuid,numeric,text,text)','EXECUTE') END  AS rpc_service_role_execute_true,

  -- [ملخصات نصية مختصرة]
  COALESCE((SELECT string_agg(column_name || ':' || data_type, ', ' ORDER BY ordinal_position)
              FROM information_schema.columns
             WHERE table_schema='public' AND table_name='payments'), 'MISSING')         AS payments_columns,
  COALESCE((SELECT string_agg(conname || ': ' || pg_get_constraintdef(oid), ' | ' ORDER BY conname)
              FROM pg_constraint
             WHERE conrelid = to_regclass('public.payments')), 'NONE')                  AS payments_constraints,
  COALESCE((SELECT string_agg(indexname || ': '
                       || CASE WHEN indexdef ILIKE 'CREATE UNIQUE%' THEN '[unique] ' ELSE '' END
                       || substring(indexdef FROM position('(' IN indexdef)),
                    ' | ' ORDER BY indexname)
              FROM pg_indexes
             WHERE schemaname='public' AND tablename='payments'), 'NONE')               AS payments_indexes;
