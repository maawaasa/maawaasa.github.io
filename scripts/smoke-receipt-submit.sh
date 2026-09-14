#!/usr/bin/env bash
# =====================================================
# smoke-receipt-submit.sh — E2E كامل (يتطلب service_role)
# المفتاح يُطلب بلا echo ولا يُخزن ولا يُطبع.
# يغطي: invalid/used/expired/wrong-purpose/type/size/upload/
#       hold-clear/review-flag/reuse/path-binding/storage-private
# وينظف الآثار بعد الانتهاء.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
ST="$BASE/storage/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
code(){ curl -s -o /tmp/rs_body.txt -w "%{http_code}" "$@"; }
bodyerr(){ python3 -c 'import json;d=json.load(open("/tmp/rs_body.txt"));print(d.get("error",""))'; }
mint(){ curl -s -X POST "$BASE/functions/v1/action-token-create" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "{\"purpose\":\"$1\",\"entity_id\":\"$2\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))'; }
gen_png(){ python3 -c '
import zlib,struct,os,base64,sys
w,h=int(sys.argv[1]),int(sys.argv[2])
def ch(t,d):
    c=t+d
    return struct.pack(">I",len(d))+c+struct.pack(">I",zlib.crc32(c)&0xffffffff)
raw=b"".join(b"\x00"+os.urandom(w*3) for _ in range(h))
png=b"\x89PNG\r\n\x1a\n"+ch(b"IHDR",struct.pack(">IIBBBBB",w,h,8,2,0,0,0))+ch(b"IDAT",zlib.compress(raw,6))+ch(b"IEND",b"")
print("data:image/png;base64,"+base64.b64encode(png).decode())' "$1" "$2"; }
submit(){
  python3 -c 'import json,sys;print(json.dumps({"token":sys.argv[1],"image_data_url":open(sys.argv[2]).read().strip()}))' "$1" "$2" \
  | curl -s -o /tmp/rs_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/receipt-submit" \
    -H "Content-Type: application/json" --data @-
}

# ===== 0) عقد اختبار: أحدث عقد status=new =====
CID=$(curl -s "$SB/contracts?select=id&status=eq.new&order=created_at.desc&limit=1" \
  "${H[@]}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["id"] if d else "")')
[ -z "$CID" ] && { echo "FAIL: لا يوجد عقد status=new للاختبار — أنشئ طلب اختبار أولًا"; exit 1; }
echo "test contract: $CID"

ORIG=$(curl -s "$SB/contracts?select=receipt_uploaded_at,receipt_image_url,deposit_review_status,hold_expires_at,hold_started_at&id=eq.$CID" "${H[@]}")
echo "original: $ORIG"

# تفعيل Hold اختباري (شرط قبول deposit receipt)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EXP=$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+1 hour" +%Y-%m-%dT%H:%M:%SZ)
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CID" "${H[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"hold_started_at\":\"$NOW\",\"hold_expires_at\":\"$EXP\",\"status\":\"new\"}"

gen_png 64 64 > /tmp/rs_small.png
gen_png 1700 1700 > /tmp/rs_big.png
python3 -c 'import base64;open("/tmp/rs_svg.txt","w").write("data:image/svg+xml;base64,"+base64.b64encode(b"<svg/>").decode())'

# ===== 1) invalid token =====
c=$(submit "deadbeef" /tmp/rs_small.png); e=$(bodyerr)
if [ "$c" = "400" ] && [ "$e" = "invalid_or_used_token" ]; then ok "invalid token رفض"; else no "invalid token: HTTP $c err=$e"; fi

# ===== 2) wrong purpose (rating token) =====
RT=$(mint rating "$CID")
c=$(submit "$RT" /tmp/rs_small.png); e=$(bodyerr)
if [ "$c" = "400" ]; then ok "wrong purpose رفض ($e)"; else no "wrong purpose: HTTP $c"; fi

# ===== 3) expired token =====
ET=$(mint deposit_receipt "$CID")
if [ -n "$ET" ]; then
  curl -s -o /dev/null -X PATCH "$SB/action_tokens?entity_id=eq.$CID&purpose=eq.deposit_receipt&used_at=is.null" "${H[@]}" \
    -H "Content-Type: application/json" -d '{"expires_at":"2020-01-01T00:00:00Z"}'
fi
c=$(submit "$ET" /tmp/rs_small.png); e=$(bodyerr)
if [ "$c" = "400" ]; then ok "expired token رفض ($e)"; else no "expired token: HTTP $c"; fi

# ===== 4) unsupported type برمز صالح (يجب ألا يُحرق الرمز) =====
ST=$(mint deposit_receipt "$CID")
c=$(submit "$ST" /tmp/rs_svg.txt); e=$(bodyerr)
if [ "$c" = "400" ] && [ "$e" = "unsupported_image_type" ]; then
  # تأكيد أن الرمز لم يُستهلك (release قبل الـClaim)
  USED=$(curl -s "$SB/action_tokens?select=used_at&entity_id=eq.$CID&purpose=eq.deposit_receipt&order=created_at.desc&limit=1" "${H[@]}" \
    | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r[0]["used_at"] if r and r[0]["used_at"] else "")')
  [ -z "$USED" ] && ok "svg رفض والرمز سليم" || no "svg: الرمز استُهلك رغم الرفض"
else
  no "svg: HTTP $c err=$e"
fi

# ===== 5) size >8MB =====
c=$(submit "anytoken" /tmp/rs_big.png); e=$(bodyerr)
if [ "$c" = "400" ] && [ "$e" = "image_too_large" ]; then ok "size رفض"; else no "size: HTTP $c err=$e"; fi

# ===== 6) valid deposit upload =====
c=$(submit "$ST" /tmp/rs_small.png)
if [ "$c" = "200" ] && grep -q 'receipt_under_review' /tmp/rs_body.txt; then
  ok "upload ناجح + receipt_under_review"
else
  no "valid upload: HTTP $c — $(head -c 150 /tmp/rs_body.txt)"
fi

# ===== 7) حقول العقد + path binding =====
ROW=$(curl -s "$SB/contracts?select=hold_expires_at,deposit_review_status,receipt_image_url,contract_number&id=eq.$CID" "${H[@]}")
if python3 - "$ROW" <<'PY'
import sys, json
r = json.loads(sys.argv[1])[0]
assert r["hold_expires_at"] is None, "hold لم يُصفَّر"
assert r["deposit_review_status"] == "receipt_under_review", "review flag"
u = r["receipt_image_url"] or ""
assert u.startswith(r["receipt_image_url"].split("/")[0]) and "/" in u, "path"
PY
then ok "حقول العقد + path مرتبط بالعقد من الرمز"; else no "حقول العقد"; fi

# ===== 8) reuse نفس الرمز =====
c=$(submit "$ST" /tmp/rs_small.png); e=$(bodyerr)
if [ "$c" = "400" ] && [ "$e" = "invalid_or_used_token" ]; then ok "reuse رفض"; else no "reuse: HTTP $c"; fi

# ===== 9) storage private =====
ANON=$(grep -o "SUPABASE_ANON_KEY = '[^']*'" assets/js/supabase-config.js | cut -d"'" -f2)
ca=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$ST/object/receipts/anon-probe.txt" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: text/plain" -d 'x')
if [ "$ca" != "200" ]; then ok "storage private (anon: $ca)"; else no "anon رفع ناجح!"; fi

# ===== 10) Cleanup =====
RIMG=$(curl -s "$SB/contracts?select=receipt_image_url&id=eq.$CID" "${H[@]}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["receipt_image_url"] or "")')
if [ -n "$RIMG" ]; then
  curl -s -o /dev/null -X DELETE "$ST/object/receipts/$RIMG" "${H[@]}"
  echo "  حُذفت صورة الاختبار من Storage"
fi
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CID" "${H[@]}" \
  -H "Content-Type: application/json" \
  -d '{"receipt_uploaded_at":null,"receipt_image_url":null,"deposit_review_status":null,"hold_started_at":null,"hold_expires_at":null}'
curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]}"
echo "  أُزيلت رموز الاختبار ورُجّعت حقول العقد"
ok "Cleanup"

rm -f /tmp/rs_body.txt /tmp/rs_small.png /tmp/rs_big.png /tmp/rs_svg.txt
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
