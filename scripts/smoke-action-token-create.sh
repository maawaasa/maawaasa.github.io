#!/usr/bin/env bash
# =====================================================
# smoke-action-token-create.sh — Positive Test الآمن
# يعمل محليًا فقط: المفتاح يُطلب بلا echo ولا يُطبع ولا يُخزن.
# الاستخدام:
#   chmod +x scripts/smoke-action-token-create.sh
#   ./scripts/smoke-action-token-create.sh
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }

# 0) أحدث عقد حقيقي موجود
CID=$(curl -s "$BASE/rest/v1/contracts?select=id&order=created_at.desc&limit=1" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["id"] if d else "")')
[ -z "$CID" ] && { echo "FAIL: لا يوجد عقد في قاعدة البيانات للفحص"; exit 1; }
echo "contract: $CID"

# 1) استدعاء الدالة بمفتاح الخدمة
HTTP=$(curl -s -o /tmp/atc_resp.json -w "%{http_code}" -X POST \
  "$BASE/functions/v1/action-token-create" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"purpose\":\"deposit_receipt\",\"entity_id\":\"$CID\"}")
[ "$HTTP" = "200" ] && ok "HTTP 200" || no "HTTP $HTTP (متوقع 200)"

TOKEN=$(python3 -c 'import json;d=json.load(open("/tmp/atc_resp.json"));print(d.get("token",""))' 2>/dev/null)
[ ${#TOKEN} -eq 64 ] && ok "raw token يعاد مرة واحدة (64 hex)" || no "raw token غير صالح (${#TOKEN} حرف)"

# 2) تحقق صف action_tokens: hash-only + TTL 24h + الربط بالعقد
ROW=$(curl -s "$BASE/rest/v1/action_tokens?entity_id=eq.$CID&order=created_at.desc&limit=1" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY")
python3 - "$ROW" "$TOKEN" "$CID" <<'PY' && ok "action_tokens: hash-only + TTL≈24h + ربط صحيح" || no "صف action_tokens غير مطابق"
import sys, json, hashlib
from datetime import datetime, timezone, timedelta
row = json.loads(sys.argv[1])[0]
raw = sys.argv[2]; cid = sys.argv[3]
assert row["token_hash"] == hashlib.sha256(raw.encode()).hexdigest(), "token_hash ≠ sha256(raw)"
assert raw not in json.dumps(row), "raw token مخزن!"
exp = datetime.fromisoformat(row["expires_at"].replace("Z", "+00:00"))
delta = exp - datetime.now(timezone.utc)
assert timedelta(hours=23) < delta < timedelta(hours=25), f"TTL خارج 24h: {delta}"
assert row["entity_type"] == "contract", "entity_type خاطئ"
assert row["entity_id"] == cid, "entity_id لا يطابق العقد"
assert row["used_at"] is None, "الرمز مستهلك؟"
PY

# 3) Cleanup — حذف رمز الاختبار
DEL=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "$BASE/rest/v1/action_tokens?entity_id=eq.$CID&purpose=eq.deposit_receipt&used_at=is.null" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY")
[ "$DEL" = "204" ] && ok "Cleanup — حذف رمز الاختبار" || no "Cleanup HTTP $DEL"

rm -f /tmp/atc_resp.json
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
