-- =====================================================
-- مأوى — ترقيع أمني عاجل (نسخة آمنة تتخطى الجداول غير الموجودة)
-- الصقه في SQL Editor → Run
-- =====================================================

-- 1) إسقاط السياسات القديمة المتساهلة (فقط على الموجود فعلاً)
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
DROP POLICY IF EXISTS "temp_anon_read_employees" ON employees;

-- 2) العملاء والعقود: anon يرسل طلبات فقط (INSERT بدون قراءة)
CREATE POLICY "anon_insert_clients" ON clients
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_insert_contracts" ON contracts
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_insert_cs" ON contract_services
    FOR INSERT TO anon WITH CHECK (true);

-- 3) الفريق فقط يملك كل شيء
CREATE POLICY "team_all_clients" ON clients
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_contracts" ON contracts
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_cs" ON contract_services
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_employees" ON employees
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_leave" ON leave_requests
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_assignments" ON assignments
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_profit" ON profit_settings
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "team_all_schedule" ON schedule
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
