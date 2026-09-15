#!/usr/bin/env bash
# =====================================================
# run-regression.sh — Final Phase 1 regression suite
# يقرأ service_role مرة واحدة ويمرره لكل سكربت عبر stdin.
# المفتاح لا يُطبع ولا يُخزَّن ولا يُمرَّر كوسيط أمر.
# المجموعة = كل ما ورد في القسم 6 من التسليم + E2E (منفصل).
# =====================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

read -rsp "SUPABASE_SERVICE_ROLE_KEY: " SRK; echo
[ -z "$SRK" ] && { echo "المفتاح مطلوب"; exit 1; }

LOGDIR="/tmp/maawaa-regression-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"

SCRIPTS=(
  smoke-action-token-create.sh
  smoke-receipt-submit.sh
  smoke-receipt-hold-transition.sh
  smoke-coverage-targeted.sh
  smoke-email-reminder-only.sh
  smoke-payment-approve.sh
)

overall=0
summary=()
for s in "${SCRIPTS[@]}"; do
  echo ""
  echo "################################################"
  echo "#  RUNNING: $s"
  echo "################################################"
  printf '%s\n' "$SRK" | bash "$SCRIPT_DIR/$s" 2>&1 | tee "$LOGDIR/${s%.sh}.log"
  rc=${PIPESTATUS[1]}
  if [ "$rc" -eq 0 ]; then
    summary+=("PASS  $s")
  else
    summary+=("FAIL($rc)  $s")
    overall=1
  fi
done

echo ""
echo "=============================================="
echo "  REGRESSION SUMMARY  (logs: $LOGDIR)"
echo "=============================================="
for line in "${summary[@]}"; do echo "  $line"; done
echo "----------------------------------------------"
[ $overall -eq 0 ] && echo "  REGRESSION_FINAL = PASS" || echo "  REGRESSION_FINAL = FAIL"
echo "=============================================="
exit $overall
