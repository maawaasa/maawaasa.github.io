-- =====================================================
-- مأوى — ترقيع أمني عاجل (SECURITY PATCH)
-- يغلق: حذف/تعديل anon على كل الجداول + قراءة بيانات العملاء
-- الصقه في SQL Editor → Run
-- =====================================================

-- 1) إسقاط كل السياسات المتساهلة القديمة على الجداول الحساسة
DROP POLICY IF EXISTS "public_insert_clients" ON clients;
DROP POLICY IF EXISTS "auth_all_clients" ON clients;
DROP POLICY IF EXISTS "public_insert_contracts" ON contracts;
DROP POLICY IF EXISTS "auth_all_contracts" ON contracts;
DROP POLICY IF EXISTS "public_insert_cs" ON contract_services;
DROP POLICY IF EXISTS "auth_all_cs" ON contract_services;
DROP POLICY IF EXISTS "auth_all_employees" ON employees;
DROP POLICY IF EXISTS "auth_all_leave" ON leave_requests;
DROP POLICY IF EXISTS "auth_all_assignments" ON assignments;
DROP POLICY IF EXISTS "auth_all_profit" ON profit_settings;
DROP POLICY IF EXISTS "auth_all_schedule" ON schedule;
DROP POLICY IF EXISTS "auth_all_terms" ON terms;
DROP POLICY IF EXISTS "auth_all_services_catalog" ON services_catalog;
DROP POLICY IF EXISTS "temp_anon_read_employees" ON employees;

-- 2) العملاء والعقود: anon يقدر يرسل "طلب جديد" فقط (INSERT فقط)
--    ولا يقدر يقرأ/يعدل/يحذف أبداً
CREATE POLICY "anon_insert_clients" ON clients
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_insert_contracts" ON contracts
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_insert_cs" ON contract_services
    FOR INSERT TO anon WITH CHECK (true);

-- 3) الفريق فقط (authenticated) يملك كل شيء
CREATE POLICY "team_all_clients" ON clients
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_contracts" ON contracts
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_cs" ON contract_services
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 4) جداول الإدارة: authenticated فقط (بدون anon نهائياً)
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'employees','leave_requests','assignments','profit_settings',
        'schedule','terms','services_catalog','invoices','payments',
        'expenses','tasks','activity_log'
    ] LOOP
        EXECUTE format('DROP POLICY IF EXISTS "team_all_%s" ON %I', t, t);
        EXECUTE format(
            'CREATE POLICY "team_all_%s" ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true)',
            t, t);
    END LOOP;
END $$;

-- 5) تحقق: هذي الاستعلامات لازم تفشل لاحقاً مع anon
-- (لا تشغلها هنا — فقط تأشير)
