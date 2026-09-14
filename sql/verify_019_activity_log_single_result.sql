-- =====================================================
-- VERIFY 019 — SINGLE RESULT · READ-ONLY (SELECT فقط)
-- استعلام واحد ⇒ صف واحد ⇒ شبكة نتائج واحدة في SQL Editor
-- المتوقع: كل boolean كما يشير اسمه (…_false=false، …_true=true، exists/enabled/zero=true)
-- =====================================================
SELECT
  -- [table / columns]
  to_regclass('public.activity_log') IS NOT NULL                                        AS activity_log_exists,
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='activity_log'
             AND column_name='id' AND data_type='bigint')                               AS id_is_bigint,
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='activity_log'
             AND column_name='action' AND data_type='text' AND is_nullable='NO')        AS action_is_text_not_null,
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='activity_log'
             AND column_name='entity' AND data_type='text')                             AS entity_is_text,
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='activity_log'
             AND column_name='details' AND data_type='jsonb')                           AS details_is_jsonb,
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='activity_log'
             AND column_name='created_at' AND data_type='timestamp with time zone')     AS created_at_is_timestamptz,
  NOT EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='activity_log'
             AND column_name='entity_type')                                             AS entity_type_column_absent,

  -- [RLS]
  COALESCE((SELECT relrowsecurity FROM pg_class
             WHERE oid = to_regclass('public.activity_log')), false)                    AS rls_enabled,
  (SELECT count(*) = 0 FROM pg_policies
    WHERE schemaname='public' AND tablename='activity_log')                             AS policy_count_zero,

  -- [anon privileges]
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('anon','public.activity_log','SELECT') END              AS anon_select_false,
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('anon','public.activity_log','INSERT') END              AS anon_insert_false,

  -- [authenticated privileges — بلا كتابة، وبلا قراءة (لا قارئ في الكود)]
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.activity_log','SELECT') END     AS authenticated_select_false,
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.activity_log','INSERT') END     AS authenticated_insert_false,
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.activity_log','UPDATE') END     AS authenticated_update_false,
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('authenticated','public.activity_log','DELETE') END     AS authenticated_delete_false,

  -- [service_role — append-only: SELECT/INSERT فقط، UPDATE/DELETE غير ممنوحة]
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.activity_log','SELECT') END      AS service_role_select_true,
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.activity_log','INSERT') END      AS service_role_insert_true,
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.activity_log','UPDATE') END      AS service_role_update_false,
  CASE WHEN to_regclass('public.activity_log') IS NULL THEN false
       ELSE has_table_privilege('service_role','public.activity_log','DELETE') END      AS service_role_delete_false,

  -- [identity sequence]
  to_regclass('public.activity_log_id_seq') IS NOT NULL                                 AS sequence_exists,
  CASE WHEN to_regclass('public.activity_log_id_seq') IS NULL THEN false
       ELSE has_sequence_privilege('anon','public.activity_log_id_seq','USAGE') END     AS anon_sequence_usage_false,
  CASE WHEN to_regclass('public.activity_log_id_seq') IS NULL THEN false
       ELSE has_sequence_privilege('authenticated','public.activity_log_id_seq','USAGE') END AS authenticated_sequence_usage_false,
  CASE WHEN to_regclass('public.activity_log_id_seq') IS NULL THEN false
       ELSE has_sequence_privilege('service_role','public.activity_log_id_seq','USAGE') END AS service_role_sequence_usage_true,

  -- [log_email_activity — 014 — EXECUTE service_role فقط]
  to_regprocedure('public.log_email_activity(text,text,text,jsonb)') IS NOT NULL        AS log_email_activity_exists,
  CASE WHEN to_regprocedure('public.log_email_activity(text,text,text,jsonb)') IS NULL THEN false
       ELSE has_function_privilege('anon','public.log_email_activity(text,text,text,jsonb)','EXECUTE') END          AS rpc_anon_execute_false,
  CASE WHEN to_regprocedure('public.log_email_activity(text,text,text,jsonb)') IS NULL THEN false
       ELSE has_function_privilege('authenticated','public.log_email_activity(text,text,text,jsonb)','EXECUTE') END AS rpc_authenticated_execute_false,
  CASE WHEN to_regprocedure('public.log_email_activity(text,text,text,jsonb)') IS NULL THEN false
       ELSE has_function_privilege('service_role','public.log_email_activity(text,text,text,jsonb)','EXECUTE') END  AS rpc_service_role_execute_true,

  -- [فهارس: PK فقط — لا قارئ في الكود]
  (SELECT count(*) = 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='activity_log')                             AS indexes_pk_only,

  -- [ملخصات نصية مختصرة]
  COALESCE((SELECT string_agg(column_name || ':' || data_type, ', ' ORDER BY ordinal_position)
              FROM information_schema.columns
             WHERE table_schema='public' AND table_name='activity_log'), 'MISSING')     AS activity_log_columns,
  COALESCE((SELECT string_agg(conname || ': ' || pg_get_constraintdef(oid), ' | ' ORDER BY conname)
              FROM pg_constraint
             WHERE conrelid = to_regclass('public.activity_log')), 'NONE')              AS activity_log_constraints,
  COALESCE((SELECT string_agg(indexname, ', ' ORDER BY indexname)
              FROM pg_indexes
             WHERE schemaname='public' AND tablename='activity_log'), 'NONE')           AS activity_log_indexes;
