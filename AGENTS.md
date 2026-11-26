# AGENTS.md

Guidance for AI agents working on the مأوى (MAWA) website.

## بروتوكول الترابط بين الوكلاء — اقرأ هذا أولاً

يعمل على هذا المستودع أكثر من وكيل ذكاء اصطناعي (opencode و ChatGPT وغيرهما) بالتناوب مع المالك. القواعد ملزمة:

1. **قبل بدء أي جلسة:** نفّذ `git pull --rebase origin main`. إذا كان فرعك خلف الأصل حدّثه قبل أي تعديل.
2. **جلسة نشطة واحدة فقط.** لا يشتغل وكيلان على نفس المستودع بنفس الوقت. من يبدأ جلسة يعلنها في «سجل الجلسات» أدناه، ومن ينهي يسجل ما أنجزه.
3. **الشغل على فروع:** أي عمل غير تافه يتم على فرع باسم `agent/<الوكيل>-<المهمة>` ويُدمج بالرئيسي بعد موافقة المالك. لا تكتب مباشرة على `main` أثناء وجود فرع نشط لمهمة نفس الملفات.
4. **مناطق محمية — لا تُعدَّل إلا باتفاق صريح من المالك:**
   - دالة `buildContractEmail` وكل ما يتعلق بإرسال البريد في `supabase/functions/contract-approval/index.ts`
   - زر «معاينة البريد» ومسار الإرسال من `info@maawaa.sa` في `approve-contract.html`
   - مفاتيح Supabase وأسرار الدوال
5. **قبل استبدال أي نظام قائم** (مولّد PDF، محرر، نموذج) تأكد أن البديل يغطي كل قدرات الأصل، واذكر الاستبدال صراحة في رسالة الـ commit. استبدال نظام بآخر أضعف يُعد خرقاً.
6. **البيانات التجريبية** (أسماء عملاء وهمية مثل «عبدالله المطيري») مسموحة في ملفات معاينة مؤقتة فقط، ولا تُرسل للمستودع.
7. **رسائل الـ commit بالعربية**، صغيرة ومركزة، ملف واحد أو مجموعة مترابطة لكل commit.
8. **النشر إلى الإنتاج** (push إلى `main`) لا يتم إلا بعد عرض النتيجة على المالك وموافقته — إلا إذا طلب المالك غير ذلك صراحة في تلك الجلسة.
9. عند اكتشاف تعارض دمج: حلّه يدوياً مع الحفاظ على عمل الطرف الآخر، ولا تستخدم force-push أبداً.

### سجل الجلسات

| التاريخ | الوكيل | المهمة | الحالة |
|--------|--------|--------|--------|
| 2026-08-28 | opencode | إصلاح سكيما + ترقية قانونية للعقد + نظام صفحات الخدمات (عبر نسخة `~/mawa-app`) | منشور على main |
| 2026-08-28 | opencode | تبني تصميم العقد المعتمد الجديد بمحرك المتجهات — فرع `agent/opencode-contract` | منتهية (سلمها Codex) |
| 2026-08-28 | opencode | استلام جلسة من Codex: واتساب بكل بريد العميل + صف موعد ثلاثي متجاوب + اسم رسمي + إصلاحات schedule/Notion/التأكيد | منتهية — سُلمت إلى ChatGPT عبر HANDOFF-CHATGPT.md |
| 2026-09-09 | opencode | الحاسبة: Multi-Unit (1 Site + N Units) بلا خصومات تلقائية + فصل Save Quote (Q-XXXX/14 يوم) عن Booking + إلغاء رسوم التنقل وخارج الرياض تسعير يدوي + `sql/013_quotes_mvp.sql` | منتهية — بانتظار مراجعة المالك قبل الـcommit |
| 2026-09-09 | opencode | جلسة ليلية: 013b إغلاق anon-INSERT ديناميكيًا + 014/015 (email_log + Hold + action_tokens) + 7 دوال جديدة (send-email/email-automation/action-token-create/receipt-submit/coverage-confirm/payment-approve + C-03 في notify-lead) + 43 قالب إيميل P0+P1 + receipt.html + جناح انحدار الحاسبة 18 فحصًا | منتهية — بانتظار تشغيل 013b و014/015 ونشر الدوال (NEEDS_OWNER_ACTION.md) |
| 2026-09-09 | opencode | روابط الحاسبة النظيفة: `calculator/index.html` هو التطبيق الفعلي على `/calculator`، الحالة في مسار URL (`/calculator/<type>/<rooms>/<units>/<services>/<extras>`) بدل query، `calculator.html` جسر توافق للروابط القديمة، `404.html` جديد لدعم الروابط العميقة، وتحديث الروابط في index/blog/sitemap/llms.txt | منتهية — بانتظار مراجعة المالك |
| 2026-11-25 | Claude Code | إعادة تصميم `index.html` بنسخة سينمائية فاخرة: فصول داكنة (الهيدر، الشوريل، المجموعة الخاصة، الفوتر) وفاتحة للبقية، الهيدر الأصلي مع درون يطير بفيزياء واقعية (فُصل عن الصورة: `assets/cinema/hero-plate.jpg` + `drone.png`)، خطوط Instrument Serif + Jost للنص الإنجليزي، تقليص المحتوى من 15 قسماً إلى 8 فصول، وتدقيق UI/UX، وأيقونة الشعار في نتائج قوقل (رمز أبيض على أسود) مع عنوان عربي أولاً، وعارض سينمائي لقسم «مشاهد من أعمالنا» بكل لقطات المشروعين — فرع `claude/mawa-landing-page-design-095d51` (PR #1) | منشور على main بموافقة المالك |
| 2026-11-25 | Claude Code | مراجعة حاسبة الأسعار وإصلاحها: روابط الفئات الفاخرة كانت توقف الصفحة، مستند العرض يضاعف الدرون والإعلاني، الروابط تفقد الإضافات عند فتحها، رقم العرض المحفوظ يلتصق بتعديلات لاحقة، مسار الحجز (ملخص الموعد، منتصف الليل، خارج الرياض بلا عربون)، تحقق بقواعد الخادم ورسالة لكل رفض، جدول الأسعار، الوضع الإنجليزي كاملاً، شريط إجمالي للجوال ووصولية — لا تغيير في الأسعار ولا في نظام الحملة — فرع `agent/claude-calculator-fixes` | منشور على main بموافقة المالك |
| 2026-11-26 | Claude Code | إعادة بناء `index.html` بالتصميم الفاخر الفاتح الذي اعتمده المالك (لون رملي واحد بدرجاته والأسود للنص والأزرار، عناوين بوزنين، بطاقات زجاجية، صور مأوى الحقيقية بدل صور الخلفيات السوداء) مع الحفاظ على كل محتوى الصفحة ووظائفها وبياناتها لمحركات البحث، وخطوط ثمانية (سيرف تكست بالزخارف للعناوين + سانز للنص) مستضافة في `assets/fonts/thmanyah/` بإذن مكتوب من ثمانية لدى المالك بدل Google Fonts، وهوية «أسود وبلاتيني» التي اختارها المالك (كل ألوان الهوية متغيرات في `:root`، وشريط أسود عميق لقسم «المجموعة الخاصة»)، وجدول أسعار منظم بأعمدة ثابتة، وقسم الخدمات «شريط الفيلم» الذي اختاره المالك من أربعة نماذج معروضة على الصفحة (لوحات داكنة تتّسع النشطة منها وتعود صورتها للألوان، تبديل تلقائي يتوقف عند مرور المؤشر، شريط مزايا أسود متحرك، وصور الخدمات `assets/lux/svc-*`)، وحذف قائمة الأحياء من الفوتر بطلب المالك (يبقى «موقع التصوير — الرياض» فقط؛ لا تُعِد القائمة) — فرع `claude/shelter-page-redesign-6810c1` | منشور على main بموافقة المالك — الصور في `assets/lux/` والخطوط في `assets/fonts/thmanyah/` |

## Repository scope

- The git repo root is this folder (`مأوى MAWA/ويب/`). The OneDrive parent directory holds unrelated design assets (PDFs/SVGs/PNGs) and is **not** part of the site — do not reference or commit anything outside `ويب/`.
- Static marketing site for a Saudi real-estate photography company. Arabic, RTL (`<html lang="ar" dir="rtl">`).
- No build step, no framework, no `package.json`, no tests. Verify changes by opening the HTML file in a browser.

## Deploy

- `git push origin main` publishes to GitHub Pages at **https://maawaa.sa/**. There is no staging environment — the `main` branch is live.
- Commit messages are written in Arabic (see `git log`); follow that convention.

## Architecture

| File | Purpose | Supabase |
|------|---------|----------|
| `index.html` | Public marketing page (indexable) | no |
| `calculator/index.html` | Price calculator + quote/booking (indexable). العنوان الرسمي: `https://maawaa.sa/calculator` — الحالة في مسار URL نظيف (`/calculator/villa/6/2/photo+drone/rush`) بدل query. `calculator.html` جسر توافق يحوّل الروابط القديمة `?t=&r=...`، و`404.html` يلقط روابط المسارات العميقة على GitHub Pages | yes — leads |
| `form.html` | Service-request form (noindex) | yes — inserts |
| `admin.html` | Private contract-management tool (noindex, disallowed) | yes — full CRUD |
| `approve-contract.html` | عقد الاعتماد: معاينة العقد + معاينة البريد + توليد PDF متجهي (jsPDF + خط IBM Plex العربي مغرّس + شعارات SVG عبر svg2pdf) وإرساله للعميل | yes — via Edge Function |
| `verify.html` | صفحة تحقق عامة من صحة العقود (تُستدعى بتوقيع HMAC) | yes — via Edge Function |
| `blog/` | مقالات تسويقية | no |

- **No shared CSS/JS across pages.** Design tokens and the Supabase bootstrap are duplicated per page — update every page that needs it.
- Note: variables named `--gold*` are actually blue (`#7AAAD4`) — preserve the names; do not "fix" them.

## نظام العقود (Contract pipeline)

1. الطلب يبدأ من الحاسبة/النموذج → جداول `clients` / `contracts` / `contract_services` في Supabase Postgres.
2. صفحة «إدارة طلبات مأوى» في Notion هي لوحة المتابعة (٣٥ عموداً) — تُقرأ عبر Notion API بالتكامل الموجود.
3. زر «اعتماد وإرسال العقد» في Notion يفتح `approve-contract.html` برابط موقّع (HMAC + انتهاء صلاحية).
4. الدالة `supabase/functions/contract-approval/index.ts` تجلب بيانات العقد (Supabase) والدفعات والخصومات وموعد الجلسة (Notion)، وتتضمن:
   - `preview` — بيانات المعاينة
   - `email_preview` — قالب البريد (دالة `buildContractEmail`) — **محمية**
   - `send` — رفع PDF للتخزين + إرسال Resend من `info@maawaa.sa` + تحديث Notion (الحالة + ملف العقد)
   - `verify` — تحقق عام بتوقيع مستقل
5. PDF العقد يُولَّد في المتصفح بـ jsPDF متجهياً (نص قابل للتحديد) — حافظ على هذه الجودة.

## Backend (Supabase)

- Loaded via CDN; config in `assets/js/supabase-config.js` exposes `getSupabase()`. The anon key is public — not a secret.
- Edge Functions: `notify-lead` (إشعارات الفريق)، `contract-approval` (العقود). Secrets live server-side only — never in frontend files. See `supabase/DEPLOY.md`.
- Deploy of functions: `supabase functions deploy <name>` (CLI linked to project `fivrwlowntwacfrsocge`).

## Conventions

- All libraries are CDN-loaded; never add npm dependencies.
- Fonts: the site uses IBM Plex Sans Arabic (contracts + approve pages); legacy pages may still use Tajawal.
- **خطوط ثمانية في `index.html` — بإذن مكتوب:** الصفحة الرئيسية تستخدم خطوط ثمانية الرسمية من `assets/fonts/thmanyah/` (Thmanyah Serif Text للعناوين والأرقام الكبيرة مع الزخارف `font-feature-settings:"salt","swsh","dlig"` — وهي نفسها نسخة Swash — وThmanyah Sans للنص والأزرار والواجهة). استضافتها على الموقع تمت **بإذن مكتوب من شركة ثمانية لدى المالك** (أكده المالك في 2026-11-26)؛ فلا تحذفها ولا تستبدلها ولا تعدّها مخالفة ترخيص. ملفات woff2 مستخدمة كما وردت من ثمانية — لا تعدّلها ولا تقتطع منها (subsetting). الخط يرسم «ر.س» تلقائياً برمز الريال الجديد.
- **هوية الألوان في `index.html` — «أسود وبلاتيني» (اختيار المالك 2026-11-26):** خلفيات لؤلؤية فاتحة، الأسود للنص والأزرار، والبلاتين للّمعات المعدنية (تدرّج كلمات العناوين `--g-head`، الأرقام الكبيرة `--g-num`، الفواصل الشعرية، دوائر الأزرار). كل ألوان الهوية متغيرات في `:root` — تبديل الهوية = تغيير قيمها فقط، ولا ألوان هوية مكتوبة مباشرة في القواعد. قسم «المجموعة الخاصة» (`.col`) شريط أسود عميق بإعادة تعريف المتغيرات داخله (`--b-*`). **المالك لا يريد الذهبي إطلاقاً** — لا تُدخل ذهبياً أو شمبانيا أو نحاسياً في أي تعديل؛ البديل المعتمد البلاتين. الأسماء `--sand`/`--bronze` تاريخية: `--sand` = البلاتين، `--bronze` = الغرافيت.
- Keep new content and copy in Arabic; preserve RTL layout.
- الأرقام في العقد الرسمي إنجليزية (1,850 ر.س) وليست هندية-عربية.
- اسم المؤسسة الرسمي: **مؤسسة مأوى المهارة التجارية** (ليس «المهارية»).
- `robots.txt` / `sitemap.xml` must stay in sync with the live URLs.
