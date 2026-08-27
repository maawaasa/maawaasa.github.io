# دالة الإشعارات — notify-lead

## اعتماد العقود وإرسالها

تحتاج المنظومة كذلك إلى الأسرار الخادمية `RESEND_API_KEY` و
`CONTRACT_APPROVAL_SECRET`. طبّق `sql/009_contract_delivery.sql` ثم انشر دالتي
`notify-lead` و`contract-approval`. يجب إبقاء التحقق القياسي من JWT مفعّلًا في
الدالتين؛ صفحة الاعتماد ترسل مفتاح Supabase العام بالإضافة إلى الرابط الموقّع
محدود الصلاحية.

دالة خادمية على Supabase Edge Functions ترسل إشعارات الطلبات الجديدة إلى البريد ومجموعة تلجرام، وتضيف الطلب تلقائياً إلى قاعدة «إدارة طلبات مأوى» في نوشن.

الأسرار (توكن تلجرام ومفتاح Web3Forms ومفتاح نوشن) تُخزن في خادم Supabase ولا تظهر في كود الموقع إطلاقاً.

## قبل النشر — إجراءات إلزامية

النسخة القديمة من `assets/js/supabase-config.js` كانت تحتوي التوكن والمفتاح بشكل مكشوف، لذا تعتبر مسروقة:

1. افتح تلجرام وتحدث مع `@BotFather` ثم نفّذ `/revoke` وألغ التوكن القديم وولّد توكن جديداً للبوت.
2. ادخل لوحة Web3Forms واحذف المفتاح القديم وأنشئ مفتاحاً جديداً.

## خطوات النشر

تثبيت أداة Supabase CLI (مرة واحدة فقط):

```bash
brew install supabase/tap/supabase
```

ثم تسجيل الدخول وربط المشروع:

```bash
supabase login
```

```bash
supabase link --project-ref fivrwlowntwacfrsocge
```

من داخل مجلد `ويب`، تخزين الأسرار (ضع القيم الجديدة بعد علامة `=`):

```bash
supabase secrets set TELEGRAM_TOKEN=التوكن_الجديد TELEGRAM_CHAT=معرف_المجموعة WEB3FORMS_ACCESS_KEY=المفتاح_الجديد NOTION_TOKEN=مفتاح_نوشن
```

ملاحظة عن `TELEGRAM_CHAT`: القيمة القديمة كانت `-5540002104` — إن بقيت المجموعة نفسها استخدمها كما هي، وإن أردت الجديدة أرسل رسالة للمجموعة ثم افتح في المتصفح:

```bash
https://api.telegram.org/bot<التوكن>/getUpdates
```

وسترى `chat.id` في النتيجة.

نشر الدالة (من داخل مجلد `ويب` أيضاً):

```bash
supabase functions deploy notify-lead
```

لا تستخدم خيار `--no-verify-jwt` أبداً — التحقق من المفتاح يمنع الغرباء من مناداة الدالة بشكل عشوائي.

## اختبار الدالة

```bash
curl -X POST 'https://fivrwlowntwacfrsocge.supabase.co/functions/v1/notify-lead' \
  -H 'Authorization: Bearer <SUPABASE_ANON_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{"text":"رسالة تجريبية من مأوى"}'
```

الناتج المتوقع `{"ok":true}` مع وصول رسالة للمجموعة والبريد.

## كيف تعمل

- الموقع ينادي الدالة من `assets/js/supabase-config.js` عبر `notifyOwner(text, contractId)` دون أي أسرار.
- الدالة تجلب تفاصيل الطلب الحقيقية من Supabase باستخدام `contractId`، ثم تنشئ صفاً في قاعدة نوشن المشتركة مع الاتصال.
- معرّف Supabase يُحفظ في ملاحظات صف نوشن، ويُستخدم لمنع إنشاء الطلب نفسه مرتين.
- الدالة تتحقق من الطلب، تحدد معدل الإرسال (5 طلبات لكل دقيقة لكل IP)، ثم ترسل إلى تلجرام وWeb3Forms ونوشن.
- تُزال وسوم HTML من رسالة الإشعار قبل إرسالها.

## تحديث الأسرار مستقبلاً

```bash
supabase secrets set TELEGRAM_TOKEN=قيمة_جديدة
```

لا حاجة لإعادة النشر عند تغيير الأسرار.
