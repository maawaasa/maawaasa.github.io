-- =====================================================
-- مأوى — دالة استلام طلبات الحاسبة والنموذج (آمنة)
-- تحل: anon لا يستطيع قراءة id العميل/العقد بعد الإدراج بسبب RLS
-- تنشئ: العميل + العقد + خدمات العقد في عملية واحدة
-- الصقه في SQL Editor → Run
-- =====================================================

CREATE OR REPLACE FUNCTION submit_lead(
    p_full_name TEXT,
    p_phone TEXT,
    p_email TEXT DEFAULT NULL,
    p_identity TEXT DEFAULT NULL,
    p_service_type TEXT DEFAULT NULL,
    p_total NUMERIC DEFAULT 0,
    p_property_type TEXT DEFAULT NULL,
    p_property_location TEXT DEFAULT NULL,
    p_rooms TEXT DEFAULT NULL,
    p_shoot_date DATE DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_services JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_client_id UUID;
    v_contract_id UUID;
    svc JSONB;
BEGIN
    -- العميل
    INSERT INTO clients (full_name, phone_number, email, identity_number)
    VALUES (p_full_name, p_phone, p_email, p_identity)
    RETURNING id INTO v_client_id;

    -- العقد
    INSERT INTO contracts (
        client_id, service_type, total_amount,
        contract_date, status, property_type, property_location,
        rooms_count, shoot_date, notes
    ) VALUES (
        v_client_id, COALESCE(p_service_type, '—'), COALESCE(p_total, 0),
        CURRENT_DATE, 'new', p_property_type, p_property_location,
        p_rooms, p_shoot_date, p_notes
    )
    RETURNING id INTO v_contract_id;

    -- خدمات العقد (إن وجدت) بصيغة [{"name":"...","pkg":"basic"}]
    IF p_services IS NOT NULL THEN
        FOR svc IN SELECT * FROM jsonb_array_elements(p_services) LOOP
            INSERT INTO contract_services (contract_id, service_name, package_type)
            VALUES (v_contract_id, svc->>'name', COALESCE(svc->>'pkg', 'basic'));
        END LOOP;
    END IF;

    RETURN v_contract_id;
END;
$$;

-- الصلاحية: أي زائر ينفذها (إدراج فقط، لا يمكنه القراءة)
REVOKE ALL ON FUNCTION submit_lead FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_lead TO anon, authenticated;
