-- إعداد امتداد مستقبلي للعقود: تبقى الواجهة الحالية عربية وبالريال السعودي.
-- لا يغيّر هذا الترحيل أي مبلغ أو نص أو رقم عقد قائم.

ALTER TABLE contracts
  ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'ar'
    CHECK (language IN ('ar', 'en')),
  ADD COLUMN IF NOT EXISTS currency CHAR(3) NOT NULL DEFAULT 'SAR'
    CHECK (currency IN ('SAR', 'USD'));

COMMENT ON COLUMN contracts.language IS
  'لغة العقد المحفوظة. الافتراضي ar؛ الإنجليزية غير مفعلة في واجهة العملاء بعد.';

COMMENT ON COLUMN contracts.currency IS
  'عملة العقد المحفوظة. الافتراضي SAR؛ USD محجوزة لتفعيل مستقبلي فقط.';
