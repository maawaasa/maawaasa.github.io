#!/usr/bin/env bash
# =====================================================
# check-c03-email-log.sh — READ-ONLY evidence (بلا إشعارات، بلا كتابة، بلا حذف)
# الغاية: إثبات ما إذا كانت C-03 الخلفية (waitUntil) من استدعاء الـsmoke السابق
# وصلت email_log فعلًا — وبأي status/timestamp.
# activity_log لا يُقرأ ولا يُحذف.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")

echo "===== آخر 10 صفوف C-03 في email_log (READ-ONLY) ====="
curl -s "$SB/email_log?select=idempotency_key,recipient,status,error,sent_at,created_at&event_type=eq.C-03&order=created_at.desc&limit=10" "${H[@]}" \
| python3 -c '
import sys, json
rows = json.load(sys.stdin)
if not isinstance(rows, list):
    print("ERR:", json.dumps(rows)[:300]); sys.exit(1)
if not rows:
    print("NO_C03_ROWS")
for r in rows:
    print("-", r.get("created_at"), "|", r.get("status"), "⇒", r.get("recipient"),
          "| sent_at:", r.get("sent_at"), "| err:", (r.get("error") or "")[:120],
          "| key:", r.get("idempotency_key"))
'
echo
echo "ملاحظة: إن لم يظهر صف الـsmoke السابق فذلك غير حاسم —"
echo "cleanup في السكربت حذف صفوف الاختبار، لكن صفًا وصل لاحقًا سيبقى ظاهرًا هنا."
unset KEY
