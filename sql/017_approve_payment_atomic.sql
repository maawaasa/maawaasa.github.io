-- =====================================================
-- 017 — approve_payment_atomic (Financial Integrity داخل DB)
-- التشغيل: Supabase → SQL Editor → لصق كامل → Run (مرة واحدة، تكراره آمن)
--
-- الضمانات:
--   - SELECT ... FOR UPDATE يقفل صف العقد ⇒ اعتمادَان متزامنان يتسلسلان لا يتزاحمان
--   - الدالة كلها معاملة واحدة: أي RAISE ⇒ Rollback كامل (لا حالات نصف مطبقة)
--   - paid_total يُحسب من payments (Source of Truth) وليس من الواجهة
--   - منع اعتماد نفس payment_reference مرتين
--   - الحالات: fully_paid / deposit_paid (≥25% → Booking Confirmed) / payment_recorded
--   - correction ليست دفعة — لا تمر من هنا إطلاقًا
-- =====================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.approve_payment_atomic(
    p_contract_id UUID,
    p_amount NUMERIC,
    p_kind TEXT,
    p_payment_reference TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_status TEXT;
    v_total NUMERIC;
    v_paid_before NUMERIC;
    v_paid_total NUMERIC;
    v_quarter NUMERIC;
    v_new_state TEXT;
    v_contract_number TEXT;
    v_payment_id BIGINT;
BEGIN
    -- 1) قفل العقد FOR UPDATE — تسلسل إلزامي للاعتماد المتزامن
    SELECT status, total_amount, contract_number
      INTO v_status, v_total, v_contract_number
      FROM public.contracts
     WHERE id = p_contract_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'contract_not_found';
    END IF;

    -- 2) حالة العقد تسمح بالاعتماد؟ (منع المراحل القديمة)
    IF p_kind = 'deposit' AND v_status NOT IN ('new', 'awaiting_payment') THEN
        RAISE EXCEPTION 'outdated_state:%', v_status;
    END IF;
    IF p_kind = 'balance' AND v_status NOT IN ('deposit_paid', 'in_progress') THEN
        RAISE EXCEPTION 'outdated_state:%', v_status;
    END IF;

    -- 3) المبلغ
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'invalid_amount';
    END IF;
    p_amount := round(p_amount::numeric, 2);

    -- 4) منع اعتماد نفس المرجع مرتين (إن وُجد معرف مرجعي)
    IF COALESCE(btrim(COALESCE(p_payment_reference, '')), '') <> '' AND
       EXISTS (SELECT 1
                 FROM public.payments
                WHERE contract_id = p_contract_id
                  AND note = btrim(p_payment_reference)) THEN
        RAISE EXCEPTION 'duplicate_reference';
    END IF;

    -- 5) paid_total الحالي من Source of Truth
    v_paid_before := COALESCE((
        SELECT SUM(amount) FROM public.payments WHERE contract_id = p_contract_id
    ), 0);

    -- 6) لا يتجاوز إجمالي العقد
    IF v_paid_before + p_amount > v_total + 0.01 THEN
        RAISE EXCEPTION 'amount_exceeds_total';
    END IF;

    -- 7) إدراج الدفعة المعتمدة بمبلغها الفعلي
    INSERT INTO public.payments (contract_id, amount, method, is_deposit, note)
    VALUES (
        p_contract_id,
        p_amount,
        'transfer',
        (p_kind = 'deposit'),
        COALESCE(NULLIF(btrim(COALESCE(p_payment_reference, '')), ''),
                 format('approved via approve_payment_atomic (%s)', p_kind))
    )
    RETURNING id INTO v_payment_id;

    -- 8) إعادة الحساب من Source of Truth
    v_paid_total := COALESCE((
        SELECT SUM(amount) FROM public.payments WHERE contract_id = p_contract_id
    ), 0);
    v_quarter := ROUND(v_total * 0.25);

    -- 9/10/11) تحديد الحالة المالية
    IF v_paid_total >= v_total - 0.01 THEN
        v_new_state := 'fully_paid';                       -- Paid in Full (حتى لو دفع كاملًا مقدمًا)
    ELSIF p_kind = 'deposit' AND v_paid_total >= v_quarter - 0.01 THEN
        v_new_state := 'deposit_paid';                     -- Booking Confirmed عند ≥25%
    ELSE
        v_new_state := 'payment_recorded';                 -- بدون Booking Confirmed
    END IF;

    IF v_new_state IN ('fully_paid', 'deposit_paid') THEN
        UPDATE public.contracts
           SET status = v_new_state,
               deposit_review_status = 'approved',
               hold_started_at = NULL,
               hold_expires_at = NULL
         WHERE id = p_contract_id
           AND status = v_status;                          -- قفل المرحلة داخل نفس المعاملة
        IF NOT FOUND THEN
            RAISE EXCEPTION 'outdated_state:%', v_status;  -- Rollback كامل شامل الدفعة
        END IF;
    ELSE
        -- payment_recorded: الدفعة مسجلة — لا تأكيد حجز
        UPDATE public.contracts
           SET deposit_review_status = 'approved'
         WHERE id = p_contract_id;
    END IF;

    -- سجل نشاط (داخل نفس المعاملة)
    BEGIN
        INSERT INTO public.activity_log (action, entity, details)
        VALUES (
            'payment_approved:' || p_kind,
            'contracts',
            jsonb_build_object(
                'contract_id', p_contract_id,
                'contract_number', v_contract_number,
                'new_state', v_new_state,
                'paid_total', v_paid_total,
                'amount', p_amount,
                'payment_id', v_payment_id,
                'payment_reference', NULLIF(btrim(COALESCE(p_payment_reference, '')), '')
            )
        );
    EXCEPTION WHEN undefined_column THEN
        INSERT INTO public.activity_log (action, entity_type, details)
        VALUES ('payment_approved:' || p_kind, 'contracts',
                jsonb_build_object(
                    'contract_id', p_contract_id,
                    'contract_number', v_contract_number,
                    'new_state', v_new_state,
                    'paid_total', v_paid_total,
                    'amount', p_amount,
                    'payment_id', v_payment_id
                ));
    END;

    -- 12) المعاملة تُ-commit مع عودة الدالة — أو Rollback كامل عند أي RAISE
    RETURN jsonb_build_object(
        'state', v_new_state,
        'status', CASE WHEN v_new_state = 'payment_recorded' THEN v_status ELSE v_new_state END,
        'paid_total', v_paid_total,
        'total_amount', v_total,
        'contract_number', v_contract_number,
        'payment_id', v_payment_id
    );
END;
$$;

-- Security: SECURITY DEFINER — EXECUTE مقفول بالكامل:
-- لا PUBLIC، لا anon، لا authenticated (يغلق تجاوز isTeamMember عبر RPC مباشر)
-- الاستدعاء الوحيد: payment-approve داخليًا بمفتاح service_role
REVOKE ALL ON FUNCTION public.approve_payment_atomic(
    UUID, NUMERIC, TEXT, TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.approve_payment_atomic(
    UUID, NUMERIC, TEXT, TEXT
) FROM anon;

REVOKE ALL ON FUNCTION public.approve_payment_atomic(
    UUID, NUMERIC, TEXT, TEXT
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.approve_payment_atomic(
    UUID, NUMERIC, TEXT, TEXT
) TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
