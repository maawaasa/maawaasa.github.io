-- =====================================================
-- مأوى للتصوير العقاري — قاعدة البيانات الكاملة
-- المرحلة 0: الأمان (RLS) + المرحلة 1: الجداول الجديدة
-- انسخ هذا الملف كاملاً والصقه في: Supabase → SQL Editor → New Query
-- =====================================================

-- ==========================================
-- 1) تفعيل RLS على كل الجداول الموجودة
-- ==========================================

ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_services ENABLE ROW LEVEL SECURITY;

-- إنشاء جدول terms إن لم يكن موجوداً
CREATE TABLE IF NOT EXISTS terms (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE terms ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 2) سياسات RLS
-- ==========================================

-- clients: العامة يقدرون يضيفون (نموذج الطلب)، الشركاء فقط يقرؤون/يعدلون
DROP POLICY IF EXISTS "public_insert_clients" ON clients;
CREATE POLICY "public_insert_clients" ON clients FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_select_clients" ON clients;
CREATE POLICY "auth_select_clients" ON clients FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_update_clients" ON clients;
CREATE POLICY "auth_update_clients" ON clients FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_delete_clients" ON clients;
CREATE POLICY "auth_delete_clients" ON clients FOR DELETE TO authenticated USING (true);

-- contracts: العامة يضيفون (نموذج الطلب)، الشركاء يديرون
DROP POLICY IF EXISTS "public_insert_contracts" ON contracts;
CREATE POLICY "public_insert_contracts" ON contracts FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_select_contracts" ON contracts;
CREATE POLICY "auth_select_contracts" ON contracts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_update_contracts" ON contracts;
CREATE POLICY "auth_update_contracts" ON contracts FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_delete_contracts" ON contracts;
CREATE POLICY "auth_delete_contracts" ON contracts FOR DELETE TO authenticated USING (true);

-- contract_services: العامة يضيفون، الشركاء يديرون
DROP POLICY IF EXISTS "public_insert_cs" ON contract_services;
CREATE POLICY "public_insert_cs" ON contract_services FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_select_cs" ON contract_services;
CREATE POLICY "auth_select_cs" ON contract_services FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_delete_cs" ON contract_services;
CREATE POLICY "auth_delete_cs" ON contract_services FOR DELETE TO authenticated USING (true);

-- terms: الشركاء فقط
DROP POLICY IF EXISTS "auth_all_terms" ON terms;
CREATE POLICY "auth_all_terms" ON terms FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 3) الجداول الجديدة (المرحلة 1)
-- ==========================================

-- كاتالوج الخدمات
CREATE TABLE IF NOT EXISTS services_catalog (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_key TEXT NOT NULL UNIQUE,
    service_name TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE services_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_services_catalog" ON services_catalog FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- الفواتير
CREATE TABLE IF NOT EXISTS invoices (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_number TEXT UNIQUE,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE SET NULL,
    client_id BIGINT REFERENCES clients(id) ON DELETE SET NULL,
    amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    paid_amount NUMERIC(10,2) DEFAULT 0,
    status TEXT DEFAULT 'unpaid',
    issue_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_invoices" ON invoices FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- المدفوعات
CREATE TABLE IF NOT EXISTS payments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE CASCADE,
    invoice_id BIGINT REFERENCES invoices(id) ON DELETE SET NULL,
    amount NUMERIC(10,2) NOT NULL,
    method TEXT DEFAULT 'transfer',
    reference TEXT,
    paid_at DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_payments" ON payments FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- المصاريف
CREATE TABLE IF NOT EXISTS expenses (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category TEXT NOT NULL,
    description TEXT,
    amount NUMERIC(10,2) NOT NULL,
    expense_date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_expenses" ON expenses FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- المهام
CREATE TABLE IF NOT EXISTS tasks (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    assigned_to TEXT,
    status TEXT DEFAULT 'pending',
    due_date DATE,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_tasks" ON tasks FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- التقويم/المواعيد
CREATE TABLE IF NOT EXISTS schedule (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    shoot_date DATE NOT NULL,
    start_time TIME,
    end_time TIME,
    location TEXT,
    assigned_to TEXT,
    status TEXT DEFAULT 'scheduled',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE schedule ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_schedule" ON schedule FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- سجل النشاط
CREATE TABLE IF NOT EXISTS activity_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_email TEXT,
    action TEXT NOT NULL,
    entity_type TEXT,
    entity_id BIGINT,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_activity" ON activity_log FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 4) بيانات أولية
-- ==========================================

INSERT INTO services_catalog (service_key, service_name, sort_order) VALUES
    ('photo', 'التصوير الفوتوغرافي HDR', 1),
    ('video', 'الفيديو السينمائي', 2),
    ('drone', 'تصوير الدرون 4K', 3),
    ('vr360', 'الجولات الافتراضية 360°', 4)
ON CONFLICT (service_key) DO NOTHING;

-- ==========================================
-- 5) Trigger لتوليد رقم عقد تلقائي
-- ==========================================
CREATE OR REPLACE FUNCTION generate_contract_number()
RETURNS TRIGGER AS $$
DECLARE
    next_num INT;
    year_str TEXT;
BEGIN
    year_str := EXTRACT(YEAR FROM NEW.contract_date)::TEXT;
    SELECT COALESCE(MAX(
        CAST(REGEXP_MATCHES(NEW.contract_number, '(\d+)$') AS INT[])
    ), 0) + 1 INTO next_num FROM contracts
    WHERE contract_number LIKE 'MWA-' || year_str || '-%';

    NEW.contract_number := 'MWA-' || year_str || '-' || LPAD(next_num::TEXT, 4, '0');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ملاحظة: هذا الـ trigger اختياري، الـ JavaScript في admin.html يولّد الرقم أيضاً
-- لتفعيله: CREATE TRIGGER set_contract_number BEFORE INSERT ON contracts
--           FOR EACH ROW WHEN (NEW.contract_number IS NULL)
--           EXECUTE FUNCTION generate_contract_number();

-- ==========================================
-- ملاحظات مهمة:
-- 1. تأكد من إنشاء 3 حسابات في Authentication → Users
-- 2. بعد تشغيل هذا الـ SQL، admin.html محمي بتسجيل الدخول
-- 3. form.html سيستمر بالعمل (يسمح بـ INSERT للعامة)
-- =====================================================
