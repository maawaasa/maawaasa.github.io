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
| 2026-08-28 | opencode | تبني تصميم العقد المعتمد الجديد بمحرك المتجهات — فرع `agent/opencode-contract` | جارية |

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
| `calculator.html` | Price calculator + quote/booking (indexable) | yes — leads |
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
- Keep new content and copy in Arabic; preserve RTL layout.
- الأرقام في العقد الرسمي إنجليزية (1,850 ر.س) وليست هندية-عربية.
- اسم المؤسسة الرسمي: **مؤسسة مأوى المهارة التجارية** (ليس «المهارية»).
- `robots.txt` / `sitemap.xml` must stay in sync with the live URLs.
