#!/usr/bin/env bash
# =====================================================
# smoke-coverage-nonteam.sh — NON_TEAM_403 Test
# مستخدم Auth تجريبي غير موجود في employees ⇒ متوقع 403
# المفتاح/البريد/كلمة المرور/JWT لا تُطبع إطلاقًا.
# الطلب آمن: contract_id وهمي — الفحص يقع قبل أي وصول لقاعدة البيانات.
# =====================================================
set -uo pipefail
BASE="https://fivrwlowntwacfrsocge.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdnJ3bG93bnR3YWNmcnNvY2dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNjU0ODYsImV4cCI6MjA5MTg0MTQ4Nn0.isXqeO1WYGM3EAolRykwU1ppNgMKmKbU7j-U2Nvb9fc"

read -rp "Test user email: " EMAIL
read -rsp "Test user password: " PASS; echo
[ -z "$EMAIL" ] || [ -z "$PASS" ] && { echo "البريد وكلمة المرور مطلوبان"; exit 1; }

# 1) signInWithPassword → access_token داخليًا فقط
LOGIN=$(curl -s -X POST "$BASE/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
JWT=$(printf '%s' "$LOGIN" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("access_token",""))')
[ -z "$JWT" ] && { echo "FAIL: فشل تسجيل الدخول — تحقق من البريد/كلمة المرور"; exit 1; }

# 2) coverage-confirm بطلب آمن لا يغيّر شيئًا (contract_id وهمي)
c=$(curl -s -o /tmp/nt_body.txt -w "%{http_code}" -X POST "$BASE/functions/v1/coverage-confirm" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"contract_id":"00000000-0000-0000-0000-000000000000"}')
e=$(python3 -c 'import json;d=json.load(open("/tmp/nt_body.txt"));print(d.get("error",""))')

rm -f /tmp/nt_body.txt
unset JWT PASS LOGIN

# 3) الحكم
if [ "$c" = "403" ] && [ "$e" = "forbidden_not_team_member" ]; then
  echo "NON_TEAM_403 = PASS"
else
  echo "NON_TEAM_403 = FAIL (HTTP $c / $e)"
fi
