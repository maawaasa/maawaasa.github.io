#!/usr/bin/env bash
# =====================================================
# cleanup-ea-leftovers.sh v2 — تنظيف بقايا smoke-email-automation الفاشل
# FAIL-CLOSED: أي استجابة REST غير array ⇒ ABORT بطباعة code/message (لا zero-rows)
# DRY_RUN=1  ⇒ اكتشاف + إثبات markers + طباعة IDs فقط — صفر DELETE
# CONFIRM=DELETE (بدون DRY_RUN) ⇒ تنفيذ الحذف بالترتيب الآمن
# لا يلمس: activity_log · Notion · Telegram · Web3Forms · أي صف بلا علامة
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
TEST_EMAIL="wfalfaifi@gmail.com"
TEST_EMAIL_ENC="wfalfaifi%40gmail.com"
WINDOW_H="${SMOKE_WINDOW_HOURS:-24}"
CUTOFF=$(date -u -v-${WINDOW_H}H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$WINDOW_H hours ago" +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date -u +%F)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TOMORROW=$(date -u -v+1d +%F 2>/dev/null || date -u -d "+1 day" +%F)
DRY="${DRY_RUN:-0}"
echo "===== cleanup-ea-leftovers v2 — DRY_RUN=$DRY — منذ $CUTOFF ====="

# restget: يطبع الجسم؛ يضع HTTP في $REST_HTTP — ABORT على أي غير 200 (fail-closed)
restget(){
  REST_HTTP=$(curl -s -o /tmp/cl_body.txt -w "%{http_code}" "$SB/$1" "${H[@]}")
  if [ "$REST_HTTP" != "200" ]; then
    echo "ABORT: REST $REST_HTTP على: $1"
    python3 -c 'import json;d=json.load(open("/tmp/cl_body.txt"));print("PG_CODE =",d.get("code",""));print("MESSAGE  =",d.get("message",""));print("DETAILS  =",d.get("details",""));print("HINT     =",d.get("hint",""))' 2>/dev/null || head -c 300 /tmp/cl_body.txt
    unset KEY; rm -f /tmp/cl_body.txt; exit 1
  fi
  cat /tmp/cl_body.txt
}
ids(){ python3 -c 'import sys,json
d=json.load(sys.stdin)
if not isinstance(d,list): print("ABORT:NOT_ARRAY:"+json.dumps(d)[:300]); sys.exit(0)
print("\n".join(str(r["id"]) for r in d))'; }
check_abort_ids(){ echo "$1" | grep -q "^ABORT:" && { echo "$1"; unset KEY; rm -f /tmp/cl_body.txt; exit 1; } || true; }
del(){ curl -s -o /dev/null -X DELETE "$SB/$1" "${H[@]}"; }
delloop(){ for id in $1; do [ -n "$id" ] && del "$2?id=eq.$id"; done; }

# ---------- 1) عملاء العلامة داخل النافذة (or= بفاصل النقطة — الصيغة الصحيحة) ----------
CLIENT_IDS=$(restget "clients?select=id,full_name,email,created_at&email=eq.$TEST_EMAIL_ENC&or=(full_name.ilike.*Automation*Smoke*,full_name.ilike.*MAAWAA*TEST*)&created_at=gte.$CUTOFF" | ids)
check_abort_ids "$CLIENT_IDS"
echo "LEFTOVER_CLIENT_IDS:"; echo "$CLIENT_IDS" | sed 's/^/  /'
if [ -z "$CLIENT_IDS" ]; then echo "لا يوجد عملاء علامة داخل النافذة — لا شيء للحذف"; unset KEY; rm -f /tmp/cl_body.txt; exit 0; fi
CSV=$(echo "$CLIENT_IDS" | paste -sd, -)

# ---------- 2) عقود المرشحين + تحقق النافذة ----------
CONTRACT_RAW=$(restget "contracts?select=id,client_id,status,notes,created_at&client_id=in.($CSV)&created_at=gte.$CUTOFF")
CONTRACT_IDS=$(echo "$CONTRACT_RAW" | TEST_CUTOFF="$CUTOFF" python3 -c '
import sys, json, os
cutoff = os.environ["TEST_CUTOFF"]
rows = json.load(sys.stdin)
bad, good = [], []
for r in rows:
    (good if r.get("created_at","") >= cutoff else bad).append(r["id"])
for rid in bad: print("ABORT:OUTSIDE_WINDOW:" + rid)
print("\n".join(good))')
check_abort_ids "$CONTRACT_IDS"
echo "LEFTOVER_CONTRACT_IDS:"; echo "$CONTRACT_IDS" | sed 's/^/  /'
CCSV=$(echo "$CONTRACT_IDS" | paste -sd, -)

# ---------- 3) المرتبط بالعقود المؤكدة فقط ----------
RES_IDS=$([ -n "$CCSV" ] && restget "equipment_reservations?select=id&contract_id=in.($CCSV)" | ids); check_abort_ids "$RES_IDS"
TOK_IDS=$([ -n "$CCSV" ] && restget "action_tokens?select=id&entity_id=in.($CCSV)" | ids); check_abort_ids "$TOK_IDS"
MAIL_IDS=$([ -n "$CCSV" ] && restget "email_log?select=id&entity_id=in.($CCSV)&event_type=eq.C-03" | ids); check_abort_ids "$MAIL_IDS"
echo "LEFTOVER_RESERVATION_IDS:"; echo "$RES_IDS" | sed 's/^/  /'
echo "LEFTOVER_TOKEN_IDS:"; echo "$TOK_IDS" | sed 's/^/  /'
echo "EMAIL_LOG_IDS:"; echo "$MAIL_IDS" | sed 's/^/  /'

# ---------- 4) quotes اختبارية (عميلها ضمن المؤكدين وإلا ABORT) ----------
QUOTE_IDS=$(restget "quotes?select=id,client_id,quote_number,created_at&quote_number=like.Q-SMOKE-*&created_at=gte.$CUTOFF" | CLIENT_IDS="$CLIENT_IDS" python3 -c '
import sys, json, os
allowed = set(os.environ["CLIENT_IDS"].split())
rows = json.load(sys.stdin)
bad = [r["id"] for r in rows if r["client_id"] not in allowed]
for rid in bad: print("ABORT:QUOTE_FOREIGN_CLIENT:" + rid)
if not bad: print("\n".join(r["id"] for r in rows))')
check_abort_ids "$QUOTE_IDS"
echo "LEFTOVER_QUOTE_IDS:"; echo "$QUOTE_IDS" | sed 's/^/  /'

rm -f /tmp/cl_body.txt

# ---------- 5) التنفيذ (DRY_RUN يمنع أي DELETE) ----------
if [ "$DRY" = "1" ]; then
  echo
  echo "DRY_RUN_DONE — لا DELETE نُفذ. إثبات markers أعلاه (email + اسم/marker + نافذة)."
  echo "للتنفيذ الفعلي: CONFIRM=DELETE bash scripts/cleanup-ea-leftovers.sh"
  unset KEY; exit 0
fi
if [ "${CONFIRM:-}" != "DELETE" ]; then
  echo "ABORT: الحذف يتطلب CONFIRM=DELETE (أو DRY_RUN=1 للفحص فقط)"
  unset KEY; exit 1
fi

delloop "$RES_IDS"  "equipment_reservations"
delloop "$TOK_IDS"  "action_tokens"
delloop "$MAIL_IDS" "email_log"
[ -n "$CCSV" ] && del "contracts?id=in.($CCSV)"
QCSV=$(echo "$QUOTE_IDS" | paste -sd, -); [ -n "$QCSV" ] && del "quotes?id=in.($QCSV)"
del "clients?id=in.($CSV)"
echo "DELETE_DONE"

# ---------- 6) Safety Gate read-only بعد التنظيف ----------
sleep 1
PQ=$(restget "quotes?status=eq.active&valid_until=lt.$TODAY&expired_notified_at=is.null&select=id" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')
PH=$(restget "contracts?status=in.(new,awaiting_payment)&hold_expires_at=lt.$NOW&receipt_uploaded_at=is.null&select=id" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')
PR=$(restget "contracts?status=in.(deposit_paid,in_progress)&shoot_date=eq.$TOMORROW&select=id" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')
echo "SAFETY_GATE_AFTER: pending_real_quotes=$PQ pending_real_holds=$PH pending_real_reminders=$PR"
if [ "$PQ" = "0" ] && [ "$PH" = "0" ] && [ "$PR" = "0" ]; then
  echo "CLEANUP = PASS (0/0/0) — activity_log لم يُمس"
else
  echo "CLEANUP = INCOMPLETE — راجع الصفوف المتبقية قبل أي إعادة تشغيل"
fi
unset KEY
