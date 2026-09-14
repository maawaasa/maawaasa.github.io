# CURRENT_HANDOVER — MAAWAA Launch (للاستمرار فقط)

## 1) القواعد الثابتة (لا تُكسر)
- Quote صالح 14 يومًا. Q-XXXX دائم للعرض · MAW-XXXX للطلب (تسلسل خادمي، لا عشوائي).
- الحاسبة لا تنشئ Order. Save Quote ≠ Request Booking.
- اختيار الموعد في Quote لا يحجزه. Hold 24h بعد تأكيد التغطية.
- رفع الإيصال أثناء Hold يوقف العدّاد ويحفظ الحجز أثناء المراجعة (Receipt ≠ Approved).
- 25% ⇒ Booking Confirmed. الرصيد قبل التسليم. Standard 7–10 أيام، Express +25%.
- خروج الرياض = Manual Pricing بلا سعر تلقائي. لا Automatic Discounts ولا Travel Fees.
- Google Calendar للحجوزات المؤكدة فقط. RAW غير مشمول. حفظ 30 يومًا · 360 لـ12 شهرًا.
- Telegram للملاك فقط · Supabase = Source of Truth · Phase 1 = Email-First · لا Customer Portal.
- RPC-only public writes: submit_lead / submit_quote فقط — لا direct anon INSERT (013b).
- approve_payment_atomic: service_role فقط (لا PUBLIC/anon/authenticated).
- email-automation: AUTOMATION_SECRET فقط (لا service_role).

## 2) Production Status
Migrations: 013 ✅ 013b ✅ 014 ✅ 014b(=015/016/017 سلسلة ✅)
Team Auth: وفاء/محمد/مالك/أسامة = PASS عبر auth_user_id (isTeamMember).

## 3) Deployed + Tested (FINAL PASS)
| Function | الحالة |
|---|---|
| action-token-create | Deploy ✅ Final Smoke PASS ✅ |
| receipt-submit | Deploy ✅ 10/10 + Hold Transition 5/5 ✅ |
| coverage-confirm | Deploy ✅ Full Smoke PASS (BOOT fix + conflict + hold + equipment) ✅ |
| payment-approve | Deploy ✅ 13/13 Isolated Smoke PASS ✅ |
| send-email | Deploy ✅ Real Resend delivery ✅ Idempotency ✅ |
| notify-lead | Deploy ✅ C-03 dispatch ✅ |
| email-automation | Deploy ✅ 9/9 (C-02/C-07/C-11/O-07 + equipment release) ✅ |

## 4) NOT Deployed Yet
- calculator/index.html + calculator.html bridge (الكود جاهز — بعد الـE2E)

## 5) الملفات المهمة
| ملف | الغرض |
|---|---|
| sql/013–017 | Migrations (منفذة) |
| scripts/smoke-e2e-full.sh | Full E2E (التالي) |
| scripts/smoke-coverage-team-v2.sh | Coverage targeted |
| scripts/smoke-receipt-submit.sh | Receipt isolated |
| scripts/smoke-action-token-create.sh | Token isolated |
| supabase/functions/email-automation/ | C-02/C-07/C-11/O-07 automation |
| supabase/functions/payment-approve/ | Financial atomic RPC |
| supabase/functions/send-email/ | Unified email sender |
| CURRENT_HANDOVER.md | هذا الملف |
| NEEDS_OWNER_ACTION.md | إجراءات المالك |

## 6) Security Rules (لا تُكسر)
- UUIDs في jq: --arg نصوص فقط — لا tonumber (سبب Invalid numeric literal)
- SECURITY DEFINER: search_path='' + REVOKE من PUBLIC/anon + أسماء مؤهلة
- Equipment tables: service_role فقط (REVOKE من authenticated/anon)
- approve_payment_atomic: EXECUTE لـservice_role فقط
- Timestamps: Python fromisoformat مع استبدال Z→+00:00 (يدعم fractional)
- Contract status gate: outdated_state 409 قبل أي Hold
- Bearer parsing: exact match، لا substring/includes
- AUTOMATION_SECRET: env function — لا يُطبع ولا يُخزن في repo

## 7) الخطوة التالية بالضبط
**Full Production E2E Smoke:**

```bash
./scripts/smoke-e2e-full.sh
```

(يطلب service_role — من Dashboard → Settings → API)

يغطي: Quote Q-XXXX → Booking MAW-XXXX (linked) → Coverage Hold → C-04 → Receipt → Payment deposit → fully_paid → email_log verification → no duplicates → no auto-discounts → cleanup.

بعد PASS: نشر calculator → Final Regression → إغلاق.

## 8) لا يُعاد (PASS نهائي)
013–017 migrations · Team Auth · action-token-create · receipt-submit (10/10 + Hold 5/5) · coverage-confirm (BOOT+conflicts+hold+equipment+concurrency) · payment-approve (13/13) · send-email (real delivery+idempotency) · notify-lead (C-03) · email-automation (9/9)

## 9) Blockers
- None — كل شيء unblocked، بانتظار تشغيل الـE2E.
