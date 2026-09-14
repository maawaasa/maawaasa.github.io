#!/usr/bin/env bash
# =====================================================
# smoke-email-reminder-only.sh — C-11 + O-07 فقط (Reminder-Only)
# fixture معزول: temp employee + عقد status=deposit_paid بجلسة غدًا
# ⇒ استدعاء email-automation مرة واحدة ⇒ تحقق email_log + عدادات
# ⇒ إعادة تشغيل ثانية ⇒ idempotency (لا رسائل جديدة)
# ⇒ Cleanup: assignment/employee/contract/client (email_log يبقى كسجل)
# لا يلمس C-02/C-07. بيانات الاعتماد محلية ولا تُطبع.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"
FN="$BASE/functions/v1"
TOMORROW=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d "+1 day" +%Y-%m-%d)

pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
json(){ jq -n --arg a "$1" --arg b "$2" '{name:$a, email:$b, role:"photographer", is_active:true}'; }

TEST_CUSTOMER="wfalfaifi@gmail.com"
TEST_EMP_EMAIL="wfalfaifi@gmail.com"   # O-07 يذهب لهذا البريد (صندوق المالك) — بمحتوى مسبوق بـ[MAAWAA TEST]
TEST_EMP_NAME="[MAAWAA TEST — IGNORE] Photographer"

# ===== 0) اختيار مصور حقيقي موجود (للربط المرجعي فقط — لن يصله بريد) =====
REAL_EMP=$(curl -s "$SB/employees?select=id,name,email&role=eq.photographer&is_active=eq.true&order=sort_order&limit=1" "${H[@]}" \
  | jq -r '.[0].id // ""')
echo "real employee (لن يصله بريد): ${REAL_EMP:-none}"

# ===== 1) temp employee آمن (يُحذف بعد الاختبار) =====
EMP_BODY=$(jq -n --arg a "$TEST_EMP_NAME" --arg b "$TEST_EMP_EMAIL" \
  '{name:$a, email:$b, role:"photographer", is_active:true}')
EMP=$(printf '%s' "$EMP_BODY" | curl -s -X POST "$SB/employees" "${H[@]}" \
  -H "Content-Type: application/json" -H "Prefer: return=representation" --data @- \
  | jq -r '.[0].id // ""')
[ -z "$EMP" ] && { echo "FAIL: إنشاء temp employee"; exit 1; }
ok "temp employee: $EMP ($TEST_EMP_EMAIL)"

# ===== 2) عقد اختبار status=deposit_paid + جلسة غدًا =====
C=$(jq -n --arg n "[MAAWAA TEST — IGNORE] Client" --arg p "0550000909" --arg e "$TEST_CUSTOMER" --arg d "$TOMORROW" \
  '{p_full_name:$n, p_phone:$p, p_email:$e, p_service_type:"تصوير HDR",
    p_total:2000, p_property_type:"apartment", p_shoot_date:$d,
    p_shoot_start_time:"10:00", p_shoot_end_time:"12:00"}' \
  | curl -s -X POST "$SB/rpc/submit_lead" "${H[@]}" -H "Content-Type: application/json" --data @- \
  | jq -r '. // ""')
[ ${#C} -ge 32 ] && ok "عقد الاختبار: $C" || { no "إنشاء العقد: $C"; exit 1; }
curl -s -o /dev/null -X PATCH "$SB/contracts?id=eq.$C" "${H[@]}" \
  -H "Content-Type: application/json" -d '{"status":"deposit_paid"}'

# ===== 3) assignment: temp employee على عقد الاختبار =====
A_BODY=$(jq -n --arg c "$C" --arg e "$EMP" \
  '{contract_id:$c, employee_id:$e, role_in_job:"photographer"}')
AC=$(curl -s -o /tmp/rem_asg.txt -w "%{http_code}" -X POST "$SB/assignments" "${H[@]}" \
  -H "Content-Type: application/json" --data "$A_BODY")
[ "$AC" = "201" ] && ok "assignment fixture (201)" || no "assignment: HTTP $AC — $(head -c 120 /tmp/rem_asg.txt)"

# إثبات fixture قبل الاستدعاء: العقد + assignment + employee email
FIX=$(curl -s "$SB/assignments?select=contract_id,employee_id&contract_id=eq.$C" "${H[@]}" \
  | jq --arg e "$EMP" '[.[] | select(.employee_id == $e)] | length')
[ "${FIX:-0}" -ge 1 ] && ok "fixture مثبت في DB قبل الاستدعاء" || no "fixture مفقود"

# ===== 4) استدعاء email-automation مرة واحدة =====
# email-automation يتوقع AUTOMATION_SECRET وليس service_role key
AUTOMATION_SECRET="37da9703e524f3e82d817dcea3e90535e97b7845cebbb46a1b9b6af0667b5042"
AH_AUTOMATION=(-H "apikey: $KEY" -H "Authorization: Bearer $AUTOMATION_SECRET")
HTTP_A=$(curl -s -o /tmp/rem_a.json -w "%{http_code}" -X POST "$FN/email-automation" \
  "${AH_AUTOMATION[@]}" -H "Content-Type: application/json" -d '{}')
echo "automation run 1: HTTP $HTTP_A — $(cat /tmp/rem_a.json)"
[ "$HTTP_A" = "200" ] && ok "automation run 200" || no "automation run HTTP $HTTP_A"

# ===== 5) تحقق email_log: C-11 = 1 و O-07 = 1 لهذا العقد =====
C11=$(curl -s "$SB/email_log?select=id&entity_id=eq.$C&event_type=eq.C-11" "${H[@]}" | jq 'length')
O07=$(curl -s "$SB/email_log?select=id&entity_id=eq.$C&event_type=eq.O-07" "${H[@]}" | jq 'length')
[ "$C11" = "1" ] && ok "C-11 email_log = 1" || no "C-11 email_log = $C11"
[ "$O07" = "1" ] && ok "O-07 email_log = 1" || no "O-07 email_log = $O07"

# ===== 6) إعادة تشغيل ثانية ⇒ idempotency (لا رسائل جديدة) =====
HTTP_B=$(curl -s -o /tmp/rem_b.json -w "%{http_code}" -X POST "$FN/email-automation" \
  "${AH_AUTOMATION[@]}" -H "Content-Type: application/json" -d '{}')
sleep 1
C11B=$(curl -s "$SB/email_log?select=id&entity_id=eq.$C&event_type=eq.C-11" "${H[@]}" | jq 'length')
O07B=$(curl -s "$SB/email_log?select=id&entity_id=eq.$C&event_type=eq.O-07" "${H[@]}" | jq 'length')
if [ "$C11B" = "1" ] && [ "$O07B" = "1" ]; then
  ok "idempotency: الإعادة لم تضف رسائل (C-11=1 O-07=1)"
else
  no "idempotency: C-11=$C11B O-07=$O07B"
fi

# ===== 7) Cleanup: assignment + temp employee + عقد + عميل (email_log يبقى كسجل) =====
jdelete(){ curl -s -o /dev/null -X DELETE "$SB/$1" "${H[@]}"; }
jdelete "assignments?contract_id=eq.$C"
jdelete "action_tokens?entity_id=eq.$C"
jdelete "contracts?id=eq.$C"
CL=$(curl -s "$SB/clients?select=id&phone_number=eq.0550000909" "${H[@]}" \
  | jq -r 'map(.id) | join(",")')
[ -n "$CL" ] && jdelete "clients?id=in.($CL)"
jdelete "employees?id=eq.$EMP"
echo "  cleanup: assignment + temp employee + عقد + عميل أُزيلت (email_log بقي كسجل)"
ok "Cleanup"

rm -f /tmp/rem_a.json /tmp/rem_b.json /tmp/rem_asg.txt
echo
echo "================ $pass PASS / $fail FAIL ================"
[ $fail -eq 0 ]
