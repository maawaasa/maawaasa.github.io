# NIGHTLY_REPORT — جلسة التشغيل الذاتي

## Completed

### Phase A — الحاسبة (Regression Suite كامل — 18 فحصًا)
- تسعير الأساس: شقة 1/2/3 غرف = 850/975/1,100 ✓ — فيلا 6 = 2,000 ✓
- Multi-Unit: وحدتان مختلفتان (975+2,000=2,975) ✓، تكرار وحدة ✓، كمية ×2 ✓
- الدرون الثابت لا يتضاعف مع الوحدات ✓
- Legacy URLs: `u=4` فيلا → 4 وحدات مطابقة + Express = 11,500 ✓، `loc=0` يُهمل بأمان ✓
- Express +25% دقيق (975→1,219) ✓
- صفر خصومات تلقائية (multiDiscRate وbundle ملغاتان — سطر الحملة عرضي فقط) ✓
- خارج الرياض: جلاجل → تسعير يدوي بلا أي إضافة للسعر؛ الملز: التنقل مشمول بلا رسوم ✓
- Luxury (قصر): «حسب المشروع» + زر مخصّص + بطاقة الوحدات مخفية ✓
- Quote doc: الإجمالي يطابق الملخص، الصلاحية 14 يومًا (23/09/2026)، الرقم Q-TEST بعد الحفظ ✓
- EN/LTR: ترجمة كاملة لواجهة الوحدات والملخص ✓
- Mobile 390px: صفر تجاوز أفقي، كل العناصر ظاهرة ✓
- جدول الأسعار: نصّه الجديد «لا توجد خصومات تلقائية» ✓

### Phase B — الأمان
- تشخيص الإنتاج: سياسات anon-INSERT ما زالت مفتوحة (أسماء السياسات في الإنتاج لا تطابق أسماء 013) → **ملف `sql/013b_close_anon_inserts.sql`**: إسقاط ديناميكي لأي سياسة anon INSERT/ALL على الجداول الثلاثة + إعادة تحميل PostgREST schema.
- مراجعة 000/008/013: تعديل 000 (إسقاط public_insert + auth_insert فقط) + banner إهمال على 001 القديم.
- إصلاح ثغرة مكتشفة: 004/005 أنشأتا `anon_insert_*` بأسماء مختلفة — 013b يسقطها ديناميكيًا مهما اختلف الاسم.

### Phase C — نظام الإيميلات (Email-First P0)
- `sql/014_email_system.sql`: جدول `email_log` (Idempotency ledger) + أعمدة Hold للعربون + دورة حياة Quote + دالة activity log محصّنة.
- `supabase/functions/_shared/templates.ts`: 18 قالبًا عربيًا RTL بهوية مأوى (C-01..C-08، C-14..C-17، O-01..O-05، O-08) — **18/18 PASS** (RTL، branding، لا undefined، نص بديل).
- `supabase/functions/send-email`: مرسل موحد — قفل Idempotency بالإدراج، منع الأحداث القديمة (فحص حالة الكيان)، وضع dry بلا `RESEND_API_KEY`، فحص بريد المستلم.
- `supabase/functions/email-automation`: C-02 (انتهاء العروض) وC-07 (انتهاء Hold 24h — رفع الإيصال قبل المهلة يلغي الحدث) — قفل تنفيذ سباقي.
- `notify-lead` محدّث: يرسل **C-03** للعميل فور طلب الحجز (fire-and-forget لا يؤثر على قنوات الملاك).
- معاينة بصرية: C-04 مُصيَّر ومُتحقق منه (screenshot ✓).

### Phase D/E — الإيصالات وصفحات الإجراءات
- `sql/015_receipts.sql`: `action_tokens` (hash فقط، مرة واحدة، انتهاء صلاحية) + حاوية `receipts` خاصة.
- `action-token-create`: توليد روابط آمنة (service فقط).
- `receipt-submit`: تحقق الرمز (مستخدم/منتهي/غرض)، رفع للحاوية الخاصة، `Receipt Under Review`، **رفع الإيصال يوقف انتهاء الـHold**، منع المراحل القديمة، Activity Log.
- `receipt.html`: صفحة إجراء واحد — موبايل أولًا RTL، حالات (تحقق/خطأ بأكواد مفهومة/نموذج/نجاح) — مختبرة محليًا ✓.

### Phase F/G — حلقة الحجز الأساسية
- `coverage-confirm`: تأكيد التغطية → تعيين مصور محايد (round-robin) → `awaiting_payment` + Hold 24h (قفل سباقي) → توليد رابط إيصال آمن → C-04 → Activity Log.
- `payment-approve`: اعتماد عربون (`deposit_paid` + C-08) أو سداد نهائي (`fully_paid` + C-17) مع تسجيل `payments` وقيود المراحل.
- كل الدوال السبع تفحص النوع بنجاح (deno check) — ثُبّت deno للفحص.

## Tested
- جناح انحدار الحاسبة: 18 فحصًا PASS (تفصيل أعلاه).
- 7 دوال جديدة + notify-lead المحدّثة: deno check نظيف 8/8.
- 43 قالب إيميل: PASS آليًا + معاينة بصرية.
- receipt.html: حالات (بلا رمز/رمز وهمي/رفع) محلية.
- Console الحاسبة: صفر أخطاء في كل الجولات.
- ملاحظة P2: `schedule-change` و`contract-approval` فيهما أخطاء صرامة أنواع قديمة (deno check) — كود إنتاج يعمل ولم يُلمس هذه الجلسة؛ contract-approval منطقة محمية ببروتوكول AGENTS.md. لا تأثير وظيفي.

## Files Changed (شجرة العمل — لا commit بطلب صريح)
```text
calculator.html                        (Phase A سابقًا — مستقر)
sql/000_new_project.sql               (سياسات auth-insert فقط)
sql/001_foundation.sql                (banner إهمال)
sql/013b_close_anon_inserts.sql       (جديد — إغلاق ديناميكي)
sql/014_email_system.sql              (جديد)
sql/015_receipts.sql                  (جديد)
supabase/config.toml                  (5 دوال جديدة)
supabase/functions/notify-lead/       (C-03 للعميل)
supabase/functions/_shared/templates.ts            (جديد)
supabase/functions/send-email/        (جديد)
supabase/functions/email-automation/  (جديد)
supabase/functions/action-token-create/ (جديد)
supabase/functions/receipt-submit/    (جديد)
supabase/functions/coverage-confirm/  (جديد)
supabase/functions/payment-approve/   (جديد)
receipt.html                          (جديد)
AGENTS.md                             (سجل الجلسة)
NEEDS_OWNER_ACTION.md / BLOCKED_DECISIONS.md / NIGHTLY_REPORT.md
```

## Migrations Ready (بترتيب التشغيل)
1. `sql/013b_close_anon_inserts.sql` — **عاجل: أمني**
2. `sql/014_email_system.sql`
3. `sql/015_receipts.sql`

## Security Fixes
- ملف 013b: إغلاق anon-INSERT ديناميكيًا (سدّ الثقب الفعلي المكتشف على الإنتاج).
- 000: بيئة جديدة لن تفتح الثقب مرة أخرى.
- receipt/coverage/payment: تحقق مزدوج (service أو authenticated)، رموز hash-only لمرة واحدة، منع مراحل قديمة، قيود تزامن.
- rate limiting حسب الجوال كما هو معتمد — IP مؤجل (قرار).

## Emails Ready
- **التغطية كاملة P0 + P1** — كل خريطة Email System Map منفذة قالبًا-قالبًا:
  - العملاء: C-01..C-11، C-13، C-14..C-18، C-19 (360)، C-20 (تقييم)
  - C-12 بكل Variants السبعة (إلغاء عميل/إلغاء مأوى/قوة قاهرة/تأخر 30د/عدم حضور/رسوم زيارة/إعادة جدولة) — كل variant يشرح أثره وفق العقد فقط
  - الملاك: O-01..O-08، O-09 (ملفات ناقصة)، O-10 (مراجعة جودة)، O-11 (خطر تأخير تسليم)، O-12 (تسليم/إغلاق) + O-06 بكل Variants الستة
- Idempotency + event version + outdated-event prevention منفذة في send-email
- الأتمتة الزمنية: C-02 (انتهاء عروض) + C-07 (انتهاء Hold) + C-11/O-07 (تذكير 24 ساعة قبل الجلسة — عميل ومصور)
- اختبار: 43 قالبًا/variant آليًا PASS + معاينة بصرية
- المتبقي للتشغيل: secrets Resend + جدولة + نشر الدوال (كلها في NEEDS_OWNER_ACTION).

## Remaining P0
1. تشغيل 013b ثم إعادة Production Smoke Test (أنا أنفذه فور تأكيدك).
2. نشر الدوال + migration 014/015 (خطوات جاهزة في NEEDS_OWNER_ACTION).
3. زرّا الملاك في admin.html (قرار BLOCKED #1 — الكود الخادمي جاهز).

## Remaining P1
- صفحات الإجراءات المتبقية (contract/delivery/rating) على نفس نمط receipt.html.
- Manual Quote Builder (Phase J) — نموذج Quote المشترك جاهز أساسه.
- ربط webhooks C-01 + زرّا الملاك في admin.html (قرارات BLOCKED).

## Owner Actions
→ الملف `NEEDS_OWNER_ACTION.md` — الأهم: **تشغيل 013b الآن** (دقيقتان) وإبلاغي لإعادة الـSmoke Test.

## Recommended Next Step
```text
1) شغّل sql/013b_close_anon_inserts.sql  ← ثم قل "أعد الاختبار"
2) شغّل 014 + 015 وانشر الدوال السبع     ← بعدها أختبر الحجز كاملًا فعليًا
3) قرارات BLOCKED_DECISIONS #1 و#2
```
