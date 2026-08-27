-- مأوى — تحصين دوال PostgreSQL الموجودة فعلياً
-- آمن للتشغيل مرة واحدة أو أكثر.

BEGIN;

-- هذه الدوال تُستدعى من triggers. تثبيت search_path يمنع تغيير حلّ الأسماء
-- عبر إعداد جلسة المتصل، من دون تغيير سلوك العقود الحالي.
ALTER FUNCTION public.generate_contract_number() SET search_path = public, pg_temp;
ALTER FUNCTION public.set_contract_number() SET search_path = public, pg_temp;
ALTER FUNCTION public.update_updated_at() SET search_path = public, pg_temp;

-- الدالة Event Trigger وليست API عامة؛ لا يجب أن تُستدعى من REST/RPC.
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

COMMIT;
