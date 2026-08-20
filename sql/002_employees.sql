-- =====================================================
-- مأوى — المرحلة 1: الموظفون + الإجازات + التعيينات + توزيع الأرباح
-- نفّذ هذا الملف في: Supabase → SQL Editor → New Query
-- =====================================================

-- ==========================================
-- 1) جدول الموظفين
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
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_all_employees" ON employees;
CREATE POLICY "auth_all_employees" ON employees
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- بيانات مبدئية: الشركاء الثلاثة + الوفاء
INSERT INTO employees (name, role, title, sort_order) VALUES
    ('محمد', 'photographer', 'شريك مصور', 1),
    ('مالك', 'photographer', 'شريك مصور', 2),
    ('أسامة', 'photographer', 'شريك مصور', 3),
    ('وفاء', 'admin', 'إدارة، برمجة وتسويق', 4)
ON CONFLICT DO NOTHING;

-- ==========================================
-- 2) طلبات الإجازات
-- ==========================================
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
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_all_leave" ON leave_requests;
CREATE POLICY "auth_all_leave" ON leave_requests
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 3) تعيين الموظفين على العقود (منفذ الأعمال)
-- ==========================================
CREATE TABLE IF NOT EXISTS assignments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id BIGINT NOT NULL,
    employee_id BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    role_in_job TEXT NOT NULL DEFAULT 'photographer',
    share_pct NUMERIC(5,2) DEFAULT 70,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (contract_id, employee_id)
);
ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_all_assignments" ON assignments;
CREATE POLICY "auth_all_assignments" ON assignments
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 4) إعدادات توزيع الأرباح (نسب مرنة)
-- مصور 70 / وفاء 10 ثابتة / تسويق وتطوير 10-20 / منتجون 10-20
-- ==========================================
CREATE TABLE IF NOT EXISTS profit_settings (
    id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    photographer_pct NUMERIC(5,2) DEFAULT 70,
    wafaa_pct NUMERIC(5,2) DEFAULT 10,
    marketing_pct NUMERIC(5,2) DEFAULT 10,
    producers_pct NUMERIC(5,2) DEFAULT 10,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE profit_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_all_profit" ON profit_settings;
CREATE POLICY "auth_all_profit" ON profit_settings
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

INSERT INTO profit_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

-- ==========================================
-- 5) فهارس
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_leave_employee ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_assignments_contract ON assignments(contract_id);
CREATE INDEX IF NOT EXISTS idx_assignments_employee ON assignments(employee_id);
CREATE INDEX IF NOT EXISTS idx_employees_active ON employees(is_active);
