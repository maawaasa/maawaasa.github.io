#!/usr/bin/env bash
# =====================================================
# smoke-admin-approval-matrix.sh — مصفوفة اعتماد لوحة الملاك
# يحاكي بالضبط شكل الحمولات التي ترسلها admin.htmlapproveReceipt:
#   kind حسب حالة العقد (deposit: new/awaiting_payment · balance: deposit_paid/in_progress)
#   amount = قيمة يدخله المالك (وليس total×0.25) · مرجع RCP- ثابت من مسار الإيصال
# الحالات: 20% · 25% · 40% · 100% مقدمًا · تراكمي (20+20+رصيد 60) · overpayment
# كل حالة على عقد مستقل · تنظيف كامل · activity_log يبقى كسجل
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
AU="$BASE/auth/v1"
FN="$BASE/functions/v1"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
q(){ curl -s "$SB/$1" "${H[@]}"; }

TS=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

# فريق ديناميكي — نفس مسار اللوحة (JWT عضو فريق)
TM_EMAIL="adm-tm-$TS@test.local"; TM_PASS="Adm-${TS}-Zq7!"
TM_UID=$(curl -s -X POST "$AU/admin/users" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"email\":\"$TM_EMAIL\",\"password\":\"$TM_PASS\",\"email_confirm\":true}" | jq -r '.id // ""')
[ -n "$TM_UID" ] && curl -s -o /dev/null -X POST "$SB/employees" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"auth_user_id\":\"$TM_UID\",\"name\":\"Admin Matrix TM\",\"role\":\"admin\",\"is_active\":true}"
JWT=$(curl -s -X POST "$AU/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$TM_EMAIL\",\"password\":\"$TM_PASS\"}" | jq -r '.access_token // ""')
[ -n "$JWT" ] || { echo "FAIL: team login"; exit 1; }

# استدعاء مطابق للوحة: Bearer عضو الفريق + apikey anon
approve(){ # $1=contract $2=amount $3=kind $4=ref $5=out_file
  curl -s -o "$5" -w "%{http_code}" -X POST "$FN/payment-approve" \
    -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
    -d "{\"contract_id\":\"$1\",\"amount\":$2,\"kind\":\"$3\",\"payment_reference\":\"$4\"}"
}
mk_contract(){ jq -n --arg n "$1" --arg d "$TOMORROW" \
    '{p_full_name:$n, p_phone:"0550000105", p_email:"adm-matrix-'$TS'@test.local", p_service_type:"تصوير HDR",
      p_total:2000, p_property_type:"apartment", p_property_location:"الرياض", p_shoot_date:$d,
      p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- | tr -d '"'; }
status(){ q "contracts?select=status&id=eq.$1" | jq -r '.[0].status // "missing"'; }
paid(){ q "payments?select=amount&contract_id=eq.$1" | jq '[.[].amount | tonumber] | add // 0' | awk '{printf "%d", $1}'; }
cleanup(){ local cid="$1"
  local clid=$(q "contracts?select=client_id&id=eq.$cid" | jq -r '.[0].client_id // ""')
  curl -s -o /dev/null -X DELETE "$SB/payments?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$cid" "${H[@]}"
  [ -n "$clid" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$clid" "${H[@]}"
  return 0
}
ref(){ echo "RCP-test-$1-$RANDOM$RANDOM"; }

echo "===== admin approval matrix (UI-shaped payloads) — T=2000 ====="

# ---------- 1) إيصال 20% → payment_recorded ولا Confirmed ----------
CID=$(mk_contract "Adm 20pct")
C=$(approve "$CID" 400 deposit "$(ref a20)" /tmp/am1.json)
ST=$(status "$CID"); PD=$(paid "$CID")
[ "$C" = "200" ] && [ "$(jq -r '.state' /tmp/am1.json)" = "payment_recorded" ] \
  && [ "$ST" != "deposit_paid" ] && [ "$ST" = "new" ] && [ "$PD" = "400" ] \
  && ok "1) 20% (400) → payment_recorded + status=new + paid=400" \
  || no "1) 20%: HTTP=$C state=$(jq -r '.state//.error' /tmp/am1.json) status=$ST paid=$PD"
cleanup "$CID"

# ---------- 2) إيصال 25% → deposit_paid ----------
CID=$(mk_contract "Adm 25pct")
C=$(approve "$CID" 500 deposit "$(ref a25)" /tmp/am2.json)
ST=$(status "$CID")
[ "$C" = "200" ] && [ "$ST" = "deposit_paid" ] && [ "$(paid "$CID")" = "500" ] \
  && ok "2) 25% (500) → deposit_paid" || no "2) 25%: HTTP=$C status=$ST"
cleanup "$CID"

# ---------- 3) إيصال 40% → deposit_paid والدفتر يسجل 800 فعليًا ----------
CID=$(mk_contract "Adm 40pct")
C=$(approve "$CID" 800 deposit "$(ref a40)" /tmp/am3.json)
ST=$(status "$CID")
[ "$C" = "200" ] && [ "$ST" = "deposit_paid" ] && [ "$(paid "$CID")" = "800" ] \
  && ok "3) 40% (800) → deposit_paid + الدفتر الفعلي 800 (لا فقدان 15%)" \
  || no "3) 40%: HTTP=$C status=$ST paid=$(paid "$CID")"
cleanup "$CID"

# ---------- 4) إيصال 100% مقدمًا → fully_paid ----------
CID=$(mk_contract "Adm 100pct")
C=$(approve "$CID" 2000 deposit "$(ref a100)" /tmp/am4.json)
ST=$(status "$CID")
[ "$C" = "200" ] && [ "$ST" = "fully_paid" ] && [ "$(paid "$CID")" = "2000" ] \
  && ok "4) 100% (2000) → fully_paid فورًا" || no "4) 100%: HTTP=$C status=$ST"
cleanup "$CID"

# ---------- 5) تراكمي: 20% + 20% (deposit) ثم رصيد 60% (balance) → fully_paid ----------
CID=$(mk_contract "Adm cumulative")
C1=$(approve "$CID" 400 deposit "$(ref c1)" /tmp/am5a.json)
S1=$(status "$CID")
C2=$(approve "$CID" 400 deposit "$(ref c2)" /tmp/am5b.json)
S2=$(status "$CID")
C3=$(approve "$CID" 1200 balance "$(ref c3)" /tmp/am5c.json)
S3=$(status "$CID")
[ "$C1" = "200" ] && [ "$S1" = "new" ] \
  && [ "$C2" = "200" ] && [ "$S2" = "deposit_paid" ] \
  && [ "$C3" = "200" ] && [ "$S3" = "fully_paid" ] && [ "$(paid "$CID")" = "2000" ] \
  && ok "5) تراكمي 400+400(deposit)→deposit_paid ثم 1200(balance)→fully_paid + paid=2000" \
  || no "5) تراكمي: c1=$C1/$S1 c2=$C2/$S2 c3=$C3/$S3 paid=$(paid "$CID")"
cleanup "$CID"

# ---------- 6) overpayment → 409 + Rollback (بلا أي دفعة) ----------
CID=$(mk_contract "Adm overpay")
C=$(approve "$CID" 2500 deposit "$(ref ov1)" /tmp/am6.json)
ST=$(status "$CID"); PD=$(paid "$CID")
[ "$C" = "409" ] && [ "$ST" != "fully_paid" ] && [ "$PD" = "0" ] \
  && ok "6) overpayment 2500 → 409 + Rollback + paid=0" \
  || no "6) overpayment: HTTP=$C status=$ST paid=$PD"
cleanup "$CID"

# ---------- تنظيف الفريق ----------
curl -s -o /dev/null -X DELETE "$SB/employees?auth_user_id=eq.$TM_UID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$AU/admin/users/$TM_UID" "${H[@]}"

echo ""
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
