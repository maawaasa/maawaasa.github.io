#!/usr/bin/env bash
# =====================================================
# smoke-test11-only.sh — Test 11 فقط (duplicate reference)
# HARNESS FIX: أول دفعة 400 < 25% ⇒ العقد يبقى new ⇒ الطلب الثاني
# يصل لفحص duplicate_reference داخل approve_payment_atomic (017)
# لا يلمس أي كود إنتاجي. Cleanup كامل.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
TS=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)
call(){ curl -s -o /tmp/pa11_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/payment-approve" \
  -H "Content-Type: application/json" "$@"; }
jget(){ python3 -c "import json;d=json.load(open('/tmp/pa11_body.txt'));print(d.get('$1',''))" 2>/dev/null; }
err(){ python3 -c 'import json;d=json.load(open("/tmp/pa11_body.txt"));print(d.get("error",""))' 2>/dev/null; }
dbcount(){ curl -s "$SB/$1" "${H[@]}" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print(len(d) if isinstance(d,list) else "ERR:"+json.dumps(d)[:200])'; }
q(){ curl -s "$SB/$1" "${H[@]}"; }
cstatus(){ q "contracts?select=status&id=eq.$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["status"])'; }

CID=$(jq -n --arg d "$TOMORROW" \
  '{p_full_name:"Pay Smoke T11", p_phone:"0550000107", p_email:"pay-t11-'"$TS"'@test.local",
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
[ -z "$CID" ] || [ ${#CID} -lt 32 ] && { echo "FAIL: فشل إنشاء العقد: [$CID]"; exit 1; }
echo "contract=$CID status=$(cstatus "$CID") total=2000"

DUP_FIRST_HTTP=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":400,\"payment_reference\":\"REF-DUP-$TS\"}")
DUP_FIRST_ERR=$(jget state)
DUP_STATUS_AFTER_FIRST=$(cstatus "$CID")
DUP_SECOND_HTTP=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":400,\"payment_reference\":\"REF-DUP-$TS\"}")
DUP_SECOND_ERR=$(err)
DUP_SECOND_BODY=$(cat /tmp/pa11_body.txt)
DUP_PAYMENTS_COUNT=$(dbcount "payments?contract_id=eq.$CID")

echo "DUP_FIRST_HTTP         = $DUP_FIRST_HTTP"
echo "DUP_FIRST_ERR          = $DUP_FIRST_ERR"
echo "DUP_STATUS_AFTER_FIRST = $DUP_STATUS_AFTER_FIRST"
echo "DUP_SECOND_HTTP        = $DUP_SECOND_HTTP"
echo "DUP_SECOND_BODY        = $DUP_SECOND_BODY"
echo "DUP_SECOND_ERR         = $DUP_SECOND_ERR"
echo "DUP_PAYMENTS_COUNT     = $DUP_PAYMENTS_COUNT"

if [ "$DUP_FIRST_HTTP" = "200" ] && [ "$DUP_FIRST_ERR" = "payment_recorded" ] \
   && [ "$DUP_STATUS_AFTER_FIRST" = "new" ] \
   && [ "$DUP_SECOND_HTTP" = "409" ] && [ "$DUP_SECOND_ERR" = "duplicate_reference" ] \
   && [ "$DUP_PAYMENTS_COUNT" = "1" ]; then
  echo "TEST_11 = PASS"
  RC=0
else
  echo "TEST_11 = FAIL"
  RC=1
fi

CLID=$(q "contracts?select=client_id&id=eq.$CID" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["client_id"])')
curl -s -o /dev/null -X DELETE "$SB/payments?contract_id=eq.$CID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$CID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$CLID" "${H[@]}"
echo "cleanup done"
rm -f /tmp/pa11_body.txt
unset KEY
exit $RC
