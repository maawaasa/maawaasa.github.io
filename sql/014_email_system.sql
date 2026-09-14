-- =====================================================
-- 014 — Email System Infrastructure (Phase 1 — Email-First)
-- التشغيل: Supabase → SQL Editor → لصق كامل → Run (مرة واحدة، تكراره آمن)
--
-- القرارات المعتمدة المنفَّذة هنا:
--   Idempotency: one send per order + event_type + event_version
--   Retry لا يرسل Duplicate Email
--   لا ترسل رسالة لمرحلة قديمة إذا انتقل الطلب لحالة أحدث
--   Supabase هو Source of Truth + Activity Log
-- =====================================================

BEGIN;

-- ==========================================
-- 1) سجل الإيميلات — أساس الـIdempotency
--    idempotency_key = entity_type:entity_id:event_type:event_version
--    الإدراج هو القفل: ON CONFLICT DO NOTHING يمنع التكرار حتى مع التزامن
-- ==========================================
CREATE TABLE IF NOT EXISTS email_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key TEXT UNIQUE NOT NULL,
    event_type TEXT NOT NULL,
    event_version INT NOT NULL DEFAULT 1,
    entity_type TEXT,
    entity_id TEXT,
    recipient TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','sent','failed','skipped_outdated','skipped_duplicate')),
    error TEXT,
    payload JSONB,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_log_entity ON email_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_email_log_event ON email_log(event_type, created_at);

ALTER TABLE email_log ENABLE ROW LEVEL SECURITY;

-- القراءة للفريق فقط — الكتابة عبر Edge Functions بمفتاح service_role (يتجاوز RLS)
-- لا سياسات لـanon إطلاقًا.
DROP POLICY IF EXISTS "auth_read_email_log" ON email_log;
CREATE POLICY "auth_read_email_log" ON email_log FOR SELECT TO authenticated USING (true);

-- ==========================================
-- 2) أعمدة Hold للعربون (إضافية آمنة — تخدم C-04/C-05/C-07 لاحقًا)
--    24h Hold بعد تأكيد التغطية — الإيصال قبل انتهاء المهلة يوقف الانتهاء
-- ==========================================
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS hold_started_at TIMESTAMPTZ;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS hold_expires_at TIMESTAMPTZ;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS receipt_uploaded_at TIMESTAMPTZ;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS receipt_image_url TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS deposit_review_status TEXT
    CHECK (deposit_review_status IS NULL
           OR deposit_review_status IN ('receipt_under_review','approved','correction_requested'));
CREATE INDEX IF NOT EXISTS idx_contracts_hold_expiry ON contracts(hold_expires_at)
    WHERE hold_expires_at IS NOT NULL;

-- ==========================================
-- 3) أعمدة دورة حياة Quote (C-01/C-02 + الحالة)
--    status موجودة في 013 (active/converted/expired/cancelled)
-- ==========================================
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS expired_notified_at TIMESTAMPTZ;

-- ==========================================
-- 4) Activity Log للإيميلات — مرآة تشغيلية في activity_log
--    (activity_log موجود من 000 — نضيف فقط دالة تسجيل آمنة)
--    Security: SECURITY DEFINER مقفلة — EXECUTE لـservice_role فقط
--    (لا يوجد أي مستدعٍ شرعي من anon/authenticated في الكود الحالي)
--    entity_id: أعمدة activity_log.entity_id من نوع BIGINT بينما معرفاتنا UUID —
--    يُحفظ إذًا داخل details بشكل Structured (دمج بدون الكتابة فوق p_details)
-- ==========================================
CREATE OR REPLACE FUNCTION public.log_email_activity(
    p_action TEXT,
    p_entity TEXT,
    p_entity_id TEXT,
    p_details JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_details JSONB;
BEGIN
    -- entity_id يُحفظ Structured داخل details — دون الكتابة فوق مفتاح موجود
    v_details := COALESCE(p_details, '{}'::jsonb);
    IF NOT (v_details ? 'entity_id') AND p_entity_id IS NOT NULL THEN
        v_details := jsonb_set(v_details, '{entity_id}', to_jsonb(p_entity_id), true);
    END IF;

    -- activity_log له جيلان: بعمود entity أو entity_type — نجرب الأول ثم البديل
    BEGIN
        INSERT INTO public.activity_log (action, entity, details)
        VALUES (p_action, p_entity, v_details);
    EXCEPTION WHEN undefined_column THEN
        INSERT INTO public.activity_log (action, entity_type, details)
        VALUES (p_action, p_entity, v_details);
    END;
END;
$$;

-- SECURITY DEFINER مقفلة: لا PUBLIC، لا anon — service_role فقط (Edge Functions)
REVOKE ALL ON FUNCTION public.log_email_activity(
    TEXT, TEXT, TEXT, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.log_email_activity(
    TEXT, TEXT, TEXT, JSONB
) TO service_role;

COMMENT ON TABLE email_log IS 'Email System Phase 1 — idempotency ledger. أحداث: C-01..C-20, O-01..O-12';

COMMIT;

-- إعادة تحميل schema الـPostgREST ليظهر email_log عبر REST
NOTIFY pgrst, 'reload schema';
