#!/usr/bin/env bash
# =====================================================
# diag-payment-approve.sh — DIAGNOSTIC ONLY (لا إصلاح)
# READ-ONLY على Production ما عدا: عقد اختبار واحد مستقل يُحذف بأمان.
# لا يحذف أي payments إطلاقًا. لا يطبع المفتاح.
# يطبع: preconditions + خطأ RPC الحقيقي (code/message/details/hint)
#       + أعمدة payments من OpenAPI + باراميترات RPC كما يراها PostgREST.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
TS=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)
RAW(){ curl -s "$@"; }

echo "===== [A] payments schema كما يعرضها PostgREST (service_role OpenAPI) ====="
RAW "$SB/" "${H[@]}" -o /tmp/pa_diag_openapi.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/pa_diag_openapi.json'))
p = d.get('definitions', {}).get('payments')
if not p:
    print("payments: NOT IN OPENAPI (بدون GRANT لـ service_role؟)")
else:
    req = p.get('required', [])
    for col, spec in p.get('properties', {}).items():
        dflt = spec.get('default', spec.get('x-default', ''))
        print(f"  {col}{'*' if col in req else ''}: {spec.get('format') or spec.get('type')} default={dflt!r}")
path = d.get('paths', {}).get('/rpc/approve_payment_atomic')
print("== RPC /rpc/approve_payment_atomic (PostgREST cache) ==")
if not path:
    print("  NOT EXPOSED حتى لـ service_role — إما GRANT ناقص أو عدم تطابق باراميترات")
else:
    post = path.get('post', {})
    params = post.get('parameters', [])
    names = [x.get('name') for x in params if isinstance(x, dict)]
    print("  exposed: YES")
    print("  params:", names)
PY

echo
echo "===== [B] عقد اختبار مستقل (submit_lead) ====="
CID=$(jq -n --arg d "$TOMORROW" \
  '{p_full_name:"Pay Diag", p_phone:"0550000104", p_email:"pay-diag-'"$TS"'@test.local",
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | RAW -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
echo "contract_id = $CID"
if [ -z "$CID" ] || [ ${#CID} -lt 32 ]; then echo "FAIL: فشل إنشاء العقد"; exit 1; fi

echo
echo "===== [C] Preconditions ====="
echo "-- الصف الخام (إن كان object فهو خطأ PostgREST — دليل إضافي):"
RAW "$SB/payments?contract_id=eq.$CID" "${H[@]}"; echo
PCOUNT=$(RAW "$SB/payments?contract_id=eq.$CID" "${H[@]}" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print("ARRAY_OK count="+str(len(d)) if isinstance(d,list) else "ERROR_OBJECT keys="+str(len(d))+": "+json.dumps(d)[:300])')
echo "payments probe => $PCOUNT"
RAW "$SB/contracts?select=id,status,total_amount,deposit_review_status,contract_number&id=eq.$CID" "${H[@]}"; echo

echo
echo "===== [D] استدعاء RPC مباشرة بـ service_role (deposit=500، reference فريد) ====="
HTTP=$(curl -s -o /tmp/pa_diag_rpc.txt -w "%{http_code}" -X POST "$SB/rpc/approve_payment_atomic" "${H[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"p_contract_id\":\"$CID\",\"p_amount\":500,\"p_kind\":\"deposit\",\"p_payment_reference\":\"DIAG-$TS\"}")
echo "DIRECT_RPC_HTTP = $HTTP"
echo "-- body:"
python3 -m json.tool /tmp/pa_diag_rpc.txt 2>/dev/null || cat /tmp/pa_diag_rpc.txt
echo
python3 - <<'PY'
import json
try:
    d = json.load(open('/tmp/pa_diag_rpc.txt'))
except Exception as e:
    d = {"parse_error": str(e)}
if isinstance(d, list) and d:
    print("RPC_RESULT =", json.dumps(d[0], ensure_ascii=False))
    print("=> نجح الـRPC (سيُسجَّل payment على عقد DIAG — لن يُحذف، راجع القرار أدناه)")
else:
    print("DIRECT_RPC_PG_CODE    =", d.get('code',''))
    print("DIRECT_RPC_MESSAGE    =", d.get('message',''))
    print("DIRECT_RPC_DETAILS    =", d.get('details',''))
    print("DIRECT_RPC_HINT       =", d.get('hint',''))
PY

echo
echo "===== [E] Cleanup (لا حذف payments) ====="
PAYS=$(RAW "$SB/payments?contract_id=eq.$CID" "${H[@]}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else -1)')
if [ "$PAYS" = "0" ]; then
  CLID=$(RAW "$SB/contracts?select=client_id&id=eq.$CID" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["client_id"])')
  RAW -X DELETE "$SB/contracts?id=eq.$CID" "${H[@]}" > /dev/null
  RAW -X DELETE "$SB/clients?id=eq.$CLID" "${H[@]}" > /dev/null
  echo "حُذف عقد التشخيص وعميله (بلا أي payments)"
else
  echo "PAYS=$PAYS على عقد التشخيص ($CID) — لم يُحذف شيء. قرار الحذف لك."
fi
unset KEY
echo "===== DIAG DONE ====="
