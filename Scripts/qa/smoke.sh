#!/bin/bash
# smoke.sh - Bough local smoke gates (test plan Phase 3.5).
# Usage: ./Scripts/qa/smoke.sh [--fast]
#   --fast skips xcodebuild build/test; only artifact, plist, launch gates run.
# Report: /tmp/bough-smoke-report-<ts>.txt. Exits non-zero on any hard gate failure.
# Writes only under /tmp (plus launches the app). Safe to re-run.
set -uo pipefail

cd "$(dirname "$0")/../.."   # repo root
FAST=0
if [ "${1:-}" = "--fast" ]; then FAST=1; fi

APP="build/export/Bough.app"
REPORT="/tmp/bough-smoke-report-$(date +%Y%m%d-%H%M%S).txt"
FAILED=0

log()  { echo "$1" | tee -a "$REPORT"; }
pass() { log "PASS  $1"; }
fail() { log "FAIL  $1"; FAILED=1; }
info() { log "INFO  $1"; }
# run_gate <label> <command...>
run_gate() {
  local label="$1"; shift
  if "$@" > /dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
  fi
}

log "Bough smoke @ $(date)"
log "host: $(sw_vers -productVersion) $(uname -m) | $(xcodebuild -version | head -1)"
log "git: $(git --version) at $(command -v git)"

# 1+2. build & tests
if [ "$FAST" -eq 0 ]; then
  log "==> build"
  START=$(date +%s)
  if xcodebuild build -project Bough.xcodeproj -scheme Bough -destination 'platform=macOS' -quiet > /tmp/bough-smoke-build.log 2>&1; then
    pass "build ok ($(( $(date +%s) - START ))s)"
  else
    fail "build failed (log: /tmp/bough-smoke-build.log)"
    tail -n 30 /tmp/bough-smoke-build.log >> "$REPORT" 2>/dev/null
  fi
  log "==> tests"
  START=$(date +%s)
  if xcodebuild test -project Bough.xcodeproj -scheme Bough -destination 'platform=macOS' -quiet > /tmp/bough-smoke-test.log 2>&1; then
    pass "tests ok ($(( $(date +%s) - START ))s)"
  else
    fail "tests failed (log: /tmp/bough-smoke-test.log)"
    tail -n 30 /tmp/bough-smoke-test.log >> "$REPORT" 2>/dev/null
  fi
else
  info "build/test skipped (--fast)"
fi

# 3. artifact & signature
log "==> artifact & signature"
if [ -d "$APP" ]; then
  pass "artifact exists: $APP"
  run_gate "codesign verify --strict" codesign --verify --strict --verbose=2 "$APP"
  spctl -a -t exec -vv "$APP" > /tmp/bough-smoke-spctl.log 2>&1
  run_gate "spctl assess" spctl -a -t exec -vv "$APP"
  run_gate "spctl verdict accepted" grep -q accepted /tmp/bough-smoke-spctl.log
  run_gate "stapler validate" xcrun stapler validate "$APP"
else
  fail "artifact missing: $APP (run Scripts/release.sh)"
fi

# 4. Info.plist gates
log "==> Info.plist"
if [ -f "$APP/Contents/Info.plist" ]; then
  PL="$APP/Contents/Info.plist"
  V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PL" 2>/dev/null)
  BV=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PL" 2>/dev/null)
  info "version $V build $BV"
  FEED=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PL" 2>/dev/null)
  if [ -n "$FEED" ] && [ "${FEED#https://}" != "$FEED" ]; then
    pass "SUFeedURL https: $FEED"
  else
    fail "SUFeedURL not https: '$FEED'"
  fi
  KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PL" 2>/dev/null)
  if [ -n "$KEY" ]; then pass "SUPublicEDKey present"; else fail "SUPublicEDKey missing"; fi
  MIN=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PL" 2>/dev/null)
  info "LSMinimumSystemVersion: $MIN"
else
  info "Info.plist gates skipped (no artifact)"
fi

# 5. launch gates
log "==> launch"
WAS_RUNNING=0
if pgrep -x Bough > /dev/null 2>&1; then WAS_RUNNING=1; fi
touch /tmp/bough-smoke-marker
if open "$APP"; then pass "open app"; else fail "open app failed"; fi
sleep 6
if pgrep -x Bough > /dev/null 2>&1; then pass "alive after 6s (was_running=$WAS_RUNNING)"; else fail "not running after open"; fi
CRASHES=$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'Bough*' -newer /tmp/bough-smoke-marker 2>/dev/null | wc -l | tr -d ' ')
if [ "$CRASHES" = "0" ]; then
  pass "no new crash reports"
else
  fail "$CRASHES new crash report(s)"
fi
if [ "$WAS_RUNNING" -eq 0 ] && pgrep -x Bough > /dev/null 2>&1; then
  pkill -x Bough
  info "quit app (launched by smoke)"
fi

# 6. bough:// scheme dispatch
log "==> bough:// scheme"
if [ -d /tmp/bough-lab/topology ] && [ "$WAS_RUNNING" -eq 0 ]; then
  if open "bough://open?path=/tmp/bough-lab/topology"; then pass "scheme dispatch"; else fail "scheme dispatch failed"; fi
  sleep 2
  if pgrep -x Bough > /dev/null 2>&1; then pass "alive after scheme open"; else fail "died after scheme open"; fi
  info "SEMI-AUTO: confirm window shows /tmp/bough-lab/topology"
else
  if [ "$WAS_RUNNING" -eq 1 ]; then info "scheme test skipped (app was already running)"; fi
  if [ ! -d /tmp/bough-lab/topology ]; then info "scheme test skipped (run Scripts/qa/make_lab.sh first)"; fi
fi

# 7. SwiftData store check (informational)
if [ -f "$HOME/Library/Application Support/default.store" ]; then
  pass "SwiftData store present"
else
  info "store not found (informational; created on first launch)"
fi

# 8. residue inventory (informational)
log "==> residue inventory"
for p in "$HOME/Library/Application Support/default.store" "$HOME/Library/Preferences/com.wangyuyang.bough.plist" "$HOME/Library/Caches/com.wangyuyang.bough" "$HOME/Library/Saved Application State/com.wangyuyang.bough.savedState"; do
  if [ -e "$p" ]; then info "  exists: $p"; else info "  absent: $p"; fi
done

echo
if [ "$FAILED" -eq 0 ]; then
  log "SMOKE RESULT: ALL GATES PASSED"
else
  log "SMOKE RESULT: FAILURES PRESENT"
fi
log "report: $REPORT"
exit "$FAILED"
