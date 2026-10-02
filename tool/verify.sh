#!/usr/bin/env bash
#
# The gate. A branch may only be promoted to master when this exits 0.
#
# It exists because "green" drifted into whatever felt confident, and that is
# how a hanging test suite ended up committed on master: `flutter analyze` was
# clean, so it read as done. Analyze passing proves the code COMPILES. It says
# nothing about whether the suite runs to completion. Both have to pass, and the
# suite has a wall-clock limit so that a hang is a failure rather than a run
# that never returns.
#
# Usage:
#   tool/verify.sh              # full gate: format, analyze, test, build
#   tool/verify.sh --no-build   # skip the APK build while iterating
#
# Exit codes:
#   0  green — safe to promote
#   1  red — do NOT merge
#
# Env:
#   TEST_TIMEOUT   seconds allowed for the suite (default 300)
#   BUILD_TIMEOUT  seconds allowed for the APK build (default 900)

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-900}"

# Flutter's test compiler writes a temp dir per test file, and the whole batch
# lands under TMPDIR. Where that points decides whether the suite runs at all.
# On the machine this was built on, /tmp is a 3.6GB tmpfs that other tools also
# use; once it was ~80% full the suite stopped being able to write its listener
# files and simply never finished. It looked exactly like a code hang — the run
# would sit there past any sensible timeout — and cost a long hunt through the
# chart code for a bug that was not there. With TMPDIR on real disk the same
# suite finishes in well under a minute.
#
# So: give the toolchain a temp dir with room, and never let it default to a
# small shared tmpfs.
export TMPDIR="${FLUTTER_TMPDIR:-$PWD/.verify-tmp}"
mkdir -p "$TMPDIR"

# ---------------------------------------------------------------------------
# Reap orphaned testers, on the way in AND on the way out.
#
# This is the actual cause of the /tmp problem, and it is worth writing down
# because it presented as a code bug twice.
#
# When a run here is KILLED BY ITS OWN TIMEOUT, `timeout` kills the `flutter`
# wrapper and leaves `flutter_tester` — the per-file test binary — running. That
# orphan does not exit on its own. It keeps writing 14MB `.so` scratch files
# into /tmp forever, hundreds of them, and `flutter_tester` does not honour
# TMPDIR for them, so redirecting TMPDIR does not save you.
#
# Symptom: /tmp (a 3.6G tmpfs) creeps to 80% full, and then EVERY flutter
# command fails with "Disk quota exceeded" while writing its listener file. That
# reads as a build break and is not one. Deleting the files does not help
# because the orphan recreates them within seconds.
#
# Measured here: one orphan held 1.2GB open, and killing it took /tmp from
# 2.9G-used to 152M-used.
cleanup_testers() {
  pkill -9 -f 'flutter_tester .*daily_companion' 2>/dev/null
  return 0
}
sweep_tmp() {
  # Only this machine's 14MB flutter scratch files, and only when it is a
  # genuine emergency, so this never deletes anything of the user's.
  if [ "$(df -P /tmp | awk 'NR==2 {print $5}' | tr -d '%')" -ge 70 ]; then
    rm -f /tmp/.9adb*.so 2>/dev/null
    rm -rf /tmp/flutter_tools.* 2>/dev/null
  fi
  return 0
}
trap 'cleanup_testers' EXIT
cleanup_testers
sweep_tmp

SKIP_BUILD=0
[ "${1:-}" = "--no-build" ] && SKIP_BUILD=1

# Logs go inside the repo, not /tmp. Redirecting a flutter command's output to
# a /tmp path fails in this environment with exit 255 and a completely empty
# file, which reads as "the tool crashed" rather than "the path is bad" and
# costs a confusing debugging detour. A directory next to the code just works.
LOG_DIR=".verify-logs"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"
FAILED=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

fail() {
  red   "  FAIL: $*"
  FAILED=1
}

# ---------------------------------------------------------------------------
# /tmp is a small shared tmpfs and it fills up.
#
# The Flutter tool leaves ~13MB per test file in the system temp directory, so a
# full suite leaks hundreds of megabytes. TMPDIR above points the test compiler at
# real disk, which is what keeps the SUITE from hanging. It does NOT help Gradle:
# the asset compressor writes through java.io.tmpdir, ignores TMPDIR, and fails
# with "Disk quota exceeded" — an error that reads like a broken build rather
# than a full disk.
#
# So: do not delete anything. /tmp is shared with other tools and their state is
# none of this script's business. Report the headroom instead, and when a build
# fails on a full disk, say that rather than reporting a code failure.
check_tmp_headroom() {
  local available
  available=$(df -m /tmp 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "${available:-}" ] && [ "$available" -lt 512 ]; then
    printf '  /tmp has %s MB free — the build is likely to fail with "Disk quota exceeded"\n' \
      "$available"
    red "    this is a full disk, not a broken build. Free it and re-run:"
    red "      rm -f /tmp/.9adb*.so; rm -rf /tmp/flutter_tools.*"
  fi
}

check_tmp_headroom

# ---------------------------------------------------------------------------
step "1/4  formatting"
# --set-exit-if-changed makes this a check, not a rewrite. A tree that is not
# formatted cannot be promoted, so a formatter run never silently edits the
# thing being verified.
if dart format --output=none --set-exit-if-changed lib test > "$LOG_DIR/fmt.log" 2>&1; then
  green "  files are formatted"
else
  fail "unformatted files — run: dart format lib test"
  head -20 "$LOG_DIR/fmt.log"
fi

# ---------------------------------------------------------------------------
step "2/4  static analysis"
if flutter analyze > "$LOG_DIR/analyze.log" 2>&1; then
  green "  no issues"
else
  fail "flutter analyze reported issues"
  grep -E '^\s+(error|warning|info)' "$LOG_DIR/analyze.log" | head -20
fi

# ---------------------------------------------------------------------------
step "3/4  test suite  (limit ${TEST_TIMEOUT}s)"
# The limit is the whole point. Without it a hang is indistinguishable from a
# slow run; with it, exit 124 is a red gate rather than an afternoon lost.
timeout "${TEST_TIMEOUT}" flutter test --reporter=failures-only \
  > "$LOG_DIR/test.log" 2>&1
TEST_EXIT=$?

if [ "$TEST_EXIT" -eq 0 ]; then
  green "  all tests passed"
elif [ "$TEST_EXIT" -eq 124 ]; then
  fail "the suite did not finish within ${TEST_TIMEOUT}s — it hung"
  red   "  a hang is not a pass. Isolate it per file:"
  red   "    for f in test/*_test.dart; do"
  red   "      timeout 90 flutter test \"\$f\" --reporter=failures-only >/dev/null 2>&1"
  red   "      echo \"\$f -> exit=\$?\""
  red   "    done"
  red   "  exit=124 identifies the hanging file."
else
  fail "tests failed (exit ${TEST_EXIT})"
  grep -E 'Expected:|Actual:|Which:|\[E\]' "$LOG_DIR/test.log" | head -20
fi

# ---------------------------------------------------------------------------
if [ "$SKIP_BUILD" -eq 0 ]; then
  step "4/4  debug APK  (limit ${BUILD_TIMEOUT}s)"
  check_tmp_headroom
  if timeout "${BUILD_TIMEOUT}" flutter build apk --debug \
      > "$LOG_DIR/build.log" 2>&1; then
    green "  build succeeded"
  elif grep -q 'Disk quota exceeded' "$LOG_DIR/build.log"; then
    fail "the build failed because /tmp is full, not because of the code"
    red   "  Gradle's asset compressor ignores TMPDIR. Free /tmp and re-run:"
    red   "    rm -f /tmp/.9adb*.so; rm -rf /tmp/flutter_tools.*"
  else
    fail "flutter build apk --debug failed or timed out"
    tail -20 "$LOG_DIR/build.log"
  fi
else
  step "4/4  debug APK — skipped (--no-build)"
  red   "  note: a skipped build is not a full green light"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$FAILED" -eq 0 ]; then
  green "GREEN — safe to promote this branch to master"
  if [ "$SKIP_BUILD" -ne 0 ]; then
    red   "  but the build was skipped; run without --no-build before merging"
  fi
  exit 0
fi

red "RED — do not merge. Logs kept in $LOG_DIR"
exit 1
