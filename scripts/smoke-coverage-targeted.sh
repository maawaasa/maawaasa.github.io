#!/usr/bin/env bash
# =====================================================
# smoke-coverage-targeted.sh — 4 اختبارات Targeted معزولة لـ coverage-confirm
# كل اختبار: عقد جديد مستقل + fixtures مثبتة من DB قبل الاستدعاء + Cleanup كامل
# كل الـparsing بـ jq حصريًا. بيانات الاعتماد محلية ولا تُطبع.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")

TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

# ===== أدوات مساعدة (jq حصريًا) =====
mk_contract(){ # name phone email date → contract_id
  jq -n --arg n "$1" --arg p "$2" --arg e "$3" --arg d "$4" \
    '{p_full_name:$n, p_phone:$p, p_email:$e, p_service_type:"تصوير HDR",
      p_total:2000, p_property_type:"apartment", p_shoot_date:$d,
      p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""'
}
del_contract_artifacts(){ # يحذف كل آثار عقد اختبار
  local cid="$1"
  curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/assignments?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/equipment_reservations?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/contract_equipment?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$cid" "${H[@]}"
}
cleanup_client(){ local ids="$1"; [ -n "$ids" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=in.($ids)" "${H[@]}"; }
find_client(){ jq -r --arg n "$1" '[.[] | select(.full_name == $n)][0].id // ""'; }

# مصور نشط واحد لكل الاختبارات
PID=$(curl -s "$SB/employees?select=id,name&role=eq.photographer&is_active=eq.true&order=sort_order&limit=1" "${H[@]}" \
  | jq -r '.[0].id // ""')
[ -z "$PID" ] && { echo "FAIL: لا مصور نشط — كل الاختبارات تتوقف"; exit 1; }
echo "photographer: $PID"

#####################################################
echo
echo "===== TEST 1: PHOTOGRAPHER CONFLICT ====="
#####################################################
CA=$(mk_contract "T1 Smoke" "0550000101" "t1@test.local" "$TOMORROW")
[ ${#CA} -ge 32 ] || { echo "FAIL: إنشاء C_A"; exit 1; }

# Fixture: جلسة متداخلة 11:00–13:00 للمصور نفسه في نفس التاريخ
SCH_BODY=$(jq -n \
  --arg employee_id "$PID" \
  --arg job_date "$TOMORROW" \
  --arg start_time "11:00:00" \
  --arg end_time "13:00:00" \
  '{
    employee_id: $employee_id,
    job_date: $job_date,
    start_time: $start_time,
    end_time: $end_time,
    status: "scheduled",
    title: "conflict-probe-1"
  }')
printf '%s' "$SCH_BODY" | jq -e . >/dev/null || { echo "FAIL: SCH_BODY"; exit 1; }
SINS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SB/schedule" "${H[@]}" \
  -H "Content-Type: application/json" --data "$SCH_BODY")

# إثبات ما قبل الاستدعاء: صف التعارض موجود فعلًا في DB بمطابقة كاملة
FIX=$(curl -s "$SB/schedule?select=id,employee_id,job_date,start_time,end_time,status,title&employee_id=eq.$PID&job_date=eq.$TOMORROW" "${H[@]}")
FIXOK=$(printf '%s' "$FIX" | jq --arg p "$PID" --arg d "$TOMORROW" \
  '[.[] | select(.employee_id == $p and .job_date == $d
                 and .start_time == "11:00:00" and .end_time == "13:00:00"
                 and .status == "scheduled" and .title == "conflict-probe-1")] | length')
if [ "${SINS}" = "201" ] && [ "${FIXOK:-0}" -ge 1 ]; then
  ok "fixture مثبت في DB قبل الاستدعاء: $FIX"
else
  no "fixture لم يُثبَّت (SINS=$SINS FIXOK=$FIXOK)"
fi

# الاستدعاء: نافذة متداخلة 11:00–13:00
c=$(curl -s -o /tmp/t1.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CA\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"11:00\",\"end_time\":\"13:00\"}")
e=$(jq -r '.error // ""' /tmp/t1.txt)
if [ "$c" = "409" ] && [ "$e" = "photographer_unavailable" ]; then
  ok "رفض 409 photographer_unavailable رغم وجود fixture"
else
  no "المتوقع 409 photographer_unavailable — الواقع HTTP $c err=$e body=$(head -c 200 /tmp/t1.txt)"
fi

# Cleanup T1
curl -s -o /dev/null -X DELETE "$SB/schedule?employee_id=eq.$PID&job_date=eq.$TOMORROW&title=eq.conflict-probe-1" "${H[@]}"
del_contract_artifacts "$CA"
CL=$(curl -s "$SB/clients?select=id&full_name=eq.T1%20Smoke" "${H[@]}" | jq -r 'map(.id) | join(",")')
cleanup_client "$CL"
echo "  cleanup T1 تم"

#####################################################
echo
echo "===== TEST 2: EQUIPMENT CONFLICT ====="
#####################################################
CB=$(mk_contract "T2 Smoke" "0550000102" "t2@test.local" "$TOMORROW")
C2=$(mk_contract "T2 Holder" "0550000103" "t2h@test.local" "$TOMORROW")
[ ${#CB} -ge 32 ] && [ ${#C2} -ge 32 ] || { echo "FAIL: إنشاء عقود T2"; exit 1; }

EQNAME="Smoke Cam $(date +%s)"
EQ_BODY=$(jq -n --arg name "$EQNAME" '{name:$name, type:"camera", active:true}')
EQ_HTTP=$(curl -s -o /tmp/eq_body.txt -w "%{http_code}" -X POST "$SB/equipment?select=id" "${H[@]}" \
  -H "Content-Type: application/json" -H "Prefer: return=representation" \
  --data "$EQ_BODY")
EQ=$(jq -r '.[0].id // ""' /tmp/eq_body.txt 2>/dev/null)
if [ -z "$EQ" ]; then
  echo "FAIL: إنشاء معدات الاختبار — HTTP $EQ_HTTP: $(head -c 200 /tmp/eq_body.txt)"
  exit 1
fi
echo "  equipment fixture: $EQNAME ($EQ)"
curl -s -o /dev/null -X POST "$SB/contract_equipment" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CB\",\"equipment_id\":\"$EQ\"}"

# Fixture: حجز active متداخل (08:00–14:00 يغطي 10:00–12:00) لعقد آخر
RES_BODY=$(jq -n --arg c "$C2" --arg e "$EQ" --arg d "$TOMORROW" \
  '{contract_id:$c, equipment_id:$e,
    start_at:($d + "T08:00:00+03:00"), end_at:($d + "T14:00:00+03:00"), status:"active"}')
printf '%s' "$RES_BODY" | jq -e . >/dev/null || { echo "FAIL: RES_BODY"; exit 1; }
RINS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SB/equipment_reservations" "${H[@]}" \
  -H "Content-Type: application/json" --data "$RES_BODY")

# إثبات ما قبل الاستدعاء: الحجز المتداخل موجود في DB
RES=$(curl -s "$SB/equipment_reservations?select=id,contract_id,equipment_id,start_at,end_at,status&equipment_id=eq.$EQ&status=eq.active" "${H[@]}")
RESOK=$(printf '%s' "$RES" | jq --arg c "$C2" --arg e "$EQ" \
  '[.[] | select(.contract_id == $c and .equipment_id == $e and .status == "active")] | length')
if [ "${RINS}" = "201" ] && [ "${RESOK:-0}" -ge 1 ]; then
  ok "حجز معدات متداخل مثبت في DB قبل الاستدعاء: $RES"
else
  no "حجز المعدات لم يثبت (RINS=$RINS RESOK=$RESOK)"
fi

c=$(curl -s -o /tmp/t2.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CB\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
e=$(jq -r '.error // ""' /tmp/t2.txt)
if [ "$c" = "409" ] && [ "$e" = "equipment_unavailable" ]; then
  ok "رفض 409 equipment_unavailable"
else
  no "المتوقع 409 equipment_unavailable — الواقع HTTP $c err=$e body=$(head -c 200 /tmp/t2.txt)"
fi

# Cleanup T2
curl -s -o /dev/null -X DELETE "$SB/equipment_reservations?contract_id=eq.$CB" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/contract_equipment?contract_id=eq.$CB" "${H[@]}"
del_contract_artifacts "$CB"
CL=$(curl -s "$SB/clients?select=id&full_name=eq.T2%20Smoke" "${H[@]}" | jq -r 'map(.id) | join(",")')
cleanup_client "$CL"
del_contract_artifacts "$C2"
CL2=$(curl -s "$SB/clients?select=id&full_name=eq.T2%20Holder" "${H[@]}" | jq -r 'map(.id) | join(",")')
cleanup_client "$CL2"
curl -s -o /dev/null -X DELETE "$SB/equipment?id=eq.$EQ" "${H[@]}"
echo "  cleanup T2 تم"

#####################################################
echo
echo "===== TEST 3: HOLD_24H + TOKEN_SINGLETON ====="
#####################################################
CC=$(mk_contract "T3 Smoke" "0550000104" "t3@test.local" "$TOMORROW")
[ ${#CC} -ge 32 ] || { echo "FAIL: إنشاء C_C"; exit 1; }

# إثبات ما قبل الاستدعاء: صفر tokens + Hold فارغ
PRE_TOK=$(curl -s "$SB/action_tokens?select=id&entity_id=eq.$CC" "${H[@]}" | jq 'length')
PRE_HOLD=$(curl -s "$SB/contracts?select=hold_started_at,hold_expires_at&id=eq.$CC" "${H[@]}" \
  | jq -r '.[0] | "started=\(.hold_started_at // "NULL") expires=\(.hold_expires_at // "NULL")"')
if [ "${PRE_TOK}" = "0" ]; then
  ok "قبل الاستدعاء: tokens=0 و Hold فارغ ($PRE_HOLD)"
else
  no "قبل الاستدعاء: tokens=$PRE_TOK (يجب 0)"
fi

c=$(curl -s -o /tmp/t3.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CC\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")

# إثبات ما بعد الاستدعاء من DB مباشرة
POST_TOK=$(curl -s "$SB/action_tokens?select=id,token_hash,purpose,used_at,entity_id&entity_id=eq.$CC" "${H[@]}")
TOKN=$(printf '%s' "$POST_TOK" | jq 'length')
ROW=$(curl -s "$SB/contracts?select=status,hold_started_at,hold_expires_at,deposit_review_status&id=eq.$CC" "${H[@]}")
HOLD_OK=$(printf '%s' "$ROW" | jq -r --argjson now "$(date -u +%s)" '
  .[0] as $r
  | ($r.hold_started_at != null) as $s
  | ($r.hold_expires_at != null) as $e
  | (($r.hold_expires_at | sub("\\.\\d+(Z|\\+00:00)$";"Z") | sub("\\+00:00$";"Z") | fromdateiso8601) - $now) as $diff
  | if $r.status == "awaiting_payment" and $s and $e
       and $diff >= 82800 and $diff <= 90000 then "OK" else "BAD" end')

if [ "$c" = "200" ] && [ "$TOKN" = "1" ] && [ "$HOLD_OK" = "OK" ]; then
  ok "HOLD_24H: 200 + hold_started_at/hold_expires_at ≈24h + awaiting_payment"
  if [ "$TOKN" = "1" ]; then
    ok "TOKEN_SINGLETON: token واحد فقط لهذا العقد"
  else
    no "TOKEN_SINGLETON: عدد tokens = $TOKN"
  fi
else
  no "HOLD_24H: HTTP $c HOLD=$HOLD_OK TOKN=$TOKN — $(head -c 200 /tmp/t3.txt)"
fi

# Cleanup T3
del_contract_artifacts "$CC"
CL3=$(curl -s "$SB/clients?select=id&full_name=eq.T3%20Smoke" "${H[@]}" | jq -r 'map(.id) | join(",")')
cleanup_client "$CL3"
echo "  cleanup T3 تم"

#####################################################
echo
echo "===== TEST 4: CONCURRENCY ====="
#####################################################
CD=$(mk_contract "T4 Smoke" "0550000105" "t4@test.local" "$TOMORROW")
[ ${#CD} -ge 32 ] || { echo "FAIL: إنشاء C_D"; exit 1; }

PAYLOAD=$(jq -n --arg c "$CD" --arg p "$PID" \
  '{contract_id:$c, photographer_employee_id:$p, start_time:"10:00", end_time:"12:00"}')
printf '%s' "$PAYLOAD" | jq -e . >/dev/null || { echo "FAIL: PAYLOAD"; exit 1; }

curl -s -o /tmp/cc_a.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" --data "$PAYLOAD" > /tmp/cc_a.code 2>/dev/null &
PA=$!
curl -s -o /tmp/cc_b.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" --data "$PAYLOAD" > /tmp/cc_b.code 2>/dev/null &
PB=$!
wait $PA $PB
A=$(cat /tmp/cc_a.code 2>/dev/null || echo '?')
B=$(cat /tmp/cc_b.code 2>/dev/null || echo '?')

echo "request A: HTTP $(cat /tmp/cc_a.code 2>/dev/null || echo '?') body=$(head -c 120 /tmp/cc_a.txt 2>/dev/null)"
echo "request B: HTTP $(cat /tmp/cc_b.code 2>/dev/null || echo '?') body=$(head -c 120 /tmp/cc_b.txt 2>/dev/null)"
echo "A=$A B=$B"

WINS=0; [ "$A" = "200" ] && WINS=$((WINS+1))
[ "$B" = "200" ] && WINS=$((WINS+1))

# تحقق DB بعد التزامن: فائز واحد، بلا تكرارات
STATUS=$(curl -s "$SB/contracts?select=status,hold_started_at,hold_expires_at&id=eq.$CD" "${H[@]}")
ASGN=$(curl -s "$SB/assignments?select=id&contract_id=eq.$CD" "${H[@]}" | jq 'length')
TOKN=$(curl -s "$SB/action_tokens?select=id&entity_id=eq.$CD" "${H[@]}" | jq 'length')
RESN=$(curl -s "$SB/equipment_reservations?select=id&contract_id=eq.$CD&status=eq.active" "${H[@]}" | jq 'length')

if [ "$WINS" = "1" ] && [ "$ASGN" -le 1 ] && [ "$TOKN" -le 1 ] && [ "$RESN" -le 1 ]; then
  ok "CONCURRENCY: فائز واحد (A=$A B=$B) — assignments=$ASGN tokens=$TOKN reservations=$RESN"
else
  no "CONCURRENCY: WINS=$WINS assignments=$ASGN tokens=$TOKN reservations=$RESN"
fi

# Cleanup T4
del_contract_artifacts "$CD"
CL4=$(curl -s "$SB/clients?select=id&full_name=eq.T4%20Smoke" "${H[@]}" | jq -r 'map(.id) | join(",")')
cleanup_client "$CL4"
echo "  cleanup T4 تم"

#####################################################
echo
echo "===================== النتيجة: $pass PASS / $fail FAIL ====================="
[ $fail -eq 0 ]
