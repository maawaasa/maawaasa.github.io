#!/usr/bin/env bash
# =====================================================
# smoke-email-automation.sh v3 — isolated fixtures gate
# إصلاحات v3:
#   - post_row: يلتقط HTTP + RAW_BODY معًا (لا تزاحم ملف) ويحلل id بقوة
#   - أي فشل أثناء تجهيز fixtures ⇒ تنظيف كل ما نُشئ + SAFETY_GATE ⇒ exit 1
#   - المعدات: دائمًا TEST equipment مؤقت [MAAWAA TEST — IGNORE] يُحذف بعد الحذف
#     (لا لمس أي معدات حقيقية إطلاقًا — حتى لو وُجد inventory)
#   - cleanup يشمل أيتام التشغيلات السابقة (clients/equipment بالعلامة داخل النافذة)
# activity_log لا يُقرأ ولا يُحذف. FIXTURES_ONLY=1 ⇒ بلا استدعاء email-automation.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
FN="$BASE/functions/v1/email-automation"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
TS=$(date +%s)
TODAY=$(date -u +%F)
YDAY=$(date -u -v-1d +%F 2>/dev/null || date -u -d "yesterday" +%F)
TOMORROW=$(date -u -v+1d +%F 2>/dev/null || date -u -d "+1 day" +%F)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOLD_START=$(date -u -v-25H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "25 hours ago" +%Y-%m-%dT%H:%M:%SZ)
HOLD_END=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ)
TEST_EMAIL="${TEST_EMAIL:-wfalfaifi@gmail.com}"
TEST_EMAIL_ENC=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$TEST_EMAIL")
TAG="[MAAWAA TEST — IGNORE]"

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
dbcount(){ curl -s "$SB/$1" "${H[@]}" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print(len(d) if isinstance(d,list) else "ERR:"+json.dumps(d)[:200])'; }
run_auto(){ curl -s -o /tmp/ea_body.txt -w "%{http_code}" -X POST "$FN" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}'; }
jget(){ python3 -c "import json;d=json.load(open('/tmp/ea_body.txt'));print(d.get('$1',''))" 2>/dev/null; }
logcount(){ dbcount "email_log?idempotency_key=eq.$1"; }
del(){ curl -s -o /dev/null -X DELETE "$SB/$1" "${H[@]}"; }

# post_row NAME PATH PAYLOAD ⇒ يطبع INSERT_HTTP/RAW_BODY/INSERT_ID ويعيّن LAST_ID
# - tempfile منفصل للجسم + -w للHTTP (بلا تمرير عبر أنبوب)
# - Prefer: return=representation ⇒ PostgREST يعيد الصف المُنشأ (إلا return=minimal الافتراضي)
# - fail-closed: HTTP≠200/201 أو جسم فارغ أو error object أو shape غريب ⇒ FAIL صريح، لا "" زائفة
LAST_ID=""; LAST_HTTP=""; LAST_BODY=""
post_row(){
  local name="$1" path="$2" payload="$3" tmp verdict="OK"
  tmp=$(mktemp)
  LAST_HTTP=$(curl -s -o "$tmp" -w "%{http_code}" -X POST "$SB/$path" "${H[@]}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$payload")
  LAST_BODY=$(cat "$tmp"); rm -f "$tmp"
  LAST_ID=""
  if [ "$LAST_HTTP" != "200" ] && [ "$LAST_HTTP" != "201" ]; then
    verdict="FAIL:HTTP_$LAST_HTTP"
  elif [ -z "$LAST_BODY" ]; then
    verdict="FAIL:EMPTY_RESPONSE_BODY"
  else
    LAST_ID=$(printf '%s' "$LAST_BODY" | python3 -c '
import sys, json
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("__FAIL__:NOT_JSON:" + raw[:120]); raise SystemExit
if isinstance(d, dict) and d.get("code"):
    print("__FAIL__:PG_" + str(d.get("code")) + ":" + str(d.get("message",""))[:150]); raise SystemExit
if isinstance(d, list) and d and isinstance(d[0], dict):
    v = d[0].get("id", "")
    print(v if v else "__FAIL__:NO_ID_IN_ARRAY"); raise SystemExit
if isinstance(d, dict):
    v = d.get("id", "")
    print(v if v else "__FAIL__:NO_ID_IN_OBJECT"); raise SystemExit
print("__FAIL__:UNEXPECTED_SHAPE")')
    case "$LAST_ID" in
      __FAIL__*) verdict="$LAST_ID"; LAST_ID="";;
    esac
  fi
  echo "FIXTURE_NAME=$name INSERT_HTTP=$LAST_HTTP INSERT_ID=$LAST_ID RAW_BODY=$(printf '%s' "$LAST_BODY" | head -c 220) VERDICT=$verdict"
}

# منظفات المسارات المختلفة — كلها مقيّدة ببيانات الاختبار/النافذة
CLEANUP_DONE_MSG="activity_log لم يُمس"
cleanup_fixtures(){
  [ -n "${RESID:-}" ] && del "equipment_reservations?id=eq.$RESID"
  [ -n "${EQID:-}" ] && [ "${EQ_CREATED:-0}" = "1" ] && del "equipment?id=eq.$EQID"
  [ -n "${CC:-}" ] && del "assignments?contract_id=eq.$CC"          # بلا FK ⇒ حذف صريح
  del "employees?email=eq.$TEST_EMAIL_ENC&or=(name=ilike.*Automation*Smoke*,name=ilike.*MAAWAA*TEST*)&created_at=gte.$CUTOFF"
  del "equipment?name=ilike.*MAAWAA*TEST*&created_at=gte.$CUTOFF"   # أيتام معدات سابقة
  del "email_log?idempotency_key=in.(quote%3A$QA%3AC-02%3Av1,contract%3A$CB%3AC-07%3Av1,contract%3A$CC%3AC-11%3Av1,contract%3A$CC%3AO-07%3Av1)"
  for C in "${CB:-}" "${CC:-}" "${CD:-}"; do
    [ -z "$C" ] && continue
    CLID=$(curl -s "$SB/contracts?select=client_id&id=eq.$C" "${H[@]}" | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r[0]["client_id"] if r else "")' 2>/dev/null)
    del "action_tokens?entity_id=eq.$C"; del "contracts?id=eq.$C"
    [ -n "$CLID" ] && del "clients?id=eq.$CLID"
  done
  [ -n "${QA:-}" ] && del "quotes?id=eq.$QA"
  # عملاء بالعلامة داخل النافذة (يشمل أيتام clients من تشغيلات فاشلة سابقة)
  del "clients?email=eq.$TEST_EMAIL_ENC&or=(full_name=ilike.*Automation*Smoke*,full_name=ilike.*MAAWAA*TEST*)&created_at=gte.$CUTOFF"
}
safety_gate(){
  local PQ PH PR
  PQ=$(dbcount "quotes?status=eq.active&valid_until=lt.$TODAY&expired_notified_at=is.null&select=id")
  PH=$(dbcount "contracts?status=in.(new,awaiting_payment)&hold_expires_at=lt.$NOW&receipt_uploaded_at=is.null&select=id")
  PR=$(dbcount "contracts?status=in.(deposit_paid,in_progress)&shoot_date=eq.$TOMORROW&select=id")
  echo "SAFETY_GATE: pending_real_quotes=$PQ pending_real_holds=$PH pending_real_reminders=$PR"
  [ "$PQ" = "0" ] && [ "$PH" = "0" ] && [ "$PR" = "0" ]
}
fixture_fail_exit(){
  echo "FAIL: فشل تجهيز fixtures — تنظيف ما نُشئ قبل الخروج"
  cleanup_fixtures
  if safety_gate; then echo "SAFETY_GATE_AFTER_FAILURE = 0/0/0"; else echo "SAFETY_GATE_AFTER_FAILURE = غير نظيف — راجع يدويًا"; fi
  unset KEY; rm -f /tmp/ea_body.txt /tmp/ea_ins.txt; exit 1
}

echo "===== email-automation isolated smoke v3 — TEST_EMAIL=$TEST_EMAIL ====="
CUTOFF=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)

# ---------- 0) بوابة الأمان ----------
DANGEROUS_Q=$(dbcount "quotes?status=eq.active&valid_until=lt.$TODAY&expired_notified_at=is.null&select=id")
DANGEROUS_H=$(dbcount "contracts?status=in.(new,awaiting_payment)&hold_expires_at=lt.$NOW&receipt_uploaded_at=is.null&select=id")
DANGEROUS_R=$(dbcount "contracts?status=in.(deposit_paid,in_progress)&shoot_date=eq.$TOMORROW&select=id")
echo "SAFETY_GATE: pending_real_quotes=$DANGEROUS_Q pending_real_holds=$DANGEROUS_H pending_real_reminders=$DANGEROUS_R"
if [ "$DANGEROUS_Q" != "0" ] || [ "$DANGEROUS_H" != "0" ] || [ "$DANGEROUS_R" != "0" ]; then
  echo "ABORT: صفوف إنتاج حقيقية ستستقبل إيميلات — لا تشغيل."; unset KEY; exit 1
fi
ok "0) بوابة الأمان"

# ---------- 1) Fixtures ----------
CA=""; QA=""; CB=""; CC=""; CD=""; RESID=""; EQID=""; EQ_CREATED=0

post_row "client_A" "clients" "{\"full_name\":\"$TAG Automation Smoke A\",\"phone_number\":\"0550000110\",\"email\":\"$TEST_EMAIL\"}"
CA="$LAST_ID"
post_row "quote_A" "quotes" "{\"quote_number\":\"Q-SMOKE-$TS\",\"client_id\":\"$CA\",\"service_type\":\"تصوير HDR\",\"total_amount\":2000,\"valid_until\":\"$YDAY\",\"status\":\"active\"}"
QA="$LAST_ID"

CB=$(jq -n --arg d "$TOMORROW" --arg e "$TEST_EMAIL" --arg tag "$TAG" \
  '{p_full_name:($tag + " Automation Smoke B"), p_phone:"0550000111", p_email:$e,
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00",
    p_notes:($tag + " smoke fixture")}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
if [ -n "$CB" ] && [ ${#CB} -ge 32 ]; then
  curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CB" "${H[@]}" -H "Content-Type: application/json" \
    -d "{\"hold_started_at\":\"$HOLD_START\",\"hold_expires_at\":\"$HOLD_END\",\"status\":\"new\"}"
  echo "FIXTURE_NAME=hold_B CONTRACT_ID=$CB (submit_lead)"
fi

# معدات: TEST دائمًا — لا استخدام لأي equipment موجود (قرار 016: بلا seed)
post_row "equipment_TEST" "equipment" "{\"name\":\"$TAG TEST Equipment $TS\",\"type\":\"other\",\"active\":true}"
EQID="$LAST_ID"; EQ_CREATED=1
if [ -n "$CB" ] && [ -n "$EQID" ]; then
  post_row "equipment_reservation_B" "equipment_reservations" \
    "{\"contract_id\":\"$CB\",\"equipment_id\":\"$EQID\",\"start_at\":\"$NOW\",\"end_at\":\"$TOMORROW"T"00:00:00+00:00\",\"status\":\"active\"}"
  RESID="$LAST_ID"
fi

CC=$(jq -n --arg d "$TOMORROW" --arg e "$TEST_EMAIL" --arg tag "$TAG" \
  '{p_full_name:($tag + " Automation Smoke C"), p_phone:"0550000112", p_email:$e,
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00",
    p_notes:($tag + " smoke fixture")}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
if [ -n "$CC" ] && [ ${#CC} -ge 32 ]; then
  curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CC" "${H[@]}" -H "Content-Type: application/json" \
    -d '{"status":"deposit_paid"}'
  echo "FIXTURE_NAME=reminder_C CONTRACT_ID=$CC (submit_lead)"
fi
# مصور TEST + assignment لاختبار O-07 (بلا مصورين حقيقيين)
post_row "employee_TEST" "employees" \
  "{\"name\":\"$TAG TEST Photographer $TS\",\"role\":\"photographer\",\"is_active\":true,\"email\":\"$TEST_EMAIL\"}"
EMPID="$LAST_ID"
ASGID=""
if [ -n "$CC" ] && [ -n "$EMPID" ]; then
  post_row "assignment_C" "assignments" \
    "{\"contract_id\":\"$CC\",\"employee_id\":\"$EMPID\",\"role_in_job\":\"photographer\"}"
  ASGID="$LAST_ID"
fi

CD=$(jq -n --arg d "$TOMORROW" --arg e "$TEST_EMAIL" --arg tag "$TAG" \
  '{p_full_name:($tag + " Automation Smoke D"), p_phone:"0550000113", p_email:$e,
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00",
    p_notes:($tag + " smoke fixture outdated")}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
if [ -n "$CD" ] && [ ${#CD} -ge 32 ]; then
  curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CD" "${H[@]}" -H "Content-Type: application/json" \
    -d "{\"hold_started_at\":\"$HOLD_START\",\"hold_expires_at\":\"$HOLD_END\",\"receipt_uploaded_at\":\"$NOW\"}"
  echo "FIXTURE_NAME=outdated_D CONTRACT_ID=$CD (submit_lead)"
fi

READY=1
[ -z "$CA" ] && { echo "FIXTURE_FAIL=client_A"; READY=0; }
[ -z "$QA" ] && { echo "FIXTURE_FAIL=quote_A"; READY=0; }
[ -z "$CB" ] && { echo "FIXTURE_FAIL=hold_B"; READY=0; }
[ -z "$EQID" ] && { echo "FIXTURE_FAIL=equipment"; READY=0; }
[ -z "$RESID" ] && { echo "FIXTURE_FAIL=reservation_B"; READY=0; }
[ -z "$CC" ] && { echo "FIXTURE_FAIL=reminder_C"; READY=0; }
[ -z "$CD" ] && { echo "FIXTURE_FAIL=outdated_D"; READY=0; }
[ -z "$EMPID" ] && { echo "FIXTURE_FAIL=employee_TEST"; READY=0; }
[ -z "$ASGID" ] && { echo "FIXTURE_FAIL=assignment_C"; READY=0; }

# ---------- 1ب) وضع تشخيص fixtures فقط ----------
if [ "${FIXTURES_ONLY:-0}" = "1" ]; then
  [ -n "$CA" ] && echo "CLIENT_A_FIXTURE=PASS" || echo "CLIENT_A_FIXTURE=FAIL"
  [ -n "$QA" ] && echo "QUOTE_FIXTURE=PASS" || echo "QUOTE_FIXTURE=FAIL"
  [ -n "$CB" ] && echo "HOLD_FIXTURE=PASS" || echo "HOLD_FIXTURE=FAIL"
  [ -n "$RESID" ] && echo "RESERVATION_FIXTURE=PASS" || echo "RESERVATION_FIXTURE=FAIL"
  [ -n "$CC" ] && echo "REMINDER_FIXTURE=PASS" || echo "REMINDER_FIXTURE=FAIL"
  [ -n "$CD" ] && echo "OUTDATED_FIXTURE=PASS" || echo "OUTDATED_FIXTURE=FAIL"
  cleanup_fixtures
  if safety_gate; then echo "SAFETY_GATE_AFTER_FIXTURES = 0/0/0"; else echo "SAFETY_GATE_AFTER_FIXTURES = غير نظيف"; fi
  echo "FIXTURES_ONLY_DONE — لم يُستدعَ email-automation — $CLEANUP_DONE_MSG"
  unset KEY; rm -f /tmp/ea_body.txt /tmp/ea_ins.txt; exit 0
fi

[ $READY = 1 ] && ok "1) fixtures جاهزة (quote=$QA hold=$CB reminder=$CC outdated=$CD res=$RESID)" \
  || fixture_fail_exit

# ---------- 2) التشغيل الأول: 1/1/2 (C-11 + O-07 عبر مصور TEST) ----------
HTTP1=$(run_auto)
A_Q=$(jget quotes_expired); A_H=$(jget holds_expired); A_R=$(jget shoot_reminders)
echo "RUN1_HTTP=$HTTP1 quotes=$A_Q holds=$A_H reminders=$A_R"
if [ "$HTTP1" = "200" ] && [ "$A_Q" = "1" ] && [ "$A_H" = "1" ] && [ "$A_R" = "2" ]; then
  ok "2) RUN1 ⇒ 1 quote + 1 hold + 2 reminders (C-11 عميل + O-07 مصور TEST)"
else no "2): HTTP=$HTTP1 q=$A_Q h=$A_H r=$A_R — BODY=$(cat /tmp/ea_body.txt)"; fi

# ---------- 3) تحققات DB + email_log ----------
sleep 2
QSTAT=$(curl -s "$SB/quotes?select=status,expired_notified_at&id=eq.$QA" "${H[@]}" | python3 -c 'import sys,json;r=json.load(sys.stdin)[0];print(r["status"],bool(r["expired_notified_at"]))')
C02=$(logcount "quote%3A$QA%3AC-02%3Av1")
HOLDCLEARED=$(curl -s "$SB/contracts?select=hold_expires_at&id=eq.$CB" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["hold_expires_at"] is None)')
C07=$(logcount "contract%3A$CB%3AC-07%3Av1")
RES_STATUS=$(curl -s "$SB/equipment_reservations?select=status&id=eq.$RESID" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["status"])')
C11=$(logcount "contract%3A$CC%3AC-11%3Av1")
O07=$(logcount "contract%3A$CC%3AO-07%3Av1")
CST_C=$(curl -s "$SB/contracts?select=status&id=eq.$CC" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["status"])')
C07_D=$(logcount "contract%3A$CD%3AC-07%3Av1")
D_HOLD=$(curl -s "$SB/contracts?select=hold_expires_at&id=eq.$CD" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["hold_expires_at"])')
[ "$QSTAT" = "expired True" ] && ok "3a) quote ⇒ expired + طابع" || no "3a): [$QSTAT]"
[ "$C02" = "1" ] && ok "3b) C-02 ⇒ email_log=1" || no "3b): $C02"
[ "$HOLDCLEARED" = "True" ] && ok "3c) hold تحرر فعليًا" || no "3c): $HOLDCLEARED"
[ "$C07" = "1" ] && ok "3d) C-07 ⇒ email_log=1" || no "3d): $C07"
[ "$RES_STATUS" = "released" ] && ok "3e) reservation TEST ⇒ released" || no "3e): $RES_STATUS"
[ "$C11" = "1" ] && [ "$CST_C" = "deposit_paid" ] && ok "3f) C-11 ⇒ 1 والحالة ثابتة" || no "3f): $C11/$CST_C"
[ "$O07" = "1" ] && ok "3g) O-07 ⇒ email_log=1 (مصور TEST)" || no "3g): O-07=$O07"
[ "$C07_D" = "0" ] && [ "$D_HOLD" != "None" ] && ok "3h) outdated ⇒ لا C-07 وhold سليم" || no "3h): $C07_D/$D_HOLD"

# ---------- 4) إعادة التشغيل ⇒ لا duplicates ----------
HTTP2=$(run_auto)
B_Q=$(jget quotes_expired); B_H=$(jget holds_expired); B_R=$(jget shoot_reminders)
C02B=$(logcount "quote%3A$QA%3AC-02%3Av1"); C07B=$(logcount "contract%3A$CB%3AC-07%3Av1")
C11B=$(logcount "contract%3A$CC%3AC-11%3Av1"); O07B=$(logcount "contract%3A$CC%3AO-07%3Av1")
if [ "$HTTP2" = "200" ] && [ "$B_Q" = "0" ] && [ "$B_H" = "0" ] && [ "$B_R" = "0" ] \
   && [ "$C02B" = "1" ] && [ "$C07B" = "1" ] && [ "$C11B" = "1" ] && [ "$O07B" = "1" ]; then
  ok "4) RUN2 ⇒ 0/0/0 وemail_log ثابت (1/1/1/1)"
else no "4): HTTP=$HTTP2 q=$B_Q h=$B_H r=$B_R logs=$C02B/$C07B/$C11B/$O07B"; fi

# ---------- 5) Cleanup ----------
cleanup_fixtures
if safety_gate; then ok "5) SAFETY_GATE_AFTER = 0/0/0 — $CLEANUP_DONE_MSG"; else no "5): البوابة غير نظيفة بعد التنظيف"; fi

rm -f /tmp/ea_body.txt /tmp/ea_ins.txt
unset KEY
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
