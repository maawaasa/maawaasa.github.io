-- مأوى — تحصين دالة استقبال طلبات الموقع
-- يحافظ على نفس التوقيع المستخدم في form.html وcalculator.html.

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
    p_services JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_client_id UUID;
    v_contract_id UUID;
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

    IF char_length(COALESCE(p_identity, '')) > 50
       OR char_length(COALESCE(p_service_type, '')) > 500
       OR char_length(COALESCE(p_property_location, '')) > 300
       OR char_length(COALESCE(p_rooms, '')) > 50
       OR char_length(COALESCE(p_notes, '')) > 2000 THEN
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

    -- حد بسيط يمنع النقر المتكرر والإغراق بنفس رقم الهاتف.
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
        rooms_count, shoot_date, notes
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
        NULLIF(btrim(COALESCE(p_notes, '')), '')
    )
    RETURNING id INTO v_contract_id;

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
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_lead(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB
) TO anon, authenticated;
