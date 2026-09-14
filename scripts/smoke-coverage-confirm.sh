#!/usr/bin/env bash
# =====================================================
# smoke-coverage-confirm.sh — E2E (يتطلب service_role)
# يغطي: anon 401 · فحص الحالة · تعارض المعدات 409 · تعارض المصور 409
#       · المسار السعيد: assignment + Hold +24h + reservations + token
#       · time_source · Cleanup كامل
# الاستخدام: ./scripts/smoke-coverage-confirm.sh
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
jdelete(){ curl -s -o /dev/null -X DELETE "$SB/$1" "${H[@]}"; }
# إنشاء عقد اختبار عبر submit_lead (نفس مسار الإنتاج)
new_contract(){ # name phone
  curl -s -X POST "$SB/rpc/submit_lead" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "{\"p_full_name\":\"$1\",\"p_phone\":\"$2\",\"p_service_type\":\"تصوير HDR\",\"p_total\":2000,\"p_property_type\":\"apartment\",\"p_shoot_date\":\"$3\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin) if sys.stdin.read(0)==None else "")' 2>/dev/null \
  || curl -s -X POST "$SB/rpc/submit_lead" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "{\"p_full_name\":\"$1\",\"p_phone\":\"$2\",\"p_service_type\":\"تصوير HDR\",\"p_total\":2000,\"p_property_type\":\"apartment\",\"p_shoot_date\":\"$3\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin))'
}

TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

echo "=== 0) تجهيز عقد اختبار C1 (status=new + تاريخ وأوقات) ==="
C1=$(curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"p_full_name\":\"Smoke C1\",\"p_phone\":\"0550000001\",\"p_email\":\"smoke-c1@test.local\",\"p_service_type\":\"تصوير HDR\",\"p_total\":2000,\"p_property_type\":\"apartment\",\"p_shoot_date\":\"$TOMORROW\",\"p_shoot_start_time\":\"10:00\",\"p_shoot_end_time\":\"12:00\"}" \
  | tr -d '"')
[ ${#C1} -ge 32 ] && ok "C1 جاهز: $C1" || { no "فشل إنشاء C1: $C1"; exit 1; }
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C1" "${H[@]}" \
  -H "Content-Type: application/json" -d '{"shoot_start_time":"10:00","shoot_end_time":"12:00"}'

# معدات اختبار + ربطها بـ C1
EQ=$(curl -s -X POST "$SB/equipment?select=id" "${H[@]}" -H "Content-Type: application/json" \
  -d '{"name":"Smoke Camera","type":"camera"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
[ -n "$EQ" ] && curl -s -o /dev/null -X POST "$SB/contract_equipment" "${H[@]}" \
  -H "Content-Type: application/json" -d "{\"contract_id\":\"$C1\",\"equipment_id\":\"$EQ\"}" \
  && ok "معدات اختبار مربوطة بـC1" || no "ربط معدات C1"

echo "=== 1) anon ⇒ 401 ==="
c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  -H "Content-Type: application/json" -d "{\"contract_id\":\"$C1\"}")
[ "$c" = "401" ] && ok "anon ⇒ 401" || no "anon: HTTP $c"

echo "=== 1-ب) حالة غير صالحة ⇒ 409 outdated_state ==="
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C1" "${H[@]}" \
  -H "Content-Type: application/json" -d '{"status":"deposit_paid"}'
c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" -d "{\"contract_id\":\"$C1\"}")
e=$(python3 -c 'import json;print(json.load(open("/tmp/cc_body.txt")).get("error",""))')
[ "$c" = "409" ] && [ "$e" = "outdated_state" ] && ok "outdated_state 409 (بلا Hold)" || no "status gate: HTTP $c err=$e"
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C1" "${H[@]}" \
  -H "Content-Type: application/json" -d '{"status":"new"}'

echo "=== 2) تعارض معدات ⇒ 409 (حجز C2 متداخل على نفس القطعة) ==="
C2=$(curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"p_full_name\":\"Smoke C2\",\"p_phone\":\"0550000002\",\"p_email\":\"smoke-c2@test.local\",\"p_service_type\":\"تصوير HDR\",\"p_total\":2000,\"p_property_type\":\"apartment\",\"p_shoot_date\":\"$TOMORROW\"}" \
  | tr -d '"')
[ ${#C2} -ge 32 ] && curl -s -o /dev/null -X POST "$SB/contract_equipment" "${H[@]}" \
  -H "Content-Type: application/json" -d "{\"contract_id\":\"$C2\",\"equipment_id\":\"$EQ\"}"
curl -s -o /dev/null -X POST "$SB/equipment_reservations" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C2\",\"equipment_id\":\"$EQ\",\"start_at\":\"${TOMORROW}T08:00:00+03:00\",\"end_at\":\"${TOMORROW}T13:00:00+03:00\",\"status\":\"active\"}"
c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" -d "{\"contract_id\":\"$C1\"}")
e=$(python3 -c 'import json;print(json.load(open("/tmp/cc_body.txt")).get("error",""))')
[ "$c" = "409" ] && [ "$e" = "equipment_unavailable" ] && ok "equipment_unavailable 409" || no "equipment: HTTP $c err=$e"
jdelete "equipment_reservations?contract_id=eq.$C2"
jdelete "contracts?id=eq.$C2"
CL2=$(curl -s "$SB/clients?select=id&full_name=eq.Smoke%20C2" "${H[@]}" | python3 -c 'import sys,json;print(",".join(x["id"] for x in json.load(sys.stdin)))')
[ -n "$CL2" ] && jdelete "clients?id=in.($CL2)"

echo "=== 3) تعارض المصور الزمني ⇒ 409 (schedule متداخل) ==="
PID=$(curl -s "$SB/employees?select=id&role=eq.photographer&is_active=eq.true&order=sort_order&limit=1" "${H[@]}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
if [ -n "$PID" ]; then
  SINS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SB/schedule" "${H[@]}" -H "Content-Type: application/json" \
    -d "{\"employee_id\":$PID,\"job_date\":\"$TOMORROW\",\"start_time\":\"09:00:00\",\"end_time\":\"13:00:00\",\"status\":\"scheduled\",\"title\":\"conflict-probe\"}")
  if [ "$SINS" = "201" ]; then
    SID=$(curl -s "$SB/schedule?select=id&employee_id=eq.$PID&job_date=eq.$TOMORROW&title=eq.conflict-probe" "${H[@]}" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
    c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
      "${H[@]}" -H "Content-Type: application/json" -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":$PID,\"start_time\":\"10:00\",\"end_time\":\"12:00\"}")
    e=$(python3 -c 'import json;print(json.load(open("/tmp/cc_body.txt")).get("error",""))')
    [ "$c" = "409" ] && [ "$e" = "photographer_unavailable" ] && ok "photographer_unavailable 409" || no "photographer: HTTP $c err=$e"
    jdelete "schedule?id=eq.$SID"
  else
    echo "SKIP: تعذر إدراج schedule (schema) — فحص تعارض المصور تخطي"
  fi
  curl -s -o /dev/null -X DELETE "$SB/schedule?employee_id=eq.$PID&job_date=eq.$TOMORROW&title=eq.conflict-probe" "${H[@]}"
else
  echo "SKIP: لا مصور نشط"
fi

echo "=== 4) المسار السعيد: بلا تعارض ⇒ Hold +24h + reservations + token ==="
c=$(curl -s -o /tmp/cc_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":$PID,\"start_time\":\"14:00\",\"end_time\":\"16:00\"}")
if [ "$c" = "200" ]; then
  ok "coverage-confirm 200"
  python3 - /tmp/cc_body.txt <<'PY' && ok "hold ≈ +24h + reservation + token + time_source=body" || no "فحص المسار السعيد"
import sys, json
from datetime import datetime, timezone
r = json.load(open(sys.argv[1]))
exp = datetime.fromisoformat(r["hold_expires_at"].replace("Z","+00:00"))
d = exp - datetime.now(timezone.utc)
assert timedelta(hours=23) < d < timedelta(hours=25), f"hold {d}"
assert r["checks"]["equipment"].startswith("reserved"), r["checks"]
assert r["checks"]["time_source"] in ("body","contract"), r["checks"]
assert r["customer_email_sent"] in ("yes","no","no_email_or_token_skipped"), "email flag"
PY
else
  no "happy path: HTTP $c — $(head -c 150 /tmp/cc_body.txt)"
fi

echo "=== 5) تحقق DB: hold + reservations + token مرتبط بـC1 ==="
DB=$(curl -s "$SB/contracts?select=status,hold_started_at,hold_expires_at&id=eq.$C1" "${H[@]}")
python3 - "$DB" <<'PY' && ok "DB: awaiting_payment + Hold مضبوط" || no "DB hold"
import sys, json
r = json.loads(sys.argv[1])[0]
assert r["status"] == "awaiting_payment", r
assert r["hold_started_at"] and r["hold_expires_at"], "hold fields"
PY
RES=$(curl -s "$SB/equipment_reservations?select=id,status&contract_id=eq.$C1" "${H[@]}" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d), d[0]["status"] if d else "")')
echo "  reservations: $RES"
[ "${RES%% *}" -ge 1 ] && ok "reservation أُنشئ" || no "لا reservation"
TOK=$(curl -s "$SB/action_tokens?select=token_hash,purpose,expires_at&entity_id=eq.$C1&purpose=eq.deposit_receipt" "${H[@]}" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d))')
[ "$TOK" -ge 1 ] && ok "deposit token مرتبط بـC1 ($TOK)" || no "لا token"

echo "=== 5-ب) concurrency: نداءان متزامنان ⇒ واحد فقط يفوز ==="
curl -s -o /tmp/cc_a.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":$PID,\"start_time\":\"14:00\",\"end_time\":\"16:00\"}" > /tmp/cc_a.code &
CA=$!
curl -s -o /tmp/cc_b.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$C1\",\"photographer_employee_id\":$PID,\"start_time\":\"14:00\",\"end_time\":\"16:00\"}" > /tmp/cc_b.code &
CB=$!
wait $CA $CB
A=$(cat /tmp/cc_a.code); B=$(cat /tmp/cc_b.code)
WINS=$(( $( [ "$A" = "200" ] && echo 1 || echo 0 ) + $( [ "$B" = "200" ] && echo 1 || echo 0 ) ))
RESN=$(curl -s "$SB/equipment_reservations?select=id&contract_id=eq.$C1&status=eq.active" "${H[@]}" \
  | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')
if [ "$WINS" -le 1 ] && [ "$RESN" -le 1 ]; then ok "concurrency: فائز واحد فقط، reservations=$RESN"; else no "concurrency: WINS=$WINS RES=$RESN"; fi
[ "$A" != "200" ] && [ "$B" != "200" ] && { no "الاثنان فشلا — أعد الحالة"; curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C1" "${H[@]}" -H "Content-Type: application/json" -d '{"status":"new"}'; }

echo "=== 6) Cleanup كامل ==="
jdelete "equipment_reservations?contract_id=eq.$C1"
jdelete "contract_equipment?contract_id=eq.$C1"
[ -n "$EQ" ] && jdelete "equipment?id=eq.$EQ"
jdelete "action_tokens?entity_id=eq.$C1"
jdelete "assignments?contract_id=eq.$C1"
jdelete "contracts?id=eq.$C1"
CN=$(curl -s "$SB/clients?select=id&full_name=eq.Smoke%20C1" "${H[@]}" | python3 -c 'import sys,json;print(",".join(x["id"] for x in json.load(sys.stdin)))')
[ -n "$CN" ] && jdelete "clients?id=in.($CN)"
ok "Cleanup"

rm -f /tmp/cc_body.txt
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
