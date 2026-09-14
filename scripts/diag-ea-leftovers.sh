#!/usr/bin/env bash
# =====================================================
# diag-ea-leftovers.sh — READ-ONLY DIAG (بلا حذف، بلا إيميل، بلا استدعاء أتمتة)
# يستخرج الصفين المطابقين لبوابة الأمان حرفيًا + كل بياناتهما + markers الاختبار،
# ثم يطبع أوامر cleanup جاهزة مقيّدة بالـIDs الدقيقة (لا ينفذها).
# activity_log لا يُقرأ ولا يُحذف.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
SB="$BASE/rest/v1"

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " KEY; echo
[ -z "$KEY" ] && { echo "المفتاح مطلوب"; exit 1; }
H=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
TODAY=$(date -u +%F)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TOMORROW=$(date -u -v+1d +%F 2>/dev/null || date -u -d "+1 day" +%F)

SEL='select=id,client_id,status,hold_started_at,hold_expires_at,receipt_uploaded_at,shoot_date,created_at,notes,clients(email,full_name)'

dump_row(){
python3 -c '
import sys, json
rows = json.load(sys.stdin)
if not isinstance(rows, list):
    print("ERR:", json.dumps(rows)[:300]); sys.exit(1)
if not rows:
    print("NO_ROWS"); sys.exit(0)
for r in rows:
    cl = r.get("clients") or {}
    if isinstance(cl, list): cl = cl[0] if cl else {}
    marks = []
    blob = " ".join(str(r.get(k) or "") for k in ("notes","status")) + " " + str(cl.get("email") or "") + " " + str(cl.get("full_name") or "")
    for m in ("MAAWAA TEST","TEST","Smoke","Automation Smoke","wfalfaifi@gmail.com"):
        if m.lower() in blob.lower(): marks.append(m)
    print("TYPE              =", sys.argv[1])
    print("contract_id       =", r.get("id"))
    print("client_id         =", r.get("client_id"))
    print("status            =", r.get("status"))
    print("hold_started_at   =", r.get("hold_started_at"))
    print("hold_expires_at   =", r.get("hold_expires_at"))
    print("receipt_uploaded_at =", r.get("receipt_uploaded_at"))
    print("shoot_date        =", r.get("shoot_date"))
    print("created_at        =", r.get("created_at"))
    print("client_email      =", cl.get("email"))
    print("client_name       =", cl.get("full_name"))
    print("notes             =", r.get("notes"))
    print("test_markers      =", ",".join(marks) if marks else "NONE")
    print("TEST_FIXTURE      =", "YES" if marks else "NO")
    print("-" * 50)
' "$1"
}

echo "===== [1] pending_real_holds (شروط البوابة حرفيًا) ====="
curl -s "$SB/contracts?$SEL&status=in.(new,awaiting_payment)&hold_expires_at=lt.$NOW&receipt_uploaded_at=is.null" "${H[@]}" | dump_row "HOLD"

echo "===== [2] pending_real_reminders (شروط البوابة حرفيًا) ====="
curl -s "$SB/contracts?$SEL&status=in.(deposit_paid,in_progress)&shoot_date=eq.$TOMORROW" "${H[@]}" | dump_row "REMINDER"

echo "===== [3] بقايا أخرى من التشغيل الفاشل (قراءة فقط) ====="
echo "-- quotes اختبارية (Q-SMOKE-*): --"
curl -s "$SB/quotes?select=id,quote_number,status,valid_until&quote_number=like.Q-SMOKE-*" "${H[@]}" | head -c 400; echo
echo "-- عملاء fixture يتامى (Automation Smoke A): --"
curl -s "$SB/clients?select=id,full_name,email,created_at&full_name=like.*Automation%20Smoke*&email=eq.wfalfaifi%40gmail.com" "${H[@]}" | head -c 600; echo
echo "-- reservations نشطة لعقود hold المذكورة أعلاه: (تُطبع في أوامر التنظيف) --"

echo
echo "===== [4] أوامر CLEANUP مقترحة (لا تُنفذ تلقائيًا — عدّل الـIDs من المخرجات أعلاه) ====="
cat <<'EOF'
# استبدل <CONTRACT_B> <CONTRACT_C> <CLIENT_B> <CLIENT_C> <RES_ID> بالقيم المطبوعة أعلاه
# الترتيب: reservations ثم tokens ثم contracts ثم clients ثم email_log إن وجد
# curl -s -X DELETE "$SB/equipment_reservations?id=eq.<RES_ID>" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
# curl -s -X DELETE "$SB/action_tokens?entity_id=in.(<CONTRACT_B>,<CONTRACT_C>)" ...
# curl -s -X DELETE "$SB/contracts?id=in.(<CONTRACT_B>,<CONTRACT_C>)" ...
# curl -s -X DELETE "$SB/clients?id=in.(<CLIENT_B>,<CLIENT_C>,<ORPHAN_CLIENT_A>)" ...
EOF
echo
echo "ملاحظة: عقد D (receipt مرفوع) لا يطابق البوابة لكنه أيضًا بقايا fixture — يُنظف بنفس الدفعة."
unset KEY
