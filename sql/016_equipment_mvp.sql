-- =====================================================
-- 016 — Equipment MVP + أزمنة الجلسة + submit_lead الموسعة
-- التشغيل: Supabase → SQL Editor → لصق كامل → Run (مرة واحدة، تكراره آمن)
--
-- النطاق (Equipment MVP فقط — بلا Dashboard):
--   A) كتالوج معدات فعلي (id/name/type/active)
--   B) ربط المعدات المطلوبة بالطلب (contract_equipment)
--   C) حجز زمني للمعدات (equipment_reservations) بحالة active/released/cancelled
--   D) منع التداخل على مستوى قاعدة البيانات:
--      EXCLUDE USING gist على نفس القطعة مع تداخل المدى الزمني
--      (آمن تحت concurrency — أقوى من فحص JavaScript)
--   E) أزمنة الجلسة: contracts.shoot_start_time / shoot_end_time
--      + submit_lead تقبلها من طلب الحجز (Calculator يجمع وقت البداية)
-- =====================================================

BEGIN;

-- ==========================================
-- 1) كتالوج المعدات
-- ==========================================
CREATE TABLE IF NOT EXISTS equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    type TEXT NOT NULL
        CHECK (type IN ('camera','lens','drone','gimbal','vr360','lighting','other')),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE equipment ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_equipment" ON public.equipment;
-- Phase 1: لا سياسات anon/authenticated — التشغيل حصريًا عبر service_role

-- ⚠️ لا تُدرج أي معدات افتراضية هنا — تعبئة الـInventory تتم عبر:
--    sql/016b_equipment_seed_example.sql (اختياري — بعد اعتماد المعدات الفعلية من المالك)

-- ==========================================
-- 2) المعدات المطلوبة لكل طلب
-- ==========================================
CREATE TABLE IF NOT EXISTS contract_equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    equipment_id UUID NOT NULL REFERENCES equipment(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (contract_id, equipment_id)
);

ALTER TABLE contract_equipment ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_contract_equipment" ON public.contract_equipment;
-- Phase 1: لا سياسات anon/authenticated — التشغيل حصريًا عبر service_role

-- ==========================================
-- 3) الحجوزات الزمنية للمعدات
--    منع التداخل بقيد قاعدة بيانات (EXCLUDE + btree_gist) —
--    آمن تحت concurrency حتى لو تجاوز تسلسل التطبيق
--    (القيد يُنشأ في خطوة مستقلة idempotent أدناه — يعمل حتى لو
--     كان الجدول موجودًا مسبقًا بدون القيد)
-- ==========================================
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS equipment_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    equipment_id UUID NOT NULL REFERENCES equipment(id),
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','released','cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_at > start_at)
);

-- 3-ب) قيد منع التداخل — idempotent فعليًا (يفحص pg_constraint قبل الإضافة)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname  = 'equipment_no_double_booking'
          AND conrelid = 'public.equipment_reservations'::regclass
    ) THEN
        ALTER TABLE public.equipment_reservations
            ADD CONSTRAINT equipment_no_double_booking
            EXCLUDE USING gist (
                equipment_id WITH =,
                tstzrange(start_at, end_at, '[)') WITH &&
            ) WHERE (status = 'active');
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_eq_res_contract ON equipment_reservations(contract_id);
CREATE INDEX IF NOT EXISTS idx_eq_res_equipment ON equipment_reservations(equipment_id) WHERE status = 'active';

ALTER TABLE equipment_reservations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_all_equipment_reservations" ON public.equipment_reservations;
-- Phase 1: لا سياسات anon/authenticated — التشغيل حصريًا عبر service_role

-- ==========================================
-- 3-ج) Least Privilege — Table Grants صريحة (لا اعتماد على RLS وحده)
-- التشغيل الحالي خادمي بالكامل عبر service_role (Edge Functions).
-- anon: لا شيء · authenticated: لا شيء (حتى SELECT) —
-- أي Admin Inventory UI مستقبلًا سيتطلب Team-scoped policies عبر employees
-- ==========================================
REVOKE ALL ON public.equipment              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.contract_equipment     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.equipment_reservations FROM PUBLIC, anon, authenticated;

GRANT ALL ON public.equipment              TO service_role;
GRANT ALL ON public.contract_equipment     TO service_role;
GRANT ALL ON public.equipment_reservations TO service_role;

-- ==========================================
-- 4) أزمنة الجلسة على العقد (من Booking Request — Calculator يجمع وقت البداية)
-- ==========================================
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS shoot_start_time TIME;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS shoot_end_time TIME;

-- ==========================================
-- 5) submit_lead — إضافة p_shoot_start_time / p_shoot_end_time
--    (نفس منطق 013 مع حفظ الأزمنة بشكل Structured بدل النص في notes)
-- ==========================================
DROP FUNCTION IF EXISTS public.submit_lead(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB, JSONB, TEXT
);
DROP FUNCTION IF EXISTS public.submit_lead(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB
);

CREATE OR REPLACE FUNCTION public.submit_lead(
    p_full_name TEXT,
    p_phone TEXT DEFAULT NULL,
    p_email TEXT DEFAULT NULL,
    p_identity TEXT DEFAULT NULL,
    p_service_type TEXT DEFAULT NULL,
    p_total NUMERIC DEFAULT 0,
    p_property_type TEXT DEFAULT NULL,
    p_property_location TEXT DEFAULT NULL,
    p_rooms TEXT DEFAULT NULL,
    p_shoot_date DATE DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_services JSONB DEFAULT NULL,
    p_units JSONB DEFAULT NULL,
    p_quote_number TEXT DEFAULT NULL,
    p_shoot_start_time TEXT DEFAULT NULL,
    p_shoot_end_time TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_client_id UUID;
    v_contract_id UUID;
    v_quote_id UUID;
    v_units JSONB;
    v_start_time TIME;
    v_end_time TIME;
    v_name TEXT := btrim(COALESCE(p_full_name, ''));
    v_phone TEXT := regexp_replace(COALESCE(p_phone, ''), '[^0-9+]', '', 'g');
    v_email TEXT := NULLIF(lower(btrim(COALESCE(p_email, ''))), '');
    v_recent_count INTEGER;
    svc JSONB;
    v_service_name TEXT;
    v_package_type TEXT;
BEGIN
    IF char_length(v_name) NOT BETWEEN 2 AND 120 THEN
        RAISE EXCEPTION 'invalid_full_name' USING ERRCODE = '22023';
    END IF;

    IF v_phone !~ '^\+?[0-9]{8,15}$' THEN
        RAISE EXCEPTION 'invalid_phone' USING ERRCODE = '22023';
    END IF;

    IF v_email IS NOT NULL AND
       (char_length(v_email) > 254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN
        RAISE EXCEPTION 'invalid_email' USING ERRCODE = '22023';
    END IF;

    -- أزمنة الجلسة: صيغة HH:MM فقط أو NULL
    IF COALESCE(p_shoot_start_time, '') <> '' THEN
        IF p_shoot_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
            RAISE EXCEPTION 'invalid_time' USING ERRCODE = '22023';
        END IF;
        v_start_time := p_shoot_start_time::time;
    END IF;
    IF COALESCE(p_shoot_end_time, '') <> '' THEN
        IF p_shoot_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
            RAISE EXCEPTION 'invalid_time' USING ERRCODE = '22023';
        END IF;
        v_end_time := p_shoot_end_time::time;
    END IF;
    IF v_start_time IS NOT NULL AND v_end_time IS NOT NULL AND v_end_time <= v_start_time THEN
        RAISE EXCEPTION 'invalid_time_range' USING ERRCODE = '22023';
    END IF;

    IF char_length(COALESCE(p_identity, '')) > 50
       OR char_length(COALESCE(p_service_type, '')) > 500
       OR char_length(COALESCE(p_property_location, '')) > 300
       OR char_length(COALESCE(p_rooms, '')) > 50
       OR char_length(COALESCE(p_notes, '')) > 2000
       OR char_length(COALESCE(p_quote_number, '')) > 30 THEN
        RAISE EXCEPTION 'input_too_long' USING ERRCODE = '22023';
    END IF;

    IF p_property_type IS NOT NULL AND p_property_type NOT IN
       ('villa', 'apartment', 'office', 'land', 'commercial', 'compound', 'other') THEN
        RAISE EXCEPTION 'invalid_property_type' USING ERRCODE = '22023';
    END IF;

    IF COALESCE(p_total, 0) < 0 OR COALESCE(p_total, 0) > 1000000 THEN
        RAISE EXCEPTION 'invalid_total' USING ERRCODE = '22023';
    END IF;

    IF p_services IS NOT NULL THEN
        IF jsonb_typeof(p_services) <> 'array' OR jsonb_array_length(p_services) > 20 THEN
            RAISE EXCEPTION 'invalid_services' USING ERRCODE = '22023';
        END IF;
    END IF;

    v_units := public.sanitize_units(p_units);

    SELECT count(*)
      INTO v_recent_count
      FROM public.clients
     WHERE regexp_replace(COALESCE(phone_number, ''), '[^0-9+]', '', 'g') = v_phone
       AND created_at >= now() - interval '15 minutes';

    IF v_recent_count >= 5 THEN
        RAISE EXCEPTION 'too_many_requests' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.clients (full_name, phone_number, email, identity_number)
    VALUES (v_name, v_phone, v_email, NULLIF(btrim(COALESCE(p_identity, '')), ''))
    RETURNING id INTO v_client_id;

    INSERT INTO public.contracts (
        client_id, service_type, total_amount,
        contract_date, status, property_type, property_location,
        rooms_count, shoot_date, notes, units,
        shoot_start_time, shoot_end_time
    ) VALUES (
        v_client_id,
        COALESCE(NULLIF(btrim(COALESCE(p_service_type, '')), ''), '—'),
        COALESCE(p_total, 0),
        CURRENT_DATE,
        'new',
        p_property_type,
        NULLIF(btrim(COALESCE(p_property_location, '')), ''),
        NULLIF(btrim(COALESCE(p_rooms, '')), ''),
        p_shoot_date,
        NULLIF(btrim(COALESCE(p_notes, '')), ''),
        v_units,
        v_start_time,
        v_end_time
    )
    RETURNING id INTO v_contract_id;

    IF COALESCE(btrim(COALESCE(p_quote_number, '')), '') <> '' THEN
        SELECT id INTO v_quote_id
          FROM public.quotes
         WHERE quote_number = btrim(p_quote_number)
         LIMIT 1;
        IF v_quote_id IS NOT NULL THEN
            UPDATE public.contracts
               SET quote_id = v_quote_id
             WHERE id = v_contract_id;
        END IF;
    END IF;

    IF p_services IS NOT NULL THEN
        FOR svc IN SELECT value FROM jsonb_array_elements(p_services) LOOP
            IF jsonb_typeof(svc) <> 'object' THEN
                RAISE EXCEPTION 'invalid_service_item' USING ERRCODE = '22023';
            END IF;

            v_service_name := btrim(COALESCE(svc->>'name', ''));
            v_package_type := COALESCE(NULLIF(btrim(COALESCE(svc->>'pkg', '')), ''), 'basic');

            IF char_length(v_service_name) NOT BETWEEN 1 AND 120
               OR v_package_type NOT IN ('basic', 'pro') THEN
                RAISE EXCEPTION 'invalid_service_item' USING ERRCODE = '22023';
            END IF;

            INSERT INTO public.contract_services (contract_id, service_name, package_type)
            VALUES (v_contract_id, v_service_name, v_package_type);
        END LOOP;
    END IF;

    RETURN v_contract_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_lead(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB, JSONB, TEXT, TEXT, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_lead(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB, JSONB, TEXT, TEXT, TEXT
) TO anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
