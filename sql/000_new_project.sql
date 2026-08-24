-- =====================================================
-- مأوى — ملف التأسيس الكامل لبروجكت Supabase جديد
-- ينشئ: كل الجداول + الحماية + البيانات المبدئية
-- انسخه كاملاً والصقه في: SQL Editor → New Query → Run
-- =====================================================

-- ==========================================
-- 1) الجداول الأساسية (العملاء والعقود)
-- ==========================================
CREATE TABLE IF NOT EXISTS clients (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name TEXT NOT NULL,
    phone_number TEXT,
    email TEXT,
    identity_number TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contracts (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id BIGINT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    contract_number TEXT UNIQUE,
    service_type TEXT,
    total_amount NUMERIC(12,2) DEFAULT 0,
    delivery_days INT DEFAULT 10,
    contract_date DATE DEFAULT CURRENT_DATE,
    status TEXT NOT NULL DEFAULT 'new'
        CHECK (status IN ('new','draft','awaiting_payment','deposit_paid','awaiting_signature','in_progress','fully_paid','completed','cancelled')),
    property_type TEXT,
    property_location TEXT,
    rooms_count TEXT,
    shoot_date DATE,
    notes TEXT,
    payment_method TEXT DEFAULT 'transfer'
        CHECK (payment_method IN ('transfer','cash','card')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contract_services (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    service_name TEXT NOT NULL,
    package_type TEXT DEFAULT 'basic'
);

-- ==========================================
-- 2) جداول الدعم
-- ==========================================
CREATE TABLE IF NOT EXISTS terms (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS services_catalog (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_key TEXT UNIQUE NOT NULL,
    service_name TEXT NOT NULL,
    package_key TEXT NOT NULL,
    package_name TEXT NOT NULL,
    price NUMERIC(12,2) NOT NULL DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS invoices (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE SET NULL,
    invoice_number TEXT UNIQUE,
    amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    vat_amount NUMERIC(12,2) DEFAULT 0,
    total_with_vat NUMERIC(12,2) DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid','paid','partial','cancelled')),
    due_date DATE,
    issued_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE CASCADE,
    invoice_id BIGINT REFERENCES invoices(id) ON DELETE SET NULL,
    amount NUMERIC(12,2) NOT NULL,
    method TEXT DEFAULT 'transfer' CHECK (method IN ('transfer','cash','card')),
    is_deposit BOOLEAN DEFAULT false,
    paid_at TIMESTAMPTZ DEFAULT NOW(),
    note TEXT
);

CREATE TABLE IF NOT EXISTS expenses (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category TEXT NOT NULL DEFAULT 'other',
    description TEXT,
    amount NUMERIC(12,2) NOT NULL,
    spent_at DATE DEFAULT CURRENT_DATE,
    receipt_url TEXT,
    created_by BIGINT
);

CREATE TABLE IF NOT EXISTS tasks (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE SET NULL,
    assigned_to BIGINT,
    due_date DATE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_progress','done','cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS schedule (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT REFERENCES contracts(id) ON DELETE CASCADE,
    employee_id BIGINT,
    job_date DATE NOT NULL,
    start_time TIME,
    end_time TIME,
    location TEXT,
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','done','cancelled','postponed')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS activity_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_email TEXT,
    action TEXT NOT NULL,
    entity TEXT,
    entity_id BIGINT,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==========================================
-- 3) جداول الفريق (المرحلة 1 — نظام الموظفين)
-- ==========================================
CREATE TABLE IF NOT EXISTS employees (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'photographer'
        CHECK (role IN ('photographer', 'admin', 'producer', 'marketer')),
    title TEXT DEFAULT '',
    phone TEXT DEFAULT '',
    email TEXT DEFAULT '',
    hire_date DATE DEFAULT CURRENT_DATE,
    annual_leave_days INT NOT NULL DEFAULT 90,
    is_active BOOLEAN DEFAULT true,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS leave_requests (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    leave_type TEXT NOT NULL DEFAULT 'annual'
        CHECK (leave_type IN ('annual', 'sick', 'emergency', 'unpaid')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    days INT NOT NULL,
    note TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    approved_by BIGINT REFERENCES employees(id) ON DELETE SET NULL,
    decided_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT valid_dates CHECK (end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS assignments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL,
    employee_id BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    role_in_job TEXT NOT NULL DEFAULT 'photographer',
    share_pct NUMERIC(5,2) DEFAULT 70,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (contract_id, employee_id)
);

CREATE TABLE IF NOT EXISTS profit_settings (
    id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    photographer_pct NUMERIC(5,2) DEFAULT 70,
    wafaa_pct NUMERIC(5,2) DEFAULT 10,
    marketing_pct NUMERIC(5,2) DEFAULT 10,
    producers_pct NUMERIC(5,2) DEFAULT 10,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==========================================
-- 4) بيانات مبدئية
-- ==========================================
INSERT INTO employees (name, role, title, sort_order) VALUES
    ('محمد', 'photographer', 'شريك مصور', 1),
    ('مالك', 'photographer', 'شريك مصور', 2),
    ('أسامة', 'photographer', 'شريك مصور', 3),
    ('وفاء', 'admin', 'إدارة، برمجة وتسويق', 4);

INSERT INTO profit_settings (id) VALUES (1);

INSERT INTO terms (content, sort_order) VALUES
    ('يلتزم العقد بأحكام الأنظمة التجارية السعودية ذات العلاقة.', 1),
    ('يتطلب تأكيد الحجز دفع عربون غير مسترد بعد ٢٤ ساعة من الموعد.', 2);

-- ==========================================
-- 5) تفعيل الحماية RLS + السياسات
-- ==========================================
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE services_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE profit_settings ENABLE ROW LEVEL SECURITY;

-- العملاء والعقود: العام يقدر يرسل طلبات (نموذج الموقع)، الفريق فقط يقرأ/يعدل
DROP POLICY IF EXISTS "public_insert_clients" ON clients;
CREATE POLICY "public_insert_clients" ON clients FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_all_clients" ON clients;
CREATE POLICY "auth_all_clients" ON clients FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "public_insert_contracts" ON contracts;
CREATE POLICY "public_insert_contracts" ON contracts FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_all_contracts" ON contracts;
CREATE POLICY "auth_all_contracts" ON contracts FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "public_insert_cs" ON contract_services;
CREATE POLICY "public_insert_cs" ON contract_services FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_all_cs" ON contract_services;
CREATE POLICY "auth_all_cs" ON contract_services FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- باقي الجداول: الفريق فقط
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['terms','services_catalog','invoices','payments','expenses','tasks','schedule','activity_log','employees','leave_requests','assignments','profit_settings']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "auth_all_%s" ON %I', t, t);
        EXECUTE format('CREATE POLICY "auth_all_%s" ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true)', t, t);
    END LOOP;
END $$;

-- ==========================================
-- 6) فهارس
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_contracts_client ON contracts(client_id);
CREATE INDEX IF NOT EXISTS idx_contracts_status ON contracts(status);
CREATE INDEX IF NOT EXISTS idx_leave_employee ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_assignments_contract ON assignments(contract_id);
CREATE INDEX IF NOT EXISTS idx_assignments_employee ON assignments(employee_id);
CREATE INDEX IF NOT EXISTS idx_schedule_date ON schedule(job_date);
CREATE INDEX IF NOT EXISTS idx_employees_active ON employees(is_active);
