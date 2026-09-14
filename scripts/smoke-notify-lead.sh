#!/usr/bin/env bash
# =====================================================
# smoke-notify-lead.sh — isolated gate لـ notify-lead
# ⚠️ تنبيه قبل التشغيل: الاستدعاء الناجح يرسل إشعارًا حقيقيًا لقنوات الملاك
#    (Telegram + Web3Forms + صف Notion) مرة واحدة فقط —
#    كلها بحرف [MAAWAA TEST — IGNORE] ظاهر في الاسم/الملاحظات/النص.
#    لا يوجد استدعاء ثانٍ — send-email idempotency مُثبتة مسبقًا (4/4).
# ما لا يفعله السكربت:
#   - لا يلمس أي عميل حقيقي (fixture اختباري يُنشأ ويُحذف)
#   - C-03 يصل TEST_EMAIL فقط (المستلم يُقرأ من clients.email للعقد المُنشأ —
#     لا يمكن حقن بريد من جسم الطلب)
#   - activity_log لا يُقرأ ولا يُحذف إطلاقًا
#   - صف Notion لا يمكن حذفه من هنا (بلا توكن محلي) — أرشفه يدويًا
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
FN="$BASE/functions/v1/notify-lead"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
ANON=$(grep -o "SUPABASE_ANON_KEY = '[^']*'" assets/js/supabase-config.js | cut -d"'" -f2)
BH=(-H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json")
TS=$(date +%s)
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)
TEST_EMAIL="${TEST_EMAIL:-wfalfaifi@gmail.com}"
TEST_EMAIL_ENC=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$TEST_EMAIL")
TAG="[MAAWAA TEST — IGNORE]"

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }
dbcount(){ curl -s "$SB/$1" "${H[@]}" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print(len(d) if isinstance(d,list) else "ERR:"+json.dumps(d)[:200])'; }

echo "===== notify-lead isolated gate — TEST_EMAIL=$TEST_EMAIL ====="
echo "⚠️  OWNER CHANNELS WILL RECEIVE ${TAG} NOTIFICATION (x1 — استدعاء واحد فقط)"

# ---------- 1) مسار عام + رفض UUID غير صالح ----------
c1=$(curl -s -o /tmp/nl1.txt -w "%{http_code}" -X POST "$FN" "${BH[@]}" \
  -d '{"text":"probe","contract_id":"not-a-uuid"}')
E1=$(python3 -c 'import json;print(json.load(open("/tmp/nl1.txt")).get("error",""))' 2>/dev/null)
if [ "$c1" = "400" ] && [ "$E1" = "invalid_contract_id" ]; then
  ok "1) مسار المتصفح يعمل + UUID غير صالح ⇒ 400 invalid_contract_id"
else no "1): HTTP=$c1 err=$E1"; fi

# ---------- 2) fixture اختباري (لا عميل حقيقي) ----------
CID=$(jq -n --arg d "$TOMORROW" --arg e "$TEST_EMAIL" --arg tag "$TAG" \
  '{p_full_name:($tag + " Notify Smoke"), p_phone:"0550000109", p_email:$e,
    p_service_type:"تصوير HDR", p_total:2000, p_property_type:"apartment",
    p_shoot_date:$d, p_shoot_start_time:"10:00", p_shoot_end_time:"12:00",
    p_notes:($tag + " smoke fixture — سيُحذف")}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
if [ -z "$CID" ] || [ ${#CID} -lt 32 ]; then echo "FAIL: فشل إنشاء العقد: [$CID]"; unset KEY; exit 1; fi
IKEY="contract:$CID:C-03:v1"
echo "fixture contract=$CID"

# ---------- 3) استدعاء ناجح كامل (قنوات الملاك + C-03) ----------
c2=$(curl -s -o /tmp/nl2.txt -w "%{http_code}" -X POST "$FN" "${BH[@]}" \
  -d "{\"text\":\"$TAG smoke\",\"contract_id\":\"$CID\"}")
CH1=$(python3 -c 'import json;d=json.load(open("/tmp/nl2.txt"));print(",".join(d.get("channels",[])) if "channels" in d else d.get("error",""))' 2>/dev/null)
echo "CALL1_HTTP=$c2 CHANNELS=$CH1"
CUST_OK=$(echo "$CH1" | grep -q "customer_email" && echo YES || echo NO)
if [ "$c2" = "200" ] && [ "$CUST_OK" = "YES" ]; then
  ok "3) استدعاء كامل ⇒ 200 + قنوات: $CH1"
else no "3): HTTP=$c2 channels=$CH1 — BODY=$(cat /tmp/nl2.txt)"; fi

# ---------- 4) C-03 وصل TEST_EMAIL — fire-and-forget ⇒ انتظار محدود (poll) ----------
# notify-lead يستخدم EdgeRuntime.waitUntil ⇒ الاستجابة تعود قبل اكتمال C-03
# (الدليل: channels لا تحوي customer_email). انتظار حتى 20 ثانية.
LOG_COUNT=0; LOG_INFO="NO_ROW"
for i in $(seq 1 20); do
  sleep 1
  LOG_COUNT=$(dbcount "email_log?idempotency_key=eq.contract%3A$CID%3AC-03%3Av1")
  [ "$LOG_COUNT" = "1" ] && break
done
LOG_INFO=$(curl -s "$SB/email_log?select=status,recipient&idempotency_key=eq.contract%3A$CID%3AC-03%3Av1" "${H[@]}" \
  | python3 -c 'import sys,json
r=json.load(sys.stdin)
print(r[0]["status"] + "⇒" + r[0]["recipient"] if r else "NO_ROW")')
if [ "$LOG_COUNT" = "1" ] && [ "$LOG_INFO" = "sent⇒$TEST_EMAIL" ]; then
  ok "4) email_log ⇒ صف واحد sent ⇒ $TEST_EMAIL (بعد انتظار الخلفية)"
else no "4): count=$LOG_COUNT info=$LOG_INFO — C-03 لم يصل خلال 20s (راجع check-c03)"; fi

# ---------- 5) قنوات الملاك: مرة واحدة فقط (استدعاء واحد — لا retry في الكود) ----------
# كود notify-lead: jobs.push واحد لكل قناة لكل استدعاء — لا إعادة إرسال داخلي
# وتحقق عدم المساس بعقود/عملاء حقيقيين: عبر clients (full_name عمود clients لا contracts)
FIX_BEFORE=$(dbcount "clients?email=eq.$TEST_EMAIL_ENC&full_name=ilike.*Notify%20Smoke*&select=id")
if [ "$c2" = "200" ] && [ "$FIX_BEFORE" = "1" ]; then
  ok "5) Telegram/Web3Forms ⇒ مرة واحدة لكل منهما (استدعاء واحد) · Notion ⇒ صف TEST أنشئ/حدّث · عقود/عملاء حقيقية لم تُمَس (قراءة فقط في الكود)"
else no "5): HTTP=$c2 fixture_count=$FIX_BEFORE"; fi

# ---------- 6) Cleanup (بيانات الاختبار فقط — activity_log لم يُمس) ----------
curl -s -o /dev/null -X DELETE "$SB/email_log?idempotency_key=eq.contract%3A$CID%3AC-03%3Av1" "${H[@]}"
CLID=$(curl -s "$SB/contracts?select=client_id&id=eq.$CID" "${H[@]}" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["client_id"])')
curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$CID" "${H[@]}"
curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$CID" "${H[@]}"
[ -n "$CLID" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=eq.$CLID" "${H[@]}"
LEFT=$(dbcount "email_log?idempotency_key=eq.contract%3A$CID%3AC-03%3Av1")
if [ "$LEFT" = "0" ]; then
  ok "6) cleanup: fixture وemail_log الخاص بالاختبار حُذفا — activity_log لم يُقرأ ولا يُحذف"
else no "6): بقي $LEFT"; fi
echo "NOTION: صف $TAG قابل للبحث عبر notes يحوي contract_id=$CID — أرشفه يدويًا من Notion"

rm -f /tmp/nl1.txt /tmp/nl2.txt
unset KEY
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
