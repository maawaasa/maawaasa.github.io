#!/usr/bin/env bash
# =====================================================
# smoke-payment-approve.sh — 13 isolated tests (v2 — Array-safe counters)
# المفتاح يُطلب بلا echo ولا يُخزن ولا يُطبع.
# كل test بعقد جديد مستقل وreference فريد. Cleanup كامل.
# عدادات payments: تتحقق أن REST response هو Array صالح قبل count —
# لا تعود مفتاحًا من error object أبدًا (إصلاح pays=4).
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
AU="$BASE/auth/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
ANON=$(grep -o "SUPABASE_ANON_KEY = '[^']*'" assets/js/supabase-config.js | cut -d"'" -f2)

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
call(){ curl -s -o /tmp/pa_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/payment-approve" \
  -H "Content-Type: application/json" "$@"; }
err(){ python3 -c 'import json;d=json.load(open("/tmp/pa_body.txt"));print(d.get("error",""))' 2>/dev/null; }
jget(){ python3 -c "import json;d=json.load(open('/tmp/pa_body.txt'));print(d.get('$1',''))" 2>/dev/null; }
fnum(){ python3 -c "import json;d=json.load(open('/tmp/pa_body.txt'));print(abs(float(d.get('paid_total',-1))-$1)<0.01)" 2>/dev/null; }
# dbcount: Array صالح ⇒ العدد · أي شيء آخر (خطأ PostgREST) ⇒ ERR:+رسالة (لا رقم زائف)
dbcount(){ curl -s "$SB/$1" "${H[@]}" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print(len(d) if isinstance(d,list) else "ERR:"+json.dumps(d)[:200])'; }
q(){ curl -s "$SB/$1" "${H[@]}"; }

TS=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

mk_user(){ curl -s -X POST "$AU/admin/users" "${H[@]}" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\",\"email_confirm\":true}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null; }
del_user(){ [ -n "$1" ] && curl -s -o /dev/null -X DELETE "$AU/admin/users/$1" "${H[@]}"; return 0; }
login(){ curl -s -X POST "$AU/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null; }
mk_contract(){ jq -n --arg n "$1" --arg e "$2" --arg d "$TOMORROW" \
    '{p_full_name:$n, p_phone:"0550000105", p_email:$e, p_service_type:"تصوير HDR",
      p_total:2000, p_property_type:"apartment", p_shoot_date:$d,
      p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""'; }
cleanup_contract(){ local cid="$1"
  [ -z "$cid" ] && return 0
  local clid=$(q "contracts?select=client_id&id=eq.$cid" | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r[0]["client_id"] if r else "")' 2>/dev/null)
  curl -s -o /dev/null -X DELETE "$SB/payments?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$cid" "${H[@]}"
  [ -n "$clid" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$clid" "${H[@]}"
  return 0
}
cstatus(){ q "contracts?select=status&id=eq.$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["status"])'; }

echo "===== payment-approve isolated smoke v2 (13) ====="

# ---------- 1) anon (بلا Bearer) ⇒ 401 ----------
c=$(curl -s -o /tmp/pa_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/payment-approve" \
  -H "Content-Type: application/json" -H "apikey: $ANON" -d '{}')
if [ "$c" = "401" ]; then ok "1) anon ⇒ 401"; else no "1) anon: HTTP $c"; fi

# ---------- 2) authenticated non-team ⇒ 403 ----------
NT_EMAIL="pay-nt-$TS@test.local"; NT_PASS="Nt-${TS}-Zq7!"
NT_UID=$(mk_user "$NT_EMAIL" "$NT_PASS"); NT_JWT=$(login "$NT_EMAIL" "$NT_PASS")
c=$(call -H "apikey: $ANON" -H "Authorization: Bearer $NT_JWT" -d '{"contract_id":"00000000-0000-0000-0000-000000000000"}')
if [ "$c" = "403" ] && [ "$(err)" = "forbidden_not_team_member" ]; then ok "2) non-team ⇒ 403"; else no "2) non-team: HTTP $c err=$(err)"; fi
del_user "$NT_UID"

# ---------- 3) team member ⇒ يصل المنطق ----------
TM_EMAIL="pay-tm-$TS@test.local"; TM_PASS="Tm-${TS}-Zq7!"
TM_UID=$(mk_user "$TM_EMAIL" "$TM_PASS")
[ -n "$TM_UID" ] && curl -s -o /dev/null -X POST "$SB/employees" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"auth_user_id\":\"$TM_UID\",\"name\":\"Pay Smoke TM\",\"role\":\"admin\",\"is_active\":true}"
TM_JWT=$(login "$TM_EMAIL" "$TM_PASS")
c=$(call -H "apikey: $ANON" -H "Authorization: Bearer $TM_JWT" -d '{"contract_id":"00000000-0000-0000-0000-000000000000"}')
if [ "$c" = "404" ] && [ "$(err)" = "contract_not_found" ]; then ok "3) team ⇒ يصل المنطق (404)"; else no "3) team: HTTP $c err=$(err)"; fi
[ -n "$TM_UID" ] && curl -s -o /dev/null -X DELETE "$SB/employees?auth_user_id=eq.$TM_UID" "${H[@]}"
del_user "$TM_UID"

# ---------- 4) correction: before/after بلا زيادة + token واحد ----------
CID=$(mk_contract "Pay Smoke C4" "pay-c4-$TS@test.local")
if [ -n "$CID" ] && [ ${#CID} -ge 32 ]; then
  PAYS_BEFORE=$(dbcount "payments?contract_id=eq.$CID")
  curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CID" "${H[@]}" -H "Content-Type: application/json" \
    -d '{"deposit_review_status":"receipt_under_review"}'
  c=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"correction\"}")
  PAYS_AFTER=$(dbcount "payments?contract_id=eq.$CID")
  TOKENS=$(dbcount "action_tokens?entity_id=eq.$CID&purpose=eq.deposit_receipt")
  ST=$(q "contracts?select=status,deposit_review_status&id=eq.$CID" | python3 -c 'import sys,json;r=json.load(sys.stdin)[0];print(r["status"],r["deposit_review_status"])')
  if [ "$c" = "200" ] && [ "$(jget state)" = "correction_requested" ] \
     && [ "$PAYS_BEFORE" = "0" ] && [ "$PAYS_AFTER" = "0" ] \
     && [ "$TOKENS" = "1" ] && [ "$ST" = "new correction_requested" ]; then
    ok "4) correction ⇒ correction_requested + token=1 + payments before/after=0/0 (لا زيادة)"
  else
    no "4) correction: HTTP $c state=$(jget state) before=$PAYS_BEFORE after=$PAYS_AFTER tokens=$TOKENS st=[$ST]"
  fi
else no "4) فشل إنشاء العقد: [$CID]"; fi
cleanup_contract "$CID"

# ---------- 5) deposit < 25% ⇒ payment_recorded ولا deposit_paid ----------
CID=$(mk_contract "Pay Smoke C5" "pay-c5-$TS@test.local")
c=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":400,\"payment_reference\":\"REF-C5-$TS\"}")
PAYS=$(dbcount "payments?contract_id=eq.$CID")
CST=$(cstatus "$CID")
if [ "$c" = "200" ] && [ "$(jget state)" = "payment_recorded" ] && [ "$(fnum 400)" = "True" ] \
   && [ "$PAYS" = "1" ] && [ "$CST" != "deposit_paid" ] && [ "$CST" = "new" ]; then
  ok "5) deposit 20% ⇒ payment_recorded + payment=1 + العقد لم يصبح deposit_paid"
else no "5): HTTP $c state=$(jget state) pays=$PAYS db=[$CST]"; fi
cleanup_contract "$CID"

# ---------- 6) cumulative ≥25% ⇒ deposit_paid ----------
CID=$(mk_contract "Pay Smoke C6" "pay-c6-$TS@test.local")
c1=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":300,\"payment_reference\":\"REF-C6A-$TS\"}")
S1=$(jget state)
c2=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":300,\"payment_reference\":\"REF-C6B-$TS\"}")
S2=$(jget state)
PAYS=$(dbcount "payments?contract_id=eq.$CID")
CST=$(cstatus "$CID")
if [ "$c1" = "200" ] && [ "$S1" = "payment_recorded" ] && [ "$c2" = "200" ] && [ "$S2" = "deposit_paid" ] \
   && [ "$(fnum 600)" = "True" ] && [ "$PAYS" = "2" ] && [ "$CST" = "deposit_paid" ]; then
  ok "6) cumulative 30% ⇒ payment_recorded ثم deposit_paid"
else no "6): c1=$c1/$S1 c2=$c2/$S2 pays=$PAYS db=[$CST]"; fi
cleanup_contract "$CID"

# ---------- 7) 100% upfront ⇒ fully_paid ----------
CID=$(mk_contract "Pay Smoke C7" "pay-c7-$TS@test.local")
c=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":2000,\"payment_reference\":\"REF-C7-$TS\"}")
CST=$(cstatus "$CID")
if [ "$c" = "200" ] && [ "$(jget state)" = "fully_paid" ] && [ "$CST" = "fully_paid" ]; then
  ok "7) 100% upfront ⇒ fully_paid"
else no "7): HTTP $c state=$(jget state) db=[$CST]"; fi
cleanup_contract "$CID"

# ---------- 8) balance غير كامل ⇒ لا fully_paid ----------
CID=$(mk_contract "Pay Smoke C8" "pay-c8-$TS@test.local")
call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":500}" > /dev/null
c=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"balance\",\"amount\":1000,\"payment_reference\":\"REF-C8-$TS\"}")
CST=$(cstatus "$CID")
if [ "$c" = "200" ] && [ "$(jget state)" = "payment_recorded" ] && [ "$(fnum 1500)" = "True" ] \
   && [ "$CST" != "fully_paid" ] && [ "$CST" = "deposit_paid" ]; then
  ok "8) balance جزئي ⇒ payment_recorded ولا fully_paid"
else no "8): HTTP $c state=$(jget state) db=[$CST]"; fi
cleanup_contract "$CID"

# ---------- 9) balance يكمل الإجمالي ⇒ fully_paid ----------
CID=$(mk_contract "Pay Smoke C9" "pay-c9-$TS@test.local")
call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":500}" > /dev/null
c=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"balance\",\"amount\":1500,\"payment_reference\":\"REF-C9-$TS\"}")
CST=$(cstatus "$CID")
if [ "$c" = "200" ] && [ "$(jget state)" = "fully_paid" ] && [ "$(fnum 2000)" = "True" ] && [ "$CST" = "fully_paid" ]; then
  ok "9) balance مكمّل ⇒ fully_paid"
else no "9): HTTP $c state=$(jget state) db=[$CST]"; fi
cleanup_contract "$CID"

# ---------- 10) overpayment ⇒ 409 amount_exceeds_total ----------
CID=$(mk_contract "Pay Smoke C10" "pay-c10-$TS@test.local")
c=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":2500,\"payment_reference\":\"REF-C10-$TS\"}")
PAYS=$(dbcount "payments?contract_id=eq.$CID")
if [ "$c" = "409" ] && [ "$(err)" = "amount_exceeds_total" ] && [ "$PAYS" = "0" ]; then
  ok "10) overpayment ⇒ 409 + Rollback (payments=0)"
else no "10): HTTP $c err=$(err) pays=$PAYS"; fi
cleanup_contract "$CID"

# ---------- 11) duplicate reference ⇒ رفض ولا duplicate payment ----------
# fixture: 400 < 25% ⇒ أول دفعة تبقي العقد new كي يصل الطلب الثاني لفحص duplicate في 017
# (500 = 25% بالضبط كان يقلب الحالة deposit_paid ⇒ Edge يرفض outdated_state مبكرًا)
CID=$(mk_contract "Pay Smoke C11" "pay-c11-$TS@test.local")
DUP_FIRST_HTTP=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":400,\"payment_reference\":\"REF-DUP-$TS\"}")
DUP_FIRST_ERR=$(jget state)
DUP_STATUS_AFTER_FIRST=$(cstatus "$CID")
DUP_SECOND_HTTP=$(call -H "Authorization: Bearer $KEY" -d "{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":400,\"payment_reference\":\"REF-DUP-$TS\"}")
DUP_SECOND_ERR=$(err)
DUP_SECOND_BODY=$(cat /tmp/pa_body.txt)
DUP_PAYMENTS_COUNT=$(dbcount "payments?contract_id=eq.$CID")
echo "  DUP_FIRST_HTTP=$DUP_FIRST_HTTP DUP_FIRST_ERR=$DUP_FIRST_ERR DUP_STATUS_AFTER_FIRST=$DUP_STATUS_AFTER_FIRST"
echo "  DUP_SECOND_HTTP=$DUP_SECOND_HTTP DUP_SECOND_ERR=$DUP_SECOND_ERR DUP_PAYMENTS_COUNT=$DUP_PAYMENTS_COUNT"
echo "  DUP_SECOND_BODY=$DUP_SECOND_BODY"
if [ "$DUP_FIRST_HTTP" = "200" ] && [ "$DUP_FIRST_ERR" = "payment_recorded" ] \
   && [ "$DUP_STATUS_AFTER_FIRST" = "new" ] \
   && [ "$DUP_SECOND_HTTP" = "409" ] && [ "$DUP_SECOND_ERR" = "duplicate_reference" ] \
   && [ "$DUP_PAYMENTS_COUNT" = "1" ]; then
  ok "11) duplicate reference ⇒ 409 duplicate_reference + دفعة واحدة فقط (وصل فحص 017)"
else no "11): first=$DUP_FIRST_HTTP/$DUP_FIRST_ERR st=$DUP_STATUS_AFTER_FIRST second=$DUP_SECOND_HTTP/$DUP_SECOND_ERR pays=$DUP_PAYMENTS_COUNT"; fi
cleanup_contract "$CID"

# ---------- 12) concurrency ⇒ فائز واحد، لا overpayment ولا duplicate ----------
CID=$(mk_contract "Pay Smoke C12" "pay-c12-$TS@test.local")
D1="{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":1000,\"payment_reference\":\"REF-R1-$TS\"}"
D2="{\"contract_id\":\"$CID\",\"kind\":\"deposit\",\"amount\":1000,\"payment_reference\":\"REF-R2-$TS\"}"
( curl -s -o /tmp/pa_r1.txt -w "%{http_code}" -X POST "$BASE/functions/v1/payment-approve" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$D1" > /tmp/pa_r1c.txt ) &
( curl -s -o /tmp/pa_r2.txt -w "%{http_code}" -X POST "$BASE/functions/v1/payment-approve" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$D2" > /tmp/pa_r2c.txt ) &
wait
R1=$(cat /tmp/pa_r1c.txt); R2=$(cat /tmp/pa_r2c.txt)
WINS=$(printf '%s\n%s' "$R1" "$R2" | grep -c '^200$')
BAD=$(grep -l -E 'amount_exceeds_total|duplicate_reference' /tmp/pa_r1.txt /tmp/pa_r2.txt 2>/dev/null | wc -l | tr -d ' ')
PAYS=$(dbcount "payments?contract_id=eq.$CID")
CST=$(cstatus "$CID")
if [ "$WINS" = "1" ] && [ "$BAD" = "0" ] && [ "$PAYS" = "1" ] && [ "$CST" = "deposit_paid" ]; then
  ok "12) concurrency ⇒ فائز واحد (r1=$R1 r2=$R2) بلا overpayment/duplicate"
else no "12): r1=$R1 r2=$R2 bad=$BAD pays=$PAYS db=[$CST]"; fi
cleanup_contract "$CID"

# ---------- 13) direct RPC: anon/auth blocked + service_role allowed ----------
CID=$(mk_contract "Pay Smoke C13" "pay-c13-$TS@test.local")
ca=$(curl -s -o /tmp/pa_body.txt -w "%{http_code}" -X POST "$SB/rpc/approve_payment_atomic" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
  -d "{\"p_contract_id\":\"$CID\",\"p_amount\":500,\"p_kind\":\"deposit\"}")
RP_EMAIL="pay-rpc-$TS@test.local"; RP_PASS="Rp-${TS}-Zq7!"
NT_UID=$(mk_user "$RP_EMAIL" "$RP_PASS"); NT_JWT=$(login "$RP_EMAIL" "$RP_PASS")
cb=$(curl -s -o /tmp/pa_body2.txt -w "%{http_code}" -X POST "$SB/rpc/approve_payment_atomic" \
  -H "apikey: $ANON" -H "Authorization: Bearer $NT_JWT" -H "Content-Type: application/json" \
  -d "{\"p_contract_id\":\"$CID\",\"p_amount\":500,\"p_kind\":\"deposit\"}")
del_user "$NT_UID"
cs=$(curl -s -o /tmp/pa_body3.txt -w "%{http_code}" -X POST "$SB/rpc/approve_payment_atomic" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"p_contract_id\":\"$CID\",\"p_amount\":500,\"p_kind\":\"deposit\",\"p_payment_reference\":\"REF-RPC-$TS\"}")
PAYS=$(dbcount "payments?contract_id=eq.$CID")
if [ "$ca" != "200" ] && [ "$cb" != "200" ] && [ "$cs" = "200" ] && [ "$PAYS" = "1" ]; then
  ok "13) direct RPC: anon=$ca blocked · auth=$cb blocked · service_role=200 + payment=1"
else no "13): anon=$ca auth=$cb service=$cs pays=$PAYS"; fi
cleanup_contract "$CID"

rm -f /tmp/pa_body.txt /tmp/pa_body2.txt /tmp/pa_body3.txt /tmp/pa_r1.txt /tmp/pa_r2.txt /tmp/pa_r1c.txt /tmp/pa_r2c.txt
unset KEY NT_JWT TM_JWT
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
