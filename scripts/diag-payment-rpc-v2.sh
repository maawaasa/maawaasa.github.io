#!/usr/bin/env bash
# =====================================================
# diag-payment-rpc-v2.sh — DIAGNOSTIC ONE-SHOT (لا إصلاح، لا deploy)
# 1) عقد جديد total=2000 status=new payments=0
# 2) استدعاء مباشر لـ approve_payment_atomic بـ service_role (500، ref فريد)
# 3) RAW response كامل + PG code/message/details/hint
# 4) بعد الفشل: status + deposit_review_status + payments count (لنفس العقد)
# 5) تعريف activity_log الفعلي من Production (OpenAPI + error-probe)
# 6) إعادة إنتاج fixture اختباري 8/9 وطباعة bodies فقط
# لا يحذف payments إلا لعقود الاختبار نفسها (cleanup).
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
ANON=$(grep -o "SUPABASE_ANON_KEY = '[^']*'" assets/js/supabase-config.js | cut -d"'" -f2)
RAW(){ curl -s "$@"; }
TS=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

echo "===== [1] عقد اختبار جديد ====="
CID=$(jq -n --arg d "$TOMORROW" \
  '{p_full_name:"Pay Diag2", p_phone:"0550000106", p_email:"pay-diag2-'"$TS"'@test.local",
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | RAW -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
echo "contract_id = $CID"
[ -z "$CID" ] || [ ${#CID} -lt 32 ] && { echo "FAIL: فشل إنشاء العقد"; exit 1; }
echo "preconditions: status=$(RAW "$SB/contracts?select=status,total_amount&id=eq.$CID" "${H[@]}")"
echo "payments pre = $(RAW "$SB/payments?contract_id=eq.$CID" "${H[@]}")"

echo
echo "===== [2] DIRECT RPC (service_role · amount=500 · ref فريد) ====="
DIRECT_HTTP=$(curl -s -o /tmp/pd_rpc.txt -w "%{http_code}" -X POST "$SB/rpc/approve_payment_atomic" "${H[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"p_contract_id\":\"$CID\",\"p_amount\":500,\"p_kind\":\"deposit\",\"p_payment_reference\":\"DIAG2-$TS\"}")
echo "DIRECT_HTTP = $DIRECT_HTTP"
echo "DIRECT_BODY ="
python3 -m json.tool /tmp/pd_rpc.txt 2>/dev/null || cat /tmp/pd_rpc.txt
python3 - <<'PY'
import json
try: d = json.load(open('/tmp/pd_rpc.txt'))
except Exception as e: d = {"parse_error": str(e)}
if isinstance(d, list) and d:
    print("RPC_RESULT =", json.dumps(d[0], ensure_ascii=False))
else:
    print("PG_CODE    =", d.get('code',''))
    print("MESSAGE    =", d.get('message',''))
    print("DETAILS    =", d.get('details',''))
    print("HINT       =", d.get('hint',''))
PY

echo
echo "===== [3] حالة العقد بعد الفشل ====="
RAW "$SB/contracts?select=status,deposit_review_status&id=eq.$CID" "${H[@]}"; echo
echo "payments count (نفس العقد فقط) = $(RAW "$SB/payments?contract_id=eq.$CID" "${H[@]}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else "ERR:"+json.dumps(d)[:200])')"

echo
echo "===== [4] تعريف activity_log الفعلي من Production (OpenAPI service_role) ====="
RAW "$SB/" "${H[@]}" -o /tmp/pd_openapi.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/pd_openapi.json'))
defs = d.get('definitions', {})
a = defs.get('activity_log')
if not a:
    print("activity_log: NOT IN OPENAPI (الجدول غير موجود أو بلا GRANT لـ service_role)")
else:
    req = a.get('required', [])
    for col, spec in a.get('properties', {}).items():
        print(f"  {col}{'*' if col in req else ''}: {spec.get('format') or spec.get('type')}")
PY
echo "-- error-probe: هل أعمدة 017 موجودة؟ --"
echo -n "select=action,entity,details      ⇒ "; RAW "$SB/activity_log?select=action,entity,details&limit=1" "${H[@]}" | head -c 300; echo
echo -n "select=action,entity_type,details ⇒ "; RAW "$SB/activity_log?select=action,entity_type,details&limit=1" "${H[@]}" | head -c 300; echo

echo
echo "===== [5] إعادة إنتاج fixture اختبار 8 (deposit500 ⇒ balance1000) — bodies فقط ====="
echo "-- deposit 500 --"
curl -s -X POST "$BASE/functions/v1/payment-approve" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":500,\"payment_reference\":\"DIAG2-DEP-$TS\"}"; echo
echo "-- contract status الآن: $(RAW "$SB/contracts?select=status&id=eq.$CID" "${H[@]}")"
echo "-- balance 1000 --"
curl -s -X POST "$BASE/functions/v1/payment-approve" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CID\",\"kind\":\"balance\",\"amount\":1000,\"payment_reference\":\"DIAG2-BAL-$TS\"}"; echo

echo
echo "===== [6] Cleanup (عقد الاختبار فقط) ====="
PAYS=$(RAW "$SB/payments?contract_id=eq.$CID" "${H[@]}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else -1)')
CLID=$(RAW "$SB/contracts?select=client_id&id=eq.$CID" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["client_id"])')
[ "$PAYS" = "0" ] || RAW -X DELETE "$SB/payments?contract_id=eq.$CID" "${H[@]}" > /dev/null
RAW -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]}" > /dev/null
RAW -X DELETE "$SB/contracts?id=eq.$CID" "${H[@]}" > /dev/null
RAW -X DELETE "$SB/clients?id=eq.$CLID" "${H[@]}" > /dev/null
echo "cleanup done (payments_deleted_for_diag_contract=$PAYS)"
unset KEY
rm -f /tmp/pd_rpc.txt /tmp/pd_openapi.json
echo "===== DIAG DONE ====="
