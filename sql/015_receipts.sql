-- =====================================================
-- 015 — Receipts & Action Tokens (Phase 1 — Email-First)
-- التشغيل: Supabase → SQL Editor → لصق كامل → Run (تكراره آمن)
--
-- النموذج: رابط فعل آمن برمز عشوائي — يُخزَّن hash فقط (نمط schedule-change)
--   action-token-create (service فقط) يولّد الرمز ويعيد الرابط الكامل
--   receipt-submit يتحقق من الـhash وينفذ الرفع ويعلّم الطلب
--   الرمز صالح لمرة واحدة (used_at) وله انتهاء صلاحية
-- =====================================================

BEGIN;

-- ==========================================
-- 1) رموز الإجراءات الآمنة
-- ==========================================
CREATE TABLE IF NOT EXISTS action_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash TEXT UNIQUE NOT NULL,          -- sha256 hex للرمز الخام (الخام لا يُخزن أبدًا)
    purpose TEXT NOT NULL
        CHECK (purpose IN ('deposit_receipt','balance_receipt','contract_access','delivery_access','rating','calendar')),
    entity_type TEXT NOT NULL DEFAULT 'contract'
        CHECK (entity_type IN ('contract','quote')),
    entity_id TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '72 hours'),
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_action_tokens_entity ON action_tokens(entity_type, entity_id);

ALTER TABLE action_tokens ENABLE ROW LEVEL SECURITY;
-- لا سياسات إطلاقًا: الوصول عبر الدوال المحصنة فقط (service_role يتجاوز RLS)
-- authenticated يقرأ للإدارة إن لزم
DROP POLICY IF EXISTS "auth_read_action_tokens" ON action_tokens;
CREATE POLICY "auth_read_action_tokens" ON action_tokens FOR SELECT TO authenticated USING (true);

-- ==========================================
-- 2) حاوية تخزين الإيصالات (خاصة — وصول عبر URLs موقعة من الدوال)
-- ==========================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts', 'receipts', false)
ON CONFLICT (id) DO NOTHING;

COMMIT;

NOTIFY pgrst, 'reload schema';
