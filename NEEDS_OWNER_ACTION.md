# NEEDS_OWNER_ACTION — إجراءات يتطلبها المالك (لا أستطيع تنفيذها برمجيًا)

> آخر تحديث: ليلة التشغيل الذاتي الأولى
> الترتيب بالأولوية — كل إجراء مستقل ما لم يُذكر خلافه

---

## 1) 🔴 حرج — تشغيل `sql/013b_close_anon_inserts.sql` (دقيقتان)

**السبب**: تشغيل 013 على الإنتاج طبّق الجداول والدوال، لكن **سياسات anon-INSERT ما زالت مفتوحة** على `clients/contracts/contract_services` — لأن أسماء السياسات في الإنتاج لا تطابق الأسماء التي أسقطتها 013 نصيًا (`DROP IF EXISTS` صامت). أي شخص يعرف مفتاح anon العام يمكنه إنشاء صفوف مباشرة متجاوزًا كل التحقق.

**الخطوات**:

```text
1) Supabase Dashboard → SQL Editor → New Query
2) الصق الملف: sql/013b_close_anon_inserts.sql كاملًا
3) Run
4) تحقق (نفس المحرر):
   SELECT tablename, policyname FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('clients','contracts','contract_services')
      AND 'anon' = ANY(roles);
   ⇒ يجب أن تكون النتيجة صفر صفوف
```

الملف يسقط السياسات **ديناميكيًا** مهما كان اسمها، ويضمن سياسات authenticated لـadmin.html، ويعيد تحميل PostgREST schema (بعد هذا يظهر `quotes` و`submit_quote` عبر REST ويشتغل Save Quote والحجز الجديد).

**بعد التشغيل**: أخبرني — أعيد Production Smoke Test كاملًا (النقاط 1–9) فورًا.

---

## 2) 🟡 تنظيف صفوف اختبار من الإنتاج (بعد الخطوة 1)

صفوف أنشأتها فحوصات الأمان قبل إغلاق السياسات:

```sql
DELETE FROM clients WHERE phone_number IN ('0500000000','0500000009','0599999999');
DELETE FROM clients WHERE full_name IN ('smoke_hacker','smoke_hacker2','zz_probe_blocked','smoke_probe');
```

(أي مما ينطبق — الأرقام أضمن من الأسماء.)

---

## 3) 🟡 نظام الإيميلات + دورة الحجز — تفعيل البنية كاملة

الكود جاهز بالكامل (دوال + migrations + صفحات). خطوات التشغيل بالترتيب:

```text
أ) SQL Editor → تشغيل الملفين بالترتيب:
   sql/014_email_system.sql
   sql/015_receipts.sql
   (email_log + أعمدة Hold والإيصالات + جدول الرموز الآمنة + حاوية receipts الخاصة)

ب) نشر الدوال (كلها تفحص النوع بنجاح):
   supabase functions deploy send-email
   supabase functions deploy email-automation
   supabase functions deploy action-token-create
   supabase functions deploy receipt-submit
   supabase functions deploy coverage-confirm
   supabase functions deploy payment-approve
   supabase functions deploy notify-lead        (محدَّث: يرسل C-03 للعميل)

ج) Secrets:
   supabase secrets set RESEND_API_KEY=re_xxxxxxxx
   supabase secrets set EMAIL_FROM_CUSTOMER="مأوى للتصوير العقاري <info@maawaa.sa>"
   supabase secrets set EMAIL_FROM_OPERATIONS="مأوى للتصوير العقاري <operations@maawaa.sa>"

د) جدولة الأتمتة (C-02 / C-07):
   Dashboard → Edge Functions → email-automation → Schedules → Cron: 0 * * * *
```

**تدفقات تعمل بعد هذه الخطوات:**

```text
تأكيد التغطية (ملاك):
  POST /functions/v1/coverage-confirm
  Headers: Authorization: Bearer <service_key أو JWT مالك>
  Body: { "contract_id": "<id>" }
  ⇒ awaiting_payment + Hold 24h + C-04 للعميل برابط رفع آمن

اعتماد العربون (ملاك بعد مراجعة الإيصال):
  POST /functions/v1/payment-approve
  Body: { "contract_id": "<id>", "kind": "deposit" }
  ⇒ deposit_paid + Booking Confirmed (C-08)

اعتماد السداد النهائي:
  POST /functions/v1/payment-approve
  Body: { "contract_id": "<id>", "kind": "balance" }
  ⇒ fully_paid + إشعار التسليم (C-17)
```

ملاحظات:
- قبل إضافة `RESEND_API_KEY` تعمل الدالتان بوضع **dry** (تسجيل في email_log بلا إرسال حقيقي) — آمنة للاختبار.
- C-01 (Quote Ready) عبر Database Webhook على جدول quotes (INSERT) → استدعاء send-email بنفس نمط C-03 — التوصيل من اللوحة (Integrations → Webhooks).
- ربط صفحة مراجعة الإيصالات للمالك في admin.html — خطوة تالية مقترحة.
- التحقق من نطاق maawaa.sa في Resend (SPF/DKIM) إن لم يكن مفعّلًا.

---

## 4) 🟡 بعد نجاح (1): فحص سياسات Storage في لوحة Supabase

فحص REST أثبت: رفع/قراءة anon على حاوية `receipts` محجوبان (400 ✓) لكن **الـList أعادت 200** — أي توجد سياسة SELECT على `storage.objects` تسمح لـanon بعرض أسماء الملفات (ليس محتواها).

```text
SQL Editor:
SELECT policyname, cmd, roles FROM pg_policies
 WHERE schemaname='storage' AND tablename='objects';

إن وُجدت سياسة تشمل anon مع SELECT/ALL:
  احذفها أو عدّلها لتستثني bucket_id = 'receipts'
  (لا تحذف سياسات authenticated — لوحة الإدارة تعتمد عليها)
```

ملاحظة تخفيف مؤقتة: أسماء ملفات الإيصالات تبدأ بـUUID غير قابل للتخمين — لا تسريب محتوى، تسريب أسماء فقط.

---

## 5) 🟢 بعد نجاح (1): مراجعة سريعة في لوحة Supabase

```text
Authentication → Policies: لا توجد سياسة INSERT تضم anon على
clients / contracts / contract_services / quotes
```

---

## 6) 🟡 قوالب الإيميل — مراجعة بصرية + ترقية «فخامة طباعي» (مؤجلة بقرار المالك)

**الحالة الآن (2026-09-15):** النسخة المحسّنة منُشرة على `send-email` ومجرَّبة عبر التدفق الحقيقي —
ثلاث رسائل وصلت بريد المالك (C-04 / C-08 / C-17 بعناوين «لديك 24 ساعة…» و«تم تأكيد حجزك» و«مخرجاتك جاهزة»).

**المطلوب من المالك:**
1. مراجعة بصرية للرسائل الثلاث على الحاسوب والجوال (العربية/RTL، شريط الحالة، الأزرار، التذييل).
2. قرار الترقية المؤجلة: «فخامة طباعي» — مسافات أوسع، تسلسل طباعي أقوى، فواصل راقية، شارة رقم الطلب، توقيع الفريق (بلا صور — يعمل في كل عملاء البريد). وُافقت عليه اتجاهًا وجُيّدت لاحقًا بقرار المالك نفسه.

**ملاحظات تقنية للتنفيذ لاحقًا:**
- التعديل في `supabase/functions/_shared/templates.ts` فقط، ثم `supabase functions deploy send-email`.
- الاختبار الأسرع: التدفق الحقيقي (E2E يرسل C-04/C-08/C-17 تلقائيًا) — الاستدعاء المباشر لـ`send-email` بالمفتاح القديم من `supabase projects api-keys` يفشل بـ401 لأن القيمة المحقونة في بيئة الدوال مختلفة (استخدم مفتاح Dashboard أو مسار الفريق).
- تغييرات غير محفوظة في شجرة العمل: `templates.ts` + `scripts/smoke-email-templates.sh` (سكربت معاينة مستقل — فحص email_log فيه يحتاج تصحيح فلترة بمعرّف التشغيل).

---

*ملاحظة: لا يوجد أي commit/push — كل العمل في شجرة العمل المحلية بانتظار مراجعتك.*
