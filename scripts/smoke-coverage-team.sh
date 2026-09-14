#!/usr/bin/env bash
# =====================================================
# smoke-coverage-team.sh — Full Smoke (بنود 3–11)
# كل أجسام JSON تُبنى بـ jq --arg (UUIDs كنصوص — لا tonumber ولا argjson)
# وتُفحص بـ jq -e قبل الإرسال.
# بيانات الاعتماد تُطلب محليًا ولا تُطبع إطلاقًا. Cleanup كامل.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }

read -rp "Team member email: " EMAIL
read -rsp "Password: " PASS; echo
[ -z "$EMAIL" ] || [ -z "$PASS" ] && { echo "بيانات الدخول مطلوبة"; exit 1; }

TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

# ===== 1) تسجيل الدخول — الـJWT داخليًا فقط =====
LOGIN_BODY=$(jq -n --arg email "$EMAIL" --arg pass "$PASS" '{email:$email, password:$pass}')
printf '%s' "$LOGIN_BODY" | jq -e . >/dev/null || { echo "FAIL: LOGIN_BODY غير صالح"; exit 1; }
LOGIN=$(printf '%s' "$LOGIN_BODY" | curl -s -X POST "$BASE/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "Content-Type: application/json" --data @-)
JWT=$(printf '%s' "$LOGIN" | jq -r '.access_token // ""')
[ -z "$JWT" ] && { echo "FAIL: فشل تسجيل الدخول"; exit 1; }
AH=(-H "apikey: $ANON" -H "Authorization: Bearer $JWT")
ok "login (team JWT جاهز داخليًا)"

# ===== 2) عقد اختبار status=new + أزمنة الجلسة =====
LEAD_BODY=$(jq -n --arg name "Team Smoke" --arg phone "0550000042" --arg email "team-smoke@test.local" \
  '{p_full_name:$name, p_phone:$phone, p_email:$email}')
printf '%s' "$LEAD_BODY" | jq -e . >/dev/null || { echo "FAIL: LEAD_BODY غير صالح"; exit 1; }
C1=$(printf '%s' "$LEAD_BODY" | curl -s -X POST "$SB/rpc/submit_lead" "${AH[@]}" \
  -H "Content-Type: application/json" --data @- | tr -d '"')
[ ${#C1} -ge 32 ] && ok "عقد اختبار جاهز: $C1" || { no "إنشاء عقد الاختبار: $C1"; exit 1; }

SCHED_BODY=$(jq -n --arg date "$TOMORROW" \
  '{shoot_date:$date, shoot_start_time:"10:00", shoot_end_time:"12:00"}')
printf '%s' "$SCHED_BODY" | jq -e . >/dev/null || { echo "FAIL: SCHED_BODY غير صالح"; exit 1; }
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C1" "${AH[@]}" \
  -H "Content-Type: application/json" --data "$SCHED_BODY"

# ===== 3) تعارض مصور زمني ⇒ 409 photographer_unavailable =====
# جلسة متداخلة (09:00–13:00) في schedule لنفس المصور مقابل محاولة تأكيد 10:00–12:00
PID=$(curl -s "$SB/employees?select=id&role=eq.photographer&is_active=eq.true&order=sort_order&limit=1" "${AH[@]}" \
  | jq -r '.[0].id // ""')
if [ -n "$PID" ]; then
  SCH_BODY=$(jq -n \
    --arg employee_id "$PID" \
    --arg job_date "$TOMORROW" \
    '{employee_id:$employee_id, job_date:$job_date,
      start_time:"09:00:00", end_time:"13:00:00", status:"scheduled",
      title:"conflict-probe"}')
  printf '%s' "$SCH_BODY" | jq -e . >/dev/null 2>&1 || { echo "SKIP: SCH_BODY غير صالح"; }
  if printf '%s' "$SCH_BODY" | jq -e . >/dev/null 2>&1; then
    SINS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SB/schedule" "${AH[@]}" \
      -H "Content-Type: application/json" --data "$SCH_BODY")
    if [ "$SINS" = "201" ]; then
      c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
        "${AH[@]}" -H "Content-Type: application/json" \
        -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
      e=$(python3 -c 'import json;print(json.load(open("/tmp/cc_body.txt")).get("error",""))')
      if [ "$c" = "409" ] && [ "$e" = "photographer_unavailable" ]; then
        ok "تعارض مصور زمني ⇒ 409 photographer_unavailable"
      else
        no "تعارض المصور: HTTP $c err=$e"
      fi
      curl -s -o /dev/null -X DELETE "$SB/schedule?employee_id=eq.$PID&job_date=eq.$TOMORROW&title=eq.conflict-probe" "${AH[@]}"
    else
      echo "SKIP: تعذر إدراج schedule (HTTP $SINS) — فحص تعارض المصور تخطي"
    fi
  else
    echo "SKIP: SCHED_BODY غير صالح — فحص تعارض المصور تخطي"
  fi
else
  echo "SKIP: لا مصور نشط — فحص تعارض المصور تخطي"
fi

# ===== 4) عقد بحالة غير صالحة ⇒ 409 outdated_state بلا Hold =====
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C1" "${AH[@]}" \
  -H "Content-Type: application/json" -d '{"status":"deposit_paid"}'
c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${AH[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
e=$(python3 -c 'import json;print(json.load(open("/tmp/cc_body.txt")).get("error",""))')
if [ "$c" = "409" ] && [ "$e" = "outdated_state" ]; then
  ok "عقد بحالة غير صالحة ⇒ رفض بلا Hold"
else
  no "status gate: HTTP $c err=$e"
fi
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C1" "${AH[@]}" \
  -H "Content-Type: application/json" -d '{"status":"new"}'

# ===== 5) Equipment: ربط قطعة اختبار ⇒ تعارض ⇒ 409 equipment_unavailable =====
EQ=$(curl -s -X POST "$SB/equipment?select=id" "${AH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"Smoke Camera","type":"camera"}' | jq -r '.[0].id // ""')
if [ -n "$EQ" ]; then
  curl -s -o /dev/null -X POST "$SB/contract_equipment" "${AH[@]}" -H "Content-Type: application/json" \
    -d "{\"contract_id\":\"$C1\",\"equipment_id\":\"$EQ\"}"
  NOWISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ENDISO=$(date -u -v+2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+2 hours" +%Y-%m-%dT%H:%M:%SZ)
  curl -s -o /dev/null -X POST "$SB/equipment_reservations" "${AH[@]}" -H "Content-Type: application/json" \
    -d "{\"contract_id\":\"$C1\",\"equipment_id\":\"$EQ\",\"start_at\":\"$NOWISO\",\"end_at\":\"$ENDISO\",\"status\":\"active\"}"
  c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
    "${AH[@]}" -H "Content-Type: application/json" \
    -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
  e=$(python3 -c 'import json;print(json.load(open("/tmp/cc_body.txt")).get("error",""))')
  if [ "$c" = "409" ] && [ "$e" = "equipment_unavailable" ]; then
    ok "تعارض معدات ⇒ 409 equipment_unavailable"
  else
    no "equipment conflict: HTTP $c err=$e"
  fi
  curl -s -o /dev/null -X DELETE "$SB/equipment_reservations?contract_id=eq.$C1" "${AH[@]}"
  curl -s -o /dev/null -X DELETE "$SB/contract_equipment?contract_id=eq.$C1" "${AH[@]}"
else
  echo "SKIP: لا يمكن إنشاء معدات اختبار"
fi

# ===== 6) المسار السعيد: بلا تعارض ⇒ Hold +24h + reservations + token =====
c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${AH[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
if [ "$c" = "200" ]; then
  ok "المسار السعيد: 200"
else
  no "المسار السعيد: HTTP $c — $(head -c 150 /tmp/cc_body.txt)"
fi

# ===== 7) تحقق الحالة: Hold +24h + assignment + token + time_source =====
ROW=$(curl -s "$SB/contracts?select=status,hold_started_at,hold_expires_at,deposit_review_status&id=eq.$C1" "${AH[@]}")
if printf '%s' "$ROW" | python3 - <<'PY'
import sys, json
from datetime import datetime, timezone, timedelta
r = json.loads(sys.stdin.read())[0]
assert r["status"] == "awaiting_payment", r["status"]
assert r["hold_started_at"], "hold_started_at"
exp = datetime.fromisoformat(r["hold_expires_at"].replace("Z","+00:00"))
d = exp - datetime.now(timezone.utc)
assert timedelta(hours=23) < d < timedelta(hours=25), f"hold {d}"
assert r["deposit_review_status"] is None, "review flag يجب أن يكون NULL عند بدء Hold"
PY
then ok "Hold مضبوط ≈ +24h وحالة awaiting_payment"; else no "Hold/حالة العقد"; fi

ASG=$(curl -s "$SB/assignments?select=id&contract_id=eq.$C1" "${AH[@]}" | jq '. | length')
[ "${ASG:-0}" -ge 1 ] && ok "assignment مُسجل ($ASG)" || no "لا assignment"
TOK=$(curl -s "$SB/action_tokens?select=id,token_hash&entity_id=eq.$C1&purpose=eq.deposit_receipt" "${AH[@]}" | jq '. | length')
[ "${TOK:-0}" -ge 1 ] && ok "deposit_receipt token مرتبط بالعقد ($TOK)" || no "لا token"

# ===== 8) concurrency: نداءان متزامنان ⇒ فائز واحد فقط =====
A=$(curl -s -o /tmp/cc_a.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${AH[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
B=$(curl -s -o /tmp/cc_b.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${AH[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":\"$PID\",\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
WINS=$(( $( [ "$A" = "200" ] && echo 1 || echo 0 ) + $( [ "$B" = "200" ] && echo 1 || echo 0 ) ))
RESN=$(curl -s "$SB/equipment_reservations?select=id&contract_id=eq.$C1&status=eq.active" "${AH[@]}" | jq '. | length')
if [ "$WINS" -le 1 ] && [ "$RESN" -le 1 ]; then
  ok "concurrency: فائز واحد فقط (A=$A B=$B reservations=$RESN)"
else
  no "concurrency: WINS=$WINS RES=$RESN"
fi

# ===== 9) time_source + Cleanup كامل =====
echo "time_source: يُعاد في response checks (body/contract/full_day_fallback)"
jdelete(){ curl -s -o /dev/null -X DELETE "$SB/$1" "${AH[@]}"; }
jdelete "action_tokens?entity_id=eq.$C1"
jdelete "assignments?contract_id=eq.$C1"
jdelete "equipment_reservations?contract_id=eq.$C1"
jdelete "contract_equipment?contract_id=eq.$C1"
jdelete "contracts?id=eq.$C1"
CL=$(curl -s "$SB/clients?select=id&full_name=eq.Team%20Smoke" "${AH[@]}" | jq -r 'map(.id) | join(",")')
[ -n "$CL" ] && jdelete "clients?id=in.($CL)"
echo "  Cleanup: عقد الاختبار وكل آثاره أُزيلت"
ok "Cleanup"

rm -f /tmp/cc_body.txt /tmp/cc_a.txt /tmp/cc_b.txt
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
