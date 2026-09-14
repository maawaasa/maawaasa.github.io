#!/usr/bin/env bash
# =====================================================
# smoke-receipt-hold-transition.sh — Targeted Hold Lifecycle Test
# يثبت التسلسل: مستقبلية → رفع أثناء Hold → NULL
# يتطلب service_role (إدخال مخفي — لا يُطبع ولا يُخزن)
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }

# 0) عقد اختبار status=new
CID=$(curl -s "$SB/contracts?select=id&status=eq.new&order=created_at.desc&limit=1" \
  "${H[@]}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["id"] if d else "")')
[ -z "$CID" ] && { echo "FAIL: لا عقد status=new"; exit 1; }
ORIG=$(curl -s "$SB/contracts?select=receipt_uploaded_at,receipt_image_url,deposit_review_status,hold_expires_at,hold_started_at&id=eq.$CID" "${H[@]}")
echo "contract: $CID"
echo "original : $ORIG"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EXP=$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+1 hour" +%Y-%m-%dT%H:%M:%SZ)

# ===== 1) تفعيل Hold: started=now + expires=now+1h =====
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CID" "${H[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"hold_started_at\":\"$NOW\",\"hold_expires_at\":\"$EXP\",\"status\":\"new\"}"

# ===== 2) إثبات A: القيمة مستقبلية وغير NULL قبل الرفع =====
PRE=$(curl -s "$SB/contracts?select=hold_started_at,hold_expires_at&id=eq.$CID" "${H[@]}")
if python3 - "$PRE" "$NOW" <<'PY'
import sys, json
from datetime import datetime, timezone, timedelta
r = json.loads(sys.argv[1])[0]
s = r["hold_started_at"]; e = r["hold_expires_at"]
assert s and e, "Hold غير مضبوط"
now = datetime.fromisoformat(sys.argv[2].replace("Z","+00:00"))
ed  = datetime.fromisoformat(e.replace("Z","+00:00"))
assert ed > now + timedelta(minutes=55), f"expires ليست مستقبلية +1h: {e}"
sd  = datetime.fromisoformat(s.replace("Z","+00:00"))
assert (ed - sd) == timedelta(hours=1), "الفترة ≠ ساعة"
PY
then ok "A) hold_expires_at مستقبلية (+1h) وhold_started_at مضبوطتان قبل الرفع"; else no "A) فشل تفعيل/قراءة الـHold"; fi

# ===== 3) رفع deposit receipt أثناء الـHold =====
TOKEN=$(curl -s -X POST "$BASE/functions/v1/action-token-create" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"purpose\":\"deposit_receipt\",\"entity_id\":\"$CID\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')
[ -z "$TOKEN" ] && { no "B) فشل توليد الرمز"; exit 1; }

python3 -c '
import zlib,struct,os,base64
w=h=64
def ch(t,d):
    c=t+d; return struct.pack(">I",len(d))+c+struct.pack(">I",zlib.crc32(c)&0xffffffff)
raw=b"".join(b"\x00"+os.urandom(w*3) for _ in range(h))
png=b"\x89PNG\r\n\x1a\n"+ch(b"IHDR",struct.pack(">IIBBBBB",w,h,8,2,0,0,0))+ch(b"IDAT",zlib.compress(raw,6))+ch(b"IEND",b"")
open("/tmp/hold_png.txt","w").write("data:image/png;base64,"+base64.b64encode(png).decode())'
HC=$(python3 -c 'import json,sys;print(json.dumps({"token":sys.argv[1],"image_data_url":open("/tmp/hold_png.txt").read().strip()}))' "$TOKEN" \
  | curl -s -o /tmp/hold_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/receipt-submit" \
    -H "Content-Type: application/json" --data @-)
if [ "$HC" = "200" ]; then ok "B) رفع إيصال عربون ناجح أثناء الـHold (HTTP 200)"; else no "B) الرفع أثناء الـHold فشل: HTTP $HC — $(head -c 150 /tmp/hold_body.txt)"; fi

# ===== 4) إثبات B: hold_expires_at انتقلت من مستقبلية إلى NULL =====
POST=$(curl -s "$SB/contracts?select=hold_started_at,hold_expires_at,deposit_review_status,receipt_image_url&id=eq.$CID" "${H[@]}")
if python3 - "$POST" <<'PY'
import sys, json
r = json.loads(sys.argv[1])[0]
assert r["hold_expires_at"] is None, f"hold_expires_at ≠ NULL: {r['hold_expires_at']}"
assert r["hold_started_at"] is not None, "hold_started_at أُزالت (يجب أن تبقى)"
assert r["deposit_review_status"] == "receipt_under_review", "review flag"
assert (r["receipt_image_url"] or "").startswith(r["receipt_image_url"].split("/")[0]) and "/" in (r["receipt_image_url"] or ""), "path"
PY
then ok "C) hold_expires_at = NULL + receipt_under_review بعد الرفع"; else no "C) الـHold لم يُصفَّر بعد الرفع"; fi

# ===== 5) الرمز صار مستهلكًا =====
c=$(python3 -c 'import json,sys;print(json.dumps({"token":sys.argv[1],"image_data_url":open("/tmp/hold_png.txt").read().strip()}))' "$TOKEN" \
  | curl -s -o /tmp/hold_body2.txt -w "%{http_code}" -X POST "$BASE/functions/v1/receipt-submit" \
    -H "Content-Type: application/json" --data @-)
e=$(python3 -c 'import json;print(json.load(open("/tmp/hold_body2.txt")).get("error",""))')
if [ "$c" = "400" ] && [ "$e" = "invalid_or_used_token" ]; then ok "D) reuse الرمز مرفوض"; else no "D) reuse: HTTP $c err=$e"; fi

# ===== 6) Cleanup كامل =====
RIMG=$(curl -s "$SB/contracts?select=receipt_image_url&id=eq.$CID" "${H[@]}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["receipt_image_url"] or "")')
[ -n "$RIMG" ] && curl -s -o /dev/null -X DELETE "$BASE/storage/v1/object/receipts/$RIMG" "${H[@]}" && echo "  حُذفت صورة الاختبار"
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$CID" "${H[@]}" \
  -H "Content-Type: application/json" \
  -d '{"receipt_uploaded_at":null,"receipt_image_url":null,"deposit_review_status":null,"hold_started_at":null,"hold_expires_at":null}'
curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]}"
echo "  Cleanup: رُجّعت حقول العقد وحُذفت رموز وصورة الاختبار"
ok "E) Cleanup"

rm -f /tmp/hold_png.txt /tmp/hold_body.txt /tmp/hold_body2.txt
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
