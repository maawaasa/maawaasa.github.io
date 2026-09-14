#!/usr/bin/env bash
# =====================================================
# smoke-coverage-team-v2.sh — Targeted: HOLD_24H + TOKEN_SINGLETON
# عقد جديد مستقل ⇒ coverage-confirm مرة واحدة ⇒ تحقق DB كامل بـ Python
# (fromisoformat يدعم fractional seconds). Cleanup كامل.
# بيانات الاعتماد محلية ولا تُطبع.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")

cleanup_contract(){ local cid="$1"
  curl -s -o /dev/null -X DELETE "$SB/action_tokens?entity_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/assignments?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/equipment_reservations?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/contract_equipment?contract_id=eq.$cid" "${H[@]}"
  curl -s -o /dev/null -X DELETE "$SB/contracts?id=eq.$cid" "${H[@]}"
}
cleanup_client(){ local ids="$1"; [ -n "$ids" ] && curl -s -o /dev/null -X DELETE "$SB/clients?id=in.($ids)" "${H[@]}"; }

TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

# ===== 0) مصور نشط =====
PID=$(curl -s "$SB/employees?select=id&role=eq.photographer&is_active=eq.true&order=sort_order&limit=1" "${H[@]}" \
  | jq -r '.[0].id // ""')
[ -z "$PID" ] && { echo "FAIL: لا مصور نشط"; exit 1; }

# ===== 1) عقد اختبار جديد مستقل =====
CA=$(jq -n --arg n "Hold Smoke" --arg p "0550000101" --arg e "hold-smoke@test.local" --arg d "$TOMORROW" \
  '{p_full_name:$n, p_phone:$p, p_email:$e, p_service_type:"تصوير HDR",
    p_total:2000, p_property_type:"apartment", p_shoot_date:$d,
    p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
[ ${#CA} -ge 32 ] && ok "عقد اختبار جاهز: $CA" || { no "إنشاء عقد الاختبار: $CA"; exit 1; }

# ===== 2) تأكيدات ما قبل الاستدعاء =====
# SQL NULL عبر jq -r يصبح سلسلة "null" — نستخدم // empty لتحويلها إلى فارغ
STARTED=$(curl -s "$SB/contracts?select=hold_started_at&id=eq.$CA" "${H[@]}" \
  | jq -r '.[0].hold_started_at // empty')
EXPIRES=$(curl -s "$SB/contracts?select=hold_expires_at&id=eq.$CA" "${H[@]}" \
  | jq -r '.[0].hold_expires_at // empty')
PRE_TOK=$(curl -s "$SB/action_tokens?select=id&entity_id=eq.$CA" "${H[@]}" | jq 'length')

if [ -z "$STARTED" ] && [ -z "$EXPIRES" ] && [ "$PRE_TOK" = "0" ]; then
  ok "PRECONDITION_CLEAN: hold_started_at/hold_expires_at = NULL + tokens=0"
else
  no "ما قبل الاستدعاء غير نظيف: started=[$STARTED] expires=[$EXPIRES] tokens=$PRE_TOK"
  cleanup_contract "$CA"
  cleanup_client "$(curl -s "$SB/clients?select=id&full_name=eq.Hold%20Smoke" "${H[@]}" | jq -r 'map(.id) | join(",")')"
  exit 1
fi

# ===== 3) استدعاء coverage-confirm مرة واحدة =====
CC_BODY=$(jq -n \
  --arg contract_id "$CA" \
  --arg photographer_employee_id "$PID" \
  --arg start_time "10:00" \
  --arg end_time "12:00" \
  '{contract_id:$contract_id, photographer_employee_id:$photographer_employee_id,
    start_time:$start_time, end_time:$end_time}')
printf '%s' "$CC_BODY" | jq -e . >/dev/null || { echo "FAIL: CC_BODY غير صالح"; cleanup_contract "$CA"; exit 1; }

HTTP=$(printf '%s' "$CC_BODY" | curl -s -o /tmp/hold_body.json -w "%{http_code}" \
  -X POST "$BASE/functions/v1/coverage-confirm" "${H[@]}" \
  -H "Content-Type: application/json" --data @-)

# ===== 4/5/6) تحقق DB بعد الاستدعاء (Python — parsing يدعم fractional) =====
ROW=$(curl -s "$SB/contracts?select=status,hold_started_at,hold_expires_at,deposit_review_status&id=eq.$CA" "${H[@]}")
TOKS=$(curl -s "$SB/action_tokens?select=id,token_hash,purpose,used_at,entity_id&entity_id=eq.$CA" "${H[@]}")

RESULT=$(python3 - "$ROW" "$TOKS" "$HTTP" "$CA" <<'PY'
import sys, json
from datetime import datetime, timezone

row = json.loads(sys.argv[1])[0]
toks = json.loads(sys.argv[2])
http = sys.argv[3]
cid  = sys.argv[4]

def parse_iso(s):
    # يدعم fractional seconds وZ و+00:00
    return datetime.fromisoformat(s.replace('Z', '+00:00'))

errors = []

if http != '200':
    errors.append(f'HTTP {http}')

started = row.get('hold_started_at')
expires = row.get('hold_expires_at')

if not started:
    errors.append('hold_started_at = NULL بعد الاستدعاء')
if not expires:
    errors.append('hold_expires_at = NULL بعد الاستدعاء')

dur = None
if started and expires:
    dur = (parse_iso(expires) - parse_iso(started)).total_seconds()
    if not (86340 <= dur <= 86460):  # 23h59m – 24h01m
        errors.append(f'المدة {dur/3600:.4f}h خارج نطاق 24h')

if row.get('status') != 'awaiting_payment':
    errors.append(f'status = {row.get("status")}')

# TOKEN_SINGLETON: رمز deposit_receipt واحد غير مستخدم مرتبط بالعقد
dep = [t for t in toks
       if t.get('purpose') == 'deposit_receipt'
       and t.get('used_at') is None
       and t.get('entity_id') == cid]
if len(toks) != 1 or len(dep) != 1:
    errors.append(f'token count={len(toks)} deposit={len(dep)}')

if errors:
    print('FAIL: ' + ' | '.join(errors))
    sys.exit(1)

print('PASS')
print(f'  hold_started_at = {started}')
print(f'  hold_expires_at = {expires}')
print(f'  المدة ≈ {dur/3600:.4f} ساعات')
print(f'  deposit_receipt token = 1 (used_at=null, مرتبط بالعقد)')
PY
)

if echo "$RESULT" | head -1 | grep -q '^PASS'; then
  ok "HOLD_24H + TOKEN_SINGLETON"
  echo "$RESULT"
else
  no "HOLD_24H/TOKEN: $RESULT"
fi

# ===== 7) Cleanup كامل =====
cleanup_contract "$CA"
CL=$(curl -s "$SB/clients?select=id&full_name=eq.Hold%20Smoke" "${H[@]}" | jq -r 'map(.id) | join(",")')
cleanup_client "$CL"
echo "  cleanup: عقد ورموز وعملاء الاختبار أُزيلت"

HOLD_VERDICT=$([ "$RESULT" = PASS ] 2>/dev/null && echo PASS || echo FAIL)
echo
echo "HOLD_24H = $(echo "$RESULT" | grep -q 'PASS' && echo PASS || echo FAIL)"
echo "TOKEN_SINGLETON = $(echo "$RESULT" | grep -q 'PASS' && echo PASS || echo FAIL)"
echo "READY_TO_CLOSE_COVERAGE = YES (إن كان الاثنان PASS)"
