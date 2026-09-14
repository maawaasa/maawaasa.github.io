#!/usr/bin/env bash
# =====================================================
# smoke-send-email.sh — اختبار إرسال حقيقي/جاف عبر send-email
# شروط الاستخدام:
#   - service_role يُدخل محليًا فقط (بلا echo، لا يُطبع، unset بالنهاية)
#   - RESEND_API_KEY لا يُطلب هنا إطلاقًا — يعيش في Supabase Secrets
#   - TEST EMAIL فقط: افتراضيًا عنوان test.local
#     (مع مفتاح Resend حقيقي استخدم صندوقًا تملكه:
#        TEST_EMAIL="you@yourdomain.com" bash scripts/smoke-send-email.sh )
#   - حدث C-03 غير حساس على عقد اختبار يُنشأ ويُحذف
#   - idempotency: نفس المفتاح مرتين ⇒ email_log صف واحد فقط
#   - cleanup: email_log لصفوف الاختبار فقط — activity_log لا يُمس إطلاقًا
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
FN="$BASE/functions/v1/send-email"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
TS=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)
TEST_EMAIL="${TEST_EMAIL:-send-smoke-$TS@test.local}"

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
dbcount(){ curl -s "$SB/$1" "${H[@]}" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print(len(d) if isinstance(d,list) else "ERR:"+json.dumps(d)[:200])'; }
logrow(){ curl -s "$SB/email_log?select=status,recipient,payload&idempotency_key=eq.$1" "${H[@]}"; }

echo "===== send-email smoke — TEST_EMAIL=$TEST_EMAIL ====="

# ---------- 0) عقد اختبار (C-03 يتطلب status=new) ----------
CID=$(jq -n --arg d "$TOMORROW" --arg e "$TEST_EMAIL" \
  '{p_full_name:"Send Smoke", p_phone:"0550000108", p_email:$e,
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
if [ -z "$CID" ] || [ ${#CID} -lt 32 ]; then echo "FAIL: فشل إنشاء العقد: [$CID]"; unset KEY; exit 1; fi
IKEY="contract:$CID:C-03:v1"
echo "contract=$CID"
echo "idempotency_key=$IKEY"

PAYLOAD="{\"event_type\":\"C-03\",\"entity_type\":\"contract\",\"entity_id\":\"$CID\",\"to\":\"$TEST_EMAIL\",\"to_name\":\"Send Smoke\",\"data\":{\"contract_number\":null,\"client_name\":\"Send Smoke\",\"services\":\"تصوير HDR\",\"shoot_date\":\"$TOMORROW\",\"location\":\"اختبار\"}}"

# ---------- 1) الإرسال الأول ----------
HTTP1=$(curl -s -o /tmp/sse1.txt -w "%{http_code}" -X POST "$FN" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$PAYLOAD")
RESULT1=$(python3 -c 'import json;print(json.load(open("/tmp/sse1.txt")).get("result",""))' 2>/dev/null)
echo "FIRST_HTTP=$HTTP1 FIRST_RESULT=$RESULT1"
if [ "$HTTP1" = "200" ] && { [ "$RESULT1" = "sent" ] || [[ "$RESULT1" == sent_dry* ]]; }; then
  case "$RESULT1" in sent_dry*) echo "MODE=DRY (لا RESEND_API_KEY — تسجيل بلا إرسال فعلي)";; *) echo "MODE=REAL";; esac
  ok "1) استدعاء أول ⇒ $RESULT1"
else
  echo "BODY1=$(cat /tmp/sse1.txt)"
  no "1) الاستدعاء الأول: HTTP=$HTTP1 result=$RESULT1"
  [[ "$RESULT1" == failed* ]] && echo "HINT: مع RESEND حقيقي استخدم: TEST_EMAIL=\"صندوق حقيقي تملكه\" bash scripts/smoke-send-email.sh"
fi

# ---------- 2) email_log: صف واحد بالضبط ----------
LOG_COUNT=$(dbcount "email_log?idempotency_key=eq.$IKEY")
ROW=$(logrow "$IKEY")
LOG_STATUS=$(echo "$ROW" | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r[0]["status"] if r else "")' 2>/dev/null)
LOG_DRY=$(echo "$ROW" | python3 -c 'import sys,json;r=json.load(sys.stdin);print(bool((r[0].get("payload") or {}).get("_dry")) if r else "")' 2>/dev/null)
LOG_RCPT=$(echo "$ROW" | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r[0].get("recipient","") if r else "")' 2>/dev/null)
if [ "$LOG_COUNT" = "1" ] && [ "$LOG_STATUS" = "sent" ] && [ "$LOG_RCPT" = "$TEST_EMAIL" ]; then
  ok "2) email_log ⇒ صف واحد status=sent recipient=TEST_EMAIL _dry=$LOG_DRY"
else
  no "2) email_log: count=$LOG_COUNT status=$LOG_STATUS rcpt=$LOG_RCPT"
fi

# ---------- 3) نفس المفتاح مرة ثانية ⇒ skipped_duplicate ولا صف جديد ----------
HTTP2=$(curl -s -o /tmp/sse2.txt -w "%{http_code}" -X POST "$FN" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$PAYLOAD")
RESULT2=$(python3 -c 'import json;print(json.load(open("/tmp/sse2.txt")).get("result",""))' 2>/dev/null)
LOG_COUNT2=$(dbcount "email_log?idempotency_key=eq.$IKEY")
if [ "$HTTP2" = "200" ] && [ "$RESULT2" = "skipped_duplicate" ] && [ "$LOG_COUNT2" = "1" ]; then
  ok "3) إعادة نفس المفتاح ⇒ skipped_duplicate والصف ما زال 1 (لا إرسال مكرر)"
else
  echo "BODY2=$(cat /tmp/sse2.txt)"
  no "3) إعادة الاستدعاء: HTTP=$HTTP2 result=$RESULT2 count=$LOG_COUNT2"
fi

# ---------- 4) Cleanup (بيانات الاختبار فقط) ----------
curl -s -o /dev/null -X DELETE "$SB/email_log?idempotency_key=eq.$IKEY" "${H[@]}"
CLID=$(curl -s "$SB/contracts?select=client_id&id=eq.$CID" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["client_id"])')
curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$CID" "${H[@]}"
[ -n "$CLID" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$CLID" "${H[@]}"
LEFT=$(dbcount "email_log?idempotency_key=eq.$IKEY")
if [ "$LEFT" = "0" ]; then ok "4) cleanup: email_log الخاص بالاختبار حُذف — activity_log لم يُمس"; else no "4) cleanup: بقي $LEFT"; fi

rm -f /tmp/sse1.txt /tmp/sse2.txt
unset KEY
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
