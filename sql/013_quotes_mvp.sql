-- =====================================================
-- 013 — Quotes MVP + الترقيم الخادمي Q-XXXX / MAW-XXXX + ربط Quote→Order
-- يعتمد على المخطط الحالي (UUID) كما في 008_submit_lead_hardening.sql
-- التشغيل: Supabase → SQL Editor → لصق الملف كاملاً → Run (مرة واحدة)
--
-- القرارات المعتمدة المنفَّذة هنا:
--   Q-XXXX  = رقم دائم ومستقل لعرض السعر (لا يُستبدل)
--   MAW-XXXX = رقم مستقل للطلب/العقد، يرتبط بالعرض عبر contracts.quote_id
--   صلاحية العرض = 14 يومًا
--   Save Quote لا ينشئ contract ولا يولّد MAW-XXXX
--   إغلاق الإدخال المجهول المباشر — الإنشاء العام عبر submit_lead/submit_quote فقط
--   الملف الكامل داخل معاملة واحدة — إما يُطبَّق كاملًا أو لا يُطبَّق شيء
-- =====================================================

BEGIN;

-- ==========================================
-- 1) تسلسلات الترقيم — خادمية وآمنة من التكرار/concurrency
-- ==========================================
CREATE SEQUENCE IF NOT EXISTS maw_quote_seq START 1001; -- Q-1042
CREATE SEQUENCE IF NOT EXISTS maw_order_seq START 1001; -- MAW-1048

-- ==========================================
-- 2) جدول العروض
-- ==========================================
CREATE TABLE IF NOT EXISTS quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_number TEXT UNIQUE,
    client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    service_type TEXT,
    property_type TEXT,
    total_amount NUMERIC(12,2) DEFAULT 0,
    currency CHAR(3) NOT NULL DEFAULT 'SAR'
        CHECK (currency IN ('SAR', 'USD')),
    language TEXT NOT NULL DEFAULT 'ar'
        CHECK (language IN ('ar', 'en')),
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','converted','expired','cancelled')),
    valid_until DATE NOT NULL DEFAULT (CURRENT_DATE + 14),
    units JSONB,
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_quotes_client ON quotes(client_id);
CREATE INDEX IF NOT EXISTS idx_quotes_status ON quotes(status);

ALTER TABLE quotes ENABLE ROW LEVEL SECURITY;

-- القراءة/الإدارة للفريق فقط — الكتابة العامة تمر حصريًا عبر submit_quote (SECURITY DEFINER)
DROP POLICY IF EXISTS "auth_all_quotes" ON quotes;
CREATE POLICY "auth_all_quotes" ON quotes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 2-ب) موضع بدء التسلسلات — بعد أعلى رقم موجود (حماية من الاصطدام)
-- مع حماية إعادة التشغيل: لا تراجع (rewind) أبدًا — القيمة الجديدة هي
-- GREATEST(أعلى رقم في السجلات، الحالة الحالية للتسلسل، 1000)
-- الصيغة: setval(seq, N, true) ⇒ nextval يعيد N+1 دائمًا.
-- في بيئة جديدة يعيد nextval = 1001 تمامًا كـSTART.
-- لا يعدّل أرقام أي سجل قديم — يقرأها فقط.
-- ==========================================
SELECT setval('maw_quote_seq', GREATEST(
    COALESCE((SELECT MAX(NULLIF(regexp_replace(quote_number, '\D', '', 'g'), '')::bigint)
              FROM public.quotes WHERE quote_number LIKE 'Q-%'), 1000),
    (SELECT CASE WHEN is_called THEN last_value ELSE last_value - 1 END
     FROM public.maw_quote_seq),
    1000), true);

SELECT setval('maw_order_seq', GREATEST(
    COALESCE((SELECT MAX(NULLIF(regexp_replace(contract_number, '\D', '', 'g'), '')::bigint)
              FROM public.contracts WHERE contract_number LIKE 'MAW-%'), 1000),
    (SELECT CASE WHEN is_called THEN last_value ELSE last_value - 1 END
     FROM public.maw_order_seq),
    1000), true);

-- ==========================================
-- 2-ج) إغلاق الإدخال المجهول المباشر (Security Gate)
-- تُسقط كل صيغ سياسات anon-INSERT المعروفة على جداول الإنشاء العام:
--   public_insert_* (من 000/001) + anon_insert_* (من 004/005)
-- كانت تسمح لأي جهة بـINSERT مباشر عبر REST متجاوزة submit_lead
-- (validation + rate limit + limits + الربط + الترقيم الخادمي).
-- بعد هذه المرحلة:
--   - الإنشاء العام للطلبات: عبر submit_lead المحصّنة فقط (SECURITY DEFINER)
--   - إنشاء العروض: عبر submit_quote فقط
--   - الفريق (authenticated): سياساته team_all_* / auth_all_* / auth_insert_*
--     كما هي — admin.html يكمل عمله
--   - لا يمس service_role ولا العمليات الداخلية الموثوقة
-- ==========================================
DROP POLICY IF EXISTS "public_insert_clients" ON public.clients;
DROP POLICY IF EXISTS "anon_insert_clients" ON public.clients;
DROP POLICY IF EXISTS "public_insert_contracts" ON public.contracts;
DROP POLICY IF EXISTS "anon_insert_contracts" ON public.contracts;
DROP POLICY IF EXISTS "public_insert_cs" ON public.contract_services;
DROP POLICY IF EXISTS "anon_insert_cs" ON public.contract_services;

DROP POLICY IF EXISTS "auth_insert_clients" ON public.clients;
CREATE POLICY "auth_insert_clients" ON public.clients
    FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_insert_contracts" ON public.contracts;
CREATE POLICY "auth_insert_contracts" ON public.contracts
    FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_insert_cs" ON public.contract_services;
CREATE POLICY "auth_insert_cs" ON public.contract_services
    FOR INSERT TO authenticated WITH CHECK (true);

-- ==========================================
-- 3) ربط العقود بالعروض + تخزين الوحدات المنظمة (ليست نصًا في notes)
--    مصممة بحيث يمكن لاحقًا استخراج units إلى جدول مستقل دون كسر الواجهة
-- ==========================================
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS quote_id UUID REFERENCES quotes(id) ON DELETE SET NULL;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS units JSONB;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS contract_number TEXT;
CREATE INDEX IF NOT EXISTS idx_contracts_quote ON contracts(quote_id);

-- ==========================================
-- 4) توليد MAW-XXXX للعقود — فقط عند إنشاء صف جديد برقم فارغ
--    لا يمس العقود التاريخية، ولا ما ينشئه admin برقمه الخاص
-- ==========================================
CREATE OR REPLACE FUNCTION public.set_contract_number()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.contract_number IS NULL OR btrim(NEW.contract_number) = '' THEN
        NEW.contract_number := 'MAW-' || nextval('public.maw_order_seq');
    END IF;
    RETURN NEW;
END;
$$;

-- إزالة أي trigger قديم بنفس الدور (النمط الاختياري القديم MWA-YYYY-NNNN)
DROP TRIGGER IF EXISTS set_contract_number ON public.contracts;
DROP TRIGGER IF EXISTS trg_contracts_number ON public.contracts;
CREATE TRIGGER trg_contracts_number
    BEFORE INSERT ON public.contracts
    FOR EACH ROW EXECUTE FUNCTION public.set_contract_number();

-- ==========================================
-- 4-ب) مطهّر الوحدات — تحقق عنصرًا-عنصرًا قبل التخزين
-- يرفض أي JSONB خام غير مطابق، ويعيد نسخة نظيفة بحقول مسموحة فقط
-- (الحقول غير المتوقعة تُسقَط — الأسلوب الأكثر أمانًا).
-- لا يُمنح EXECUTE للعامة — يُستدعى من الدوال المحصّنة فقط.
-- ==========================================
CREATE OR REPLACE FUNCTION public.sanitize_units(p_units JSONB)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    ua JSONB;
    u JSONB;
    v_type TEXT;
    v_rooms INT;
    v_qty INT;
    v_kind TEXT;
    v_total INT := 0;
    allowed_types CONSTANT TEXT[] := ARRAY['apartment', 'villa'];
    rooms_min CONSTANT JSONB := jsonb_build_object('apartment', 1, 'villa', 3);
    rooms_max CONSTANT JSONB := jsonb_build_object('apartment', 6, 'villa', 12);
BEGIN
    IF p_units IS NULL THEN
        RETURN NULL;
    END IF;

    IF jsonb_typeof(p_units) <> 'array' OR jsonb_array_length(p_units) > 20 THEN
        RAISE EXCEPTION 'invalid_units' USING ERRCODE = '22023';
    END IF;

    ua := '[]'::jsonb;

    FOR u IN SELECT value FROM jsonb_array_elements(p_units) LOOP
        IF jsonb_typeof(u) <> 'object' THEN
            RAISE EXCEPTION 'invalid_unit_item' USING ERRCODE = '22023';
        END IF;

        -- رفض أي عنصر ضخم غير متوقع
        IF octet_length(u::text) > 500 THEN
            RAISE EXCEPTION 'invalid_unit_item' USING ERRCODE = '22023';
        END IF;

        v_type := COALESCE(u->>'type', '');
        v_rooms := NULLIF(u->>'rooms', '')::int;   -- قيمة غير صحيحة ⇒ استثناء 22P02 (رفض)
        v_qty := COALESCE(NULLIF(u->>'qty', '')::int, 1);
        v_kind := COALESCE(u->>'kind', '');

        IF NOT (v_type = ANY(allowed_types)) THEN
            RAISE EXCEPTION 'invalid_unit_item' USING ERRCODE = '22023';
        END IF;

        IF v_rooms IS NULL
           OR v_rooms < (rooms_min ->> v_type)::int
           OR v_rooms > (rooms_max ->> v_type)::int THEN
            RAISE EXCEPTION 'invalid_unit_item' USING ERRCODE = '22023';
        END IF;

        IF v_qty < 1 OR v_qty > 20 THEN
            RAISE EXCEPTION 'invalid_unit_item' USING ERRCODE = '22023';
        END IF;

        v_total := v_total + v_qty;
        IF v_total > 20 THEN
            RAISE EXCEPTION 'invalid_units' USING ERRCODE = '22023';
        END IF;

        -- إعادة بناء نظيفة: الحقول المسموحة فقط بقيم متحقق منها
        ua := ua || jsonb_build_object(
            'kind',  CASE WHEN v_kind IN ('main', 'extra') THEN v_kind ELSE 'extra' END,
            'type',  v_type,
            'rooms', v_rooms,
            'qty',   v_qty
        );
    END LOOP;

    RETURN ua;
END;
$$;

REVOKE ALL ON FUNCTION public.sanitize_units(JSONB) FROM PUBLIC;

-- ==========================================
-- 5) دالة حفظ عرض السعر — تعيد رقم Q-XXXX دائم + تاريخ الانتهاء
--    لا تنشئ contract ولا ترسل إشعارًا (الإشعار مسار notify-lead للطلبات فقط)
-- ==========================================
CREATE OR REPLACE FUNCTION public.submit_quote(
    p_full_name TEXT,
    p_phone TEXT DEFAULT NULL,
    p_email TEXT DEFAULT NULL,
    p_property_type TEXT DEFAULT NULL,
    p_service_type TEXT DEFAULT NULL,
    p_total NUMERIC DEFAULT 0,
    p_units JSONB DEFAULT NULL,
    p_payload JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_client_id UUID;
    v_quote_id UUID;
    v_qnum TEXT;
    v_valid DATE;
    v_units JSONB;
    v_name TEXT := btrim(COALESCE(p_full_name, ''));
    v_phone TEXT := regexp_replace(COALESCE(p_phone, ''), '[^0-9+]', '', 'g');
    v_email TEXT := NULLIF(lower(btrim(COALESCE(p_email, ''))), '');
    v_recent_count INTEGER;
BEGIN
    -- نفس قواعد التحقق والتحصين المعمول بها في submit_lead
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

    IF char_length(COALESCE(p_service_type, '')) > 500 THEN
        RAISE EXCEPTION 'input_too_long' USING ERRCODE = '22023';
    END IF;

    IF p_property_type IS NOT NULL AND p_property_type NOT IN
       ('villa', 'apartment', 'office', 'land', 'commercial', 'compound', 'other') THEN
        RAISE EXCEPTION 'invalid_property_type' USING ERRCODE = '22023';
    END IF;

    IF COALESCE(p_total, 0) < 0 OR COALESCE(p_total, 0) > 1000000 THEN
        RAISE EXCEPTION 'invalid_total' USING ERRCODE = '22023';
    END IF;

    -- تحقق عنصرًا-عنصرًا + إعادة بناء نظيفة للوحدات
    v_units := public.sanitize_units(p_units);

    IF p_payload IS NOT NULL AND pg_column_size(p_payload) > 16000 THEN
        RAISE EXCEPTION 'payload_too_large' USING ERRCODE = '22023';
    END IF;

    -- حد بسيط يمنع النقر المتكرر والإغراق بنفس رقم الهاتف (نفس سياسة submit_lead)
    SELECT count(*)
      INTO v_recent_count
      FROM public.clients
     WHERE regexp_replace(COALESCE(phone_number, ''), '[^0-9+]', '', 'g') = v_phone
       AND created_at >= now() - interval '15 minutes';

    IF v_recent_count >= 5 THEN
        RAISE EXCEPTION 'too_many_requests' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.clients (full_name, phone_number, email)
    VALUES (v_name, v_phone, v_email)
    RETURNING id INTO v_client_id;

    -- Q-XXXX: رقم دائم من تسلسل خادمي — لا يُستبدل ولا يُعاد توليده
    v_qnum := 'Q-' || nextval('public.maw_quote_seq');
    v_valid := CURRENT_DATE + 14;

    INSERT INTO public.quotes (
        quote_number, client_id, service_type, property_type,
        total_amount, units, payload, valid_until, status
    ) VALUES (
        v_qnum, v_client_id,
        COALESCE(NULLIF(btrim(COALESCE(p_service_type, '')), ''), '—'),
        p_property_type,
        COALESCE(p_total, 0),
        v_units,
        p_payload,
        v_valid,
        'active'
    )
    RETURNING id INTO v_quote_id;

    RETURN jsonb_build_object(
        'id', v_quote_id,
        'quote_number', v_qnum,
        'valid_until', v_valid
    );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_quote(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_quote(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, JSONB
) TO anon, authenticated;

-- ==========================================
-- 6) submit_lead موسّع — نفس منطق 008 مع إضافتين فقط:
--    p_units        : الوحدات كبيانات JSONB منظمة (1 Site + N Units)
--    p_quote_number : ربط الطلب الجديد (MAW-XXXX) بالعرض الأصلي (Q-XXXX)
-- ==========================================
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
    p_quote_number TEXT DEFAULT NULL
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

    -- تحقق عنصرًا-عنصرًا + إعادة بناء نظيفة للوحدات (بدون JSONB خام من العميل)
    v_units := public.sanitize_units(p_units);

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
        rooms_count, shoot_date, notes, units
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
        v_units
    )
    RETURNING id INTO v_contract_id;

    -- الربط بالعرض الأصلي: Quote (Q-XXXX) ← Order (MAW-XXXX ينشأ من الـtrigger)
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
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB, JSONB, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_lead(
    TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, TEXT, JSONB, JSONB, TEXT
) TO anon, authenticated;

COMMIT;
