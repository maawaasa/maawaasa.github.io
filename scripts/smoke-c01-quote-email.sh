#!/usr/bin/env bash
# =====================================================
# smoke-c01-quote-email.sh — C-01 «عرض السعر جاهز» (معزول)
# 1) submit_quote حقيقي → Q-XXXX + quote_id (بدون MAW)
# 2) quote-notify → C-01 sent (مفتاح quote:<id>:C-01:v1)
# 3) إعادة الاستدعاء → لا بريد إضافي
# 4) invalid/unknown UUID → 400/404
# 5) quote غير active → skipped_outdated
# 6) cleanup: quote/client فقط — email_log/activity_log يبقيان
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"; FN="$BASE/functions/v1"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"
TEST_EMAIL="wfalfaifi@gmail.com"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
q(){ curl -s "$SB/$1" "${H[@]}"; }
TS=$(date +%s)

CID=""; CLID=""
cleanup_fail(){
  [ -n "${CID:-}" ] || return 0
  curl -s -o /dev/null -X DELETE "$SB/quotes?id=eq.$CID" "${H[@]:-}"
  [ -n "${CLID:-}" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$CLID" "${H[@]:-}"
  echo "[trap] cleanup done"
}
trap cleanup_fail EXIT

echo "===== C-01 Quote Ready Flow ====="
# 1) invalid UUID → 400
C=$(curl -s -o /tmp/c01_1.json -w "%{http_code}" -X POST "$FN/quote-notify" \
  -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"quote_id":"not-a-uuid"}')
[ "$C" = "400" ] && [ "$(jq -r .error /tmp/c01_1.json)" = "invalid_quote_id" ] \
  && ok "invalid UUID → 400 invalid_quote_id" || no "invalid: $C $(cat /tmp/c01_1.json)"

# 2) UUID صالح غير موجود → 404 (رد عام بلا PII)
RAND="11111111-2222-4333-8444-555555555555"
C=$(curl -s -o /tmp/c01_2.json -w "%{http_code}" -X POST "$FN/quote-notify" \
  -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"quote_id\":\"$RAND\"}")
[ "$C" = "404" ] && [ "$(jq -r .error /tmp/c01_2.json)" = "not_found" ] \
  && ok "quote غير موجود → 404 not_found" || no "unknown: $C $(cat /tmp/c01_2.json)"

# 3) fixture: submit_quote حقيقي
QID=$(jq -n --arg e "$TEST_EMAIL" '{p_full_name:"[C01 FLOW TEST]",p_phone:"0550000999",p_email:$e,p_property_type:"apartment",p_service_type:"تصوير HDR",p_total:2000,p_units:[{kind:"main",type:"apartment",rooms:2,qty:1}],p_payload:{summary:"تصوير HDR"}}' \
  | curl -s -X POST "$SB/rpc/submit_quote" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" --data @-)
QID=$(echo "$QID" | jq -r '.id // ""'); QNUM=$(echo "$QID" | jq -r '.quote_number // ""')
CLID=$(q "quotes?select=client_id&id=eq.$QID" | jq -r '.[0].client_id // ""')
[ ${#QID} -ge 32 ] && ok "fixture: $QNUM ($QID)" || { no "fixture فشل"; exit 1; }
CID="$QID"

# 4) لا MAW order من حفظ العرض (قرار الفصل)
ORDERS=$(q "contracts?select=id&client_id=eq.$CLID" | jq length)
[ "$ORDERS" = "0" ] && ok "حفظ العرض لم ينشئ أي MAW order (contracts=0)" || no "orders=$ORDERS"

# 5) quote-notify → C-01 sent
C=$(curl -s -o /tmp/c01_3.json -w "%{http_code}" -X POST "$FN/quote-notify" \
  -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"quote_id\":\"$QID\"}")
R=$(jq -r .result /tmp/c01_3.json)
EK=$(q "email_log?select=idempotency_key,status,recipient&entity_id=eq.$QID&event_type=eq.C-01" | jq -c '.[0] // null')
[ "$C" = "200" ] && [ "$R" = "sent" ] && [ "$(echo "$EK" | jq -r .status)" = "sent" ] \
  && [ "$(echo "$EK" | jq -r .recipient)" = "$TEST_EMAIL" ] \
  && [ "$(echo "$EK" | jq -r .idempotency_key)" = "quote:$QID:C-01:v1" ] \
  && ok "C-01 sent للمفتاح quote:<id>:C-01:v1 إلى $TEST_EMAIL" || no "send: $C/$R — $EK"

# 6) إعادة الاستدعاء → لا بريد إضافي
C2=$(curl -s -o /tmp/c01_4.json -w "%{http_code}" -X POST "$FN/quote-notify" \
  -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"quote_id\":\"$QID\"}")
N2=$(q "email_log?select=id&entity_id=eq.$QID&event_type=eq.C-01" | jq length)
[ "$C2" = "200" ] && [ "$N2" = "1" ] && ok "إعادة الاستدعاء → skipped_duplicate + بريد واحد فقط" \
  || no "repeat: $C2 rows=$N2"

# 7) quote غير active → skipped_outdated
curl -s -o /dev/null -X PATCH "$SB/quotes?id=eq.$QID" "${H[@]}" -H "Content-Type: application/json" -d '{"status":"expired"}'
# اختبار إضافي: quote جديد لكن منتهي الصلاحية → gate يمنع
QID3=$(jq -n --arg e "$TEST_EMAIL" '{p_full_name:"[C01 FLOW TEST 2]",p_phone:"0550000998",p_email:$e,p_property_type:"apartment",p_service_type:"تصوير HDR",p_total:1500}' \
  | curl -s -X POST "$SB/rpc/submit_quote" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" --data @- | jq -r '.id // ""')
CLID3=$(q "quotes?select=client_id&id=eq.$QID3" | jq -r '.[0].client_id // ""')
curl -s -o /dev/null -X PATCH "$SB/quotes?id=eq.$QID3" "${H[@]}" -H "Content-Type: application/json" -d '{"status":"expired"}'
C3=$(curl -s -o /tmp/c01_5.json -w "%{http_code}" -X POST "$FN/quote-notify" \
  -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"quote_id\":\"$QID3\"}")
[ "$C3" = "200" ] && [ "$(jq -r .result /tmp/c01_5.json)" = "skipped_outdated" ] \
  && ok "quote غير active → skipped_outdated بلا إرسال" || no "inactive: $C3 $(cat /tmp/c01_5.json)"

# ===== تنظيف (email_log/activity_log يبقيان) =====
del(){ curl -s -o /dev/null -w "%{http_code} " -X DELETE "$SB/$1" "${H[@]}"; }
echo "--- cleanup ---"
del "quotes?id=eq.$QID"; del "quotes?id=eq.$QID3"
[ -n "$CLID" ] && del "clients?id=eq.$CLID"
[ -n "$CLID3" ] && del "clients?id=eq.$CLID3"
CID=""; CLID=""
echo "cleanup done (email_log/activity_log بقيا كسجل)"

echo ""
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
