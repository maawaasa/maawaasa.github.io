#!/usr/bin/env bash
# =====================================================
# diag-c11-selection.sh — READ-ONLY (صفر كتابة، صفر إيميل، بلا fixtures)
# يثبت: هل embed assignments(employees(...)) في remindShoot يعمل على Production؟
# خطأ العلاقات schema-level يظهر فورًا حتى على استعلام بلا نتائج.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
TODAY=$(date -u +%F)
TOMORROW=$(date -u -v+1d +%F 2>/dev/null || date -u -d "+1 day" +%F)

echo "TOMORROW_UTC (كما يحسبه harness)   = $TOMORROW"
echo "ملاحظة TZ: الدالة تحسب new Date(Date.now()+86400_000) بفواصل runtime-local؛
Edge Runtime في Supabase يعمل UTC ⇒ مطابق لـdate -u -v+1d — لا خلل حدّي متوقع."

echo
echo "===== [A] الاستعلام الحرفي مع embed assignments(employees(...)) ====="
HTTP_A=$(curl -s -o /tmp/c11a.txt -w "%{http_code}" \
  "$SB/contracts?select=id,contract_number,status,shoot_date,service_type,property_location,clients(email,full_name),assignments(employees(id,name,email))&status=in.(deposit_paid,in_progress)&shoot_date=eq.$TOMORROW&limit=100" "${H[@]}")
echo "HTTP=$HTTP_A"
python3 -c 'import json;d=json.load(open("/tmp/c11a.txt"));print(json.dumps(d,ensure_ascii=False)[:500])' 2>/dev/null || head -c 400 /tmp/c11a.txt
echo
python3 - <<'PY'
import json
try: d = json.load(open('/tmp/c11a.txt'))
except Exception: d = None
if isinstance(d, dict) and d.get("code"):
    print("EMBED_QUERY_RESULT = ERROR")
    print("PG_CODE    =", d.get("code"))
    print("MESSAGE    =", d.get("message"))
    print("DETAILS    =", d.get("details"))
    print("HINT       =", d.get("hint"))
elif isinstance(d, list):
    print("EMBED_QUERY_RESULT = OK rows=" + str(len(d)))
else:
    print("EMBED_QUERY_RESULT = UNEXPECTED")
PY

echo
echo "===== [B] نفس الاستعلام بلا assignments (الإصلاح الأدنى المتوقع) ====="
HTTP_B=$(curl -s -o /tmp/c11b.txt -w "%{http_code}" \
  "$SB/contracts?select=id,contract_number,status,shoot_date,clients(email,full_name)&status=in.(deposit_paid,in_progress)&shoot_date=eq.$TOMORROW&limit=100" "${H[@]}")
echo "HTTP=$HTTP_B"
head -c 200 /tmp/c11b.txt; echo

echo
echo "===== [C] سطر التحكم: نفس embed لكن عبر علاقة employees العكسية ====="
HTTP_C=$(curl -s -o /tmp/c11c.txt -w "%{http_code}" \
  "$SB/assignments?select=id,contract_id,employees(id,name,email)&limit=1" "${H[@]}")
echo "HTTP=$HTTP_C"
head -c 200 /tmp/c11c.txt; echo

rm -f /tmp/c11a.txt /tmp/c11b.txt /tmp/c11c.txt
unset KEY
echo "===== DIAG DONE (READ-ONLY — صفر كتابة) ====="
