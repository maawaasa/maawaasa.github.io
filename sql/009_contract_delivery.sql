-- مأوى — سجل اعتماد وإرسال العقود
-- يمنع إرسال العقد نفسه أكثر من مرة ويحفظ مسار النسخة النهائية.

CREATE TABLE IF NOT EXISTS public.contract_deliveries (
    contract_id UUID PRIMARY KEY REFERENCES public.contracts(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
    approved_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    recipient_email TEXT,
    storage_path TEXT,
    resend_email_id TEXT,
    last_error TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.contract_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.contract_deliveries FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('customer-contracts', 'customer-contracts', false, 10485760, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;
