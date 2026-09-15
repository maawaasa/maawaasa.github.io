#!/usr/bin/env bash
# =====================================================
# smoke-email-templates.sh — معاينة قوالب C-04 / C-08 / C-17
# يرسل 3 رسائل معاينة حقيقية عبر send-email إلى بريد المالك.
# entity_id = null ⇒ يتخطى فحص outdated · event_version فريد ⇒ بلا تصادم idempotency
# روابط الأزرار demo (maawaa.sa/token=preview) — للاطلاع البصري فقط.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
FN="$BASE/functions/v1"
SB="$BASE/rest/v1"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " SRK; echo
[ -z "$SRK" ] && { echo "المفتاح مطلوب"; exit 1; }

TEST_EMAIL="wfalfaifi@gmail.com"
V=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

pass=0; fail=0
ok(){ echo "✓ $1"; pass=$((pass+1)); }
no(){ echo "✗ $1"; fail=$((fail+1)); }

send(){ # $1=event  $2=data-json
  curl -s -w "\n%{http_code}" -X POST "$FN/send-email" \
    -H "Authorization: Bearer $SRK" -H "Content-Type: application/json" \
    -d "{\"event_type\":\"$1\",\"event_version\":$V,\"entity_type\":\"contract\",\"entity_id\":null,\"to\":\"$TEST_EMAIL\",\"to_name\":\"معاينة القوالب\",\"data\":$2}"
}

check_log(){ # $1=event
  curl -s "$SB/email_log?select=status,error&event_type=eq.$1&recipient=eq.$TEST_EMAIL&order=created_at.desc&limit=1" \
    -H "apikey: $ANON" -H "Authorization: Bearer $SRK" \
    | jq -r '.[0].status // "missing"'
}

DATA_COMMON="\"contract_number\":\"MAW-PREVIEW\",\"client_name\":\"[معاينة قوالب]\",\"services\":\"تصوير HDR — فيديو سينمائي\",\"shoot_date\":\"$TOMORROW\",\"shoot_time\":\"10:00 — 12:00\",\"location\":\"الرياض — حي النرجس\",\"total\":2000,\"deposit\":500,\"remaining\":1500"

echo "=========================================="
echo "  EMAIL TEMPLATE PREVIEWS → $TEST_EMAIL"
echo "  version marker: v$V"
echo "=========================================="

# --- C-04: بانتظار العربون (warning + زر رفع + واتساب) ---
R=$(send "C-04" "{$DATA_COMMON,\"deposit_upload_url\":\"https://maawaa.sa/receipt?token=preview-demo\"}")
C=$(echo "$R" | tail -1)
[ "$C" = "200" ] && ok "C-04 إرسال HTTP 200" || no "C-04 HTTP $C — $(echo "$R" | head -1 | head -c 150)"
S=$(check_log "C-04"); [ "$S" = "sent" ] && ok "C-04 email_log = sent" || no "C-04 email_log = $S"

# --- C-08: حجز مؤكد (success) ---
R=$(send "C-08" "{$DATA_COMMON,\"contract_url\":\"https://maawaa.sa/contract?token=preview-demo\",\"calendar_url\":\"https://maawaa.sa/calendar?token=preview-demo\"}")
C=$(echo "$R" | tail -1)
[ "$C" = "200" ] && ok "C-08 إرسال HTTP 200" || no "C-08 HTTP $C — $(echo "$R" | head -1 | head -c 150)"
S=$(check_log "C-08"); [ "$S" = "sent" ] && ok "C-08 email_log = sent" || no "C-08 email_log = $S"

# --- C-17: مخرجات جاهزة (success + زر تحميل + واتساب) ---
R=$(send "C-17" "{$DATA_COMMON,\"delivery_url\":\"https://maawaa.sa/delivery?token=preview-demo\"}")
C=$(echo "$R" | tail -1)
[ "$C" = "200" ] && ok "C-17 إرسال HTTP 200" || no "C-17 HTTP $C — $(echo "$R" | head -1 | head -c 150)"
S=$(check_log "C-17"); [ "$S" = "sent" ] && ok "C-17 email_log = sent" || no "C-17 email_log = $S"

echo ""
echo "================ $pass PASS / $fail FAIL ================"
echo "افحص بريدك: $TEST_EMAIL — ثلاث رسائل بعناوين:"
echo "  1) لديك 24 ساعة لتثبيت موعدك (C-04)"
echo "  2) تم تأكيد حجزك (C-08)"
echo "  3) مخرجاتك جاهزة للتحميل (C-17)"
[ $fail -eq 0 ]
