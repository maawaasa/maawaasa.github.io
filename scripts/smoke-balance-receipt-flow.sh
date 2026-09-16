#!/usr/bin/env bash
# =====================================================
# smoke-balance-receipt-flow.sh — تدفق إيصال الرصيد كاملًا (معزول)
# يغطي: deposit_paid+remaining → C-14+token · رابط صالح · رفع إيصال رصيد
#       · hold لا يتأثر · لا اعتماد تلقائي · رؤية الإدارة · اعتماد جزئي
#       · اعتماد كامل → fully_paid + C-17 · منع التكرار · رفض used/expired
# TEST_EMAIL = wfalfaifi@gmail.com (صندوق المالك) · تنظيف كل البيانات
# لا activity_log/email_log يُحذفان (سجل دائم)
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"; AU="$BASE/auth/v1"; FN="$BASE/functions/v1"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"
TEST_EMAIL="wfalfaifi@gmail.com"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
read -rsp "AUTOMATION_SECRET: " AUTOSEC; echo
[ -z "$KEY" ] || [ -z "$AUTOSEC" ] && { echo "المفتاحان مطلوبان"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
q(){ curl -s "$SB/$1" "${H[@]}"; }
TS=$(date +%s); TOMORROW=$(date -u -v+1d +%Y-%m-%d)

# شبكة تنظيف fail-closed: أي انهيار/متغير غير معرّف ينظّف آثار الاختبار
# activity_log وemail_log لا يُحذفان أبدًا (سجل دائم)
cleanup_fail(){
  [ -n "${CID:-}" ] || return 0
  curl -s -o /dev/null -X DELETE "$SB/payments?contract_id=eq.$CID" "${H[@]:-}"
  curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]:-}"
  curl -s -o /dev/null -X DELETE "$SB/assignments?contract_id=eq.$CID" "${H[@]:-}"
  curl -s -o /dev/null -X DELETE "$SB/equipment_reservations?contract_id=eq.$CID" "${H[@]:-}"
  curl -s -o /dev/null -X DELETE "$SB/contract_equipment?contract_id=eq.$CID" "${H[@]:-}"
  local cl=""
  cl=$(q "contracts?select=client_id&id=eq.$CID" 2>/dev/null | jq -r '.[0].client_id // ""' 2>/dev/null)
  [ -n "$cl" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$cl" "${H[@]:-}"
  curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$CID" "${H[@]:-}"
  if [ -n "${TM_UID:-}" ]; then
    curl -s -o /dev/null -X DELETE "$SB/employees?auth_user_id=eq.$TM_UID" "${H[@]:-}"
    curl -s -o /dev/null -X DELETE "$AU/admin/users/$TM_UID" "${H[@]:-}"
  fi
  echo "[trap] cleanup done"
}
trap cleanup_fail EXIT

# ===== تجهيز: فريق ديناميكي + عقد T=2000 + اعتماد عربون 25% =====
TM_EMAIL="bal-tm-$TS@test.local"; TM_PASS="Bal-${TS}-Zq7!"
TM_UID=$(curl -s -X POST "$AU/admin/users" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"email\":\"$TM_EMAIL\",\"password\":\"$TM_PASS\",\"email_confirm\":true}" | jq -r '.id // ""')
curl -s -o /dev/null -X POST "$SB/employees" "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"auth_user_id\":\"$TM_UID\",\"name\":\"Balance Flow TM\",\"role\":\"admin\",\"is_active\":true}"
JWT=$(curl -s -X POST "$AU/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$TM_EMAIL\",\"password\":\"$TM_PASS\"}" | jq -r '.access_token // ""')
[ -n "$JWT" ] || { echo "FAIL: team login"; exit 1; }

CID=$(jq -n --arg d "$TOMORROW" '{p_full_name:"[BALANCE FLOW TEST]",p_phone:"0550000999",p_email:"'"$TEST_EMAIL"'",p_service_type:"تصوير HDR",p_total:2000,p_property_type:"apartment",p_property_location:"الرياض",p_shoot_date:$d,p_shoot_start_time:"10:00",p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- | tr -d '"')
C=$(curl -s -o /tmp/bf_dep.json -w "%{http_code}" -X POST "$FN/payment-approve" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CID\",\"amount\":500,\"kind\":\"deposit\",\"payment_reference\":\"BAL-dep-$TS\"}")
[ "$C" = "200" ] && [ "$(q "contracts?select=status&id=eq.$CID" | jq -r '.[0].status')" = "deposit_paid" ] \
  && ok "تجهيز: عقد deposit_paid ومتبقٍ 1500" || { no "تجهيز الاعتماد فشل: $C"; exit 1; }

# ===== 1) الأتمتة → C-14 + token (TTL ≈72h) =====
EA1=$(curl -s -X POST "$FN/email-automation" -H "Authorization: Bearer $AUTOSEC" -H "Content-Type: application/json" -d '{}')
TOKS1=$(q "action_tokens?select=id,expires_at&entity_id=eq.$CID&purpose=eq.balance_receipt&used_at=is.null" | jq length)
C14_1=$(q "email_log?select=id&entity_id=eq.$CID&event_type=eq.C-14&status=eq.sent&recipient=eq.$TEST_EMAIL" | jq length)
EXPH=$(q "action_tokens?select=expires_at&entity_id=eq.$CID&purpose=eq.balance_receipt&used_at=is.null&order=created_at.desc&limit=1" | jq -r '.[0].expires_at // ""')
DIFF_H=$(python3 -c "
import sys,datetime
try:
    e=datetime.datetime.fromisoformat('$EXPH'.replace('Z','+00:00'))
    print(int((e-datetime.datetime.now(datetime.timezone.utc)).total_seconds()//3600))
except Exception: print(-999)")
BALSENT=$(echo "$EA1" | jq -r '.balance_c14_sent // 0')
if [ "$TOKS1" -ge 1 ] && [ "$C14_1" = "1" ] && [ "$BALSENT" = "1" ] && [ "$DIFF_H" -ge 71 ] && [ "$DIFF_H" -le 73 ]; then
  ok "C-14 أُرسل مرة واحدة (counter=1) + balance token واحد بـTTL≈72h (${DIFF_H}h)"
else
  no "C-14/token: toks=$TOKS1 c14=$C14_1 bal_sent=$BALSENT ttl=${DIFF_H}h — $EA1"
fi

# ===== 2) منع التكرار: تشغيل ثانٍ → لا token جديد ولا C-14 جديد =====
EA2=$(curl -s -X POST "$FN/email-automation" -H "Authorization: Bearer $AUTOSEC" -H "Content-Type: application/json" -d '{}')
TOKS2=$(q "action_tokens?select=id&entity_id=eq.$CID&purpose=eq.balance_receipt&used_at=is.null" | jq length)
C14_2=$(q "email_log?select=id&entity_id=eq.$CID&event_type=eq.C-14&status=eq.sent" | jq length)
SKIPTOK=$(echo "$EA2" | jq -r '.balance_c14_skipped_existing_token // 0')
[ "$TOKS2" = "$TOKS1" ] && [ "$C14_2" = "1" ] && [ "$SKIPTOK" = "1" ] \
  && ok "idempotency: نفس token ونفس C-14 + counter skipped_existing_token=1" \
  || no "تكرار: toks=$TOKS1→$TOKS2 c14=$C14_1→$C14_2 skip=$SKIPTOK"

# ===== 3) رابط صالح: إنشاء رمز خدمي (raw) ورفع إيصال رصيد حقيقي =====
RAW=$(curl -s -X POST "$FN/action-token-create" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"purpose":"balance_receipt","entity_id":"'"$CID"'","entity_type":"contract","ttl_hours":72}' | jq -r '.token // ""')
[ ${#RAW} -ge 32 ] && ok "action-token-create balance_receipt يعيد raw token (72h)" || no "raw token فشل"
PNG=$(python3 -c '
import zlib,struct,os,base64
w=h=64
def ch(t,d):
    c=t+d; return struct.pack(">I",len(d))+c+struct.pack(">I",zlib.crc32(c)&0xffffffff)
raw=b"".join(b"\x00"+os.urandom(w*3) for _ in range(h))
png=b"\x89PNG\r\n\x1a\n"+ch(b"IHDR",struct.pack(">IIBBBBB",w,h,8,2,0,0,0))+ch(b"IDAT",zlib.compress(raw,6))+ch(b"IEND",b"")
print("data:image/png;base64,"+base64.b64encode(png).decode())')
IMG=$(printf '%s' "$PNG" | jq -Rs .)
RU=$(jq -n --arg t "$RAW" --argjson img "$IMG" '{token:$t, image_data_url:$img}' \
  | curl -s -w "\n%{http_code}" -X POST "$FN/receipt-submit" -H "Content-Type: application/json" --data @-)
RUC=$(echo "$RU" | tail -1)
ST=$(q "contracts?select=status,deposit_review_status,hold_expires_at&id=eq.$CID" | jq -c '.[0]')
PAYS=$(q "payments?select=amount&contract_id=eq.$CID" | jq length)
[ "$RUC" = "200" ] && [ "$(echo "$ST" | jq -r .status)" = "deposit_paid" ] \
  && [ "$(echo "$ST" | jq -r .deposit_review_status)" = "receipt_under_review" ] \
  && [ "$(echo "$ST" | jq -r .hold_expires_at)" = "null" ] && [ "$PAYS" = "1" ] \
  && ok "رفع إيصال رصيد 200 + receipt_under_review + hold سليم + لا اعتماد تلقائي (payments=1)" \
  || no "رفع الرصيد: HTTP=$RUC state=$ST pays=$PAYS"

# ===== 4) الإدارة تراه (استعلام renderReceipts الحي) =====
SEEN=$(q "contracts?select=id&deposit_review_status=eq.receipt_under_review&id=eq.$CID" | jq length)
[ "$SEEN" = "1" ] && ok "admin sees balance receipt (نفس استعلام القسم)" || no "غير مرئي للإدارة"

# ===== 5) الرمز المستهلك يُرفض =====
RU2=$(jq -n --arg t "$RAW" --argjson img "$IMG" '{token:$t, image_data_url:$img}' \
  | curl -s -o /tmp/bf_used.json -w "%{http_code}" -X POST "$FN/receipt-submit" -H "Content-Type: application/json" --data @-)
ERR2=$(jq -r '.error // ""' /tmp/bf_used.json 2>/dev/null)
[ "$RU2" = "400" ] && [ "$ERR2" = "invalid_or_used_token" ] && ok "إعادة استخدام الرمز مرفوضة (used)" || no "used: $RU2/$ERR2"

# ===== 6) رمز منتهٍ يُرفض =====
RAW3=$(curl -s -X POST "$FN/action-token-create" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"purpose":"balance_receipt","entity_id":"'"$CID"'","entity_type":"contract","ttl_hours":72}' | jq -r '.token // ""')
H3=$(printf '%s' "$RAW3" | sha256sum | cut -c1-64)
curl -s -o /dev/null -X PATCH "$SB/action_tokens?token_hash=eq.$H3" "${H[@]}" -H "Content-Type: application/json" -d '{"expires_at":"2020-01-01T00:00:00Z"}'
RU4=$(jq -n --arg t "$RAW3" --argjson img "$IMG" '{token:$t, image_data_url:$img}' \
  | curl -s -o /tmp/bf_exp2.json -w "%{http_code}" -X POST "$FN/receipt-submit" -H "Content-Type: application/json" --data @-)
ERR4=$(jq -r '.error // ""' /tmp/bf_exp2.json 2>/dev/null)
[ "$RU4" = "400" ] && [ "$ERR4" = "invalid_or_used_token" ] && ok "رمز منتهٍ يُرفض (expired)" || no "expired: $RU4/$ERR4"

# ===== 7) اعتماد جزئي للرصيد (700) → payment_recorded ولا fully_paid =====
CA=$(curl -s -o /tmp/bf_p1.json -w "%{http_code}" -X POST "$FN/payment-approve" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CID\",\"amount\":700,\"kind\":\"balance\",\"payment_reference\":\"BAL-part-$TS\"}")
STA=$(q "contracts?select=status&id=eq.$CID" | jq -r '.[0].status')
[ "$CA" = "200" ] && [ "$(jq -r '.state' /tmp/bf_p1.json)" = "payment_recorded" ] && [ "$STA" = "deposit_paid" ] \
  && ok "رصيد جزئي 700 → payment_recorded + يبقى deposit_paid" || no "جزئي: $CA/$STA"

# ===== 8) باقي الرصيد (800) → fully_paid + C-17 =====
CB=$(curl -s -o /tmp/bf_p2.json -w "%{http_code}" -X POST "$FN/payment-approve" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d "{\"contract_id\":\"$CID\",\"amount\":800,\"kind\":\"balance\",\"payment_reference\":\"BAL-full-$TS\"}")
STB=$(q "contracts?select=status&id=eq.$CID" | jq -r '.[0].status')
C17=$(q "email_log?select=id&entity_id=eq.$CID&event_type=eq.C-17&status=eq.sent" | jq length)
[ "$CB" = "200" ] && [ "$STB" = "fully_paid" ] && [ "$C17" = "1" ] \
  && ok "اكتمال الرصيد 800 → fully_paid + C-17 أُرسل" || no "كامل: $CB/$STB/c17=$C17"

# ===== تنظيف (كل شيء عدا السجلات) =====
curl -s -o /dev/null -X DELETE "$SB/payments?contract_id=eq.$CID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]}"
CL=$(q "contracts?select=client_id&id=eq.$CID" | jq -r '.[0].client_id // ""')
curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$CID" "${H[@]}"
[ -n "$CL" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$CL" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/employees?auth_user_id=eq.$TM_UID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$AU/admin/users/$TM_UID" "${H[@]}"
CID=""; TM_UID=""  # شبكة الـEXIT لن تجد شيئًا — التنظيف تم في المسار الناجح
echo "cleanup done (email_log/activity_log بقيا)"

echo ""
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
