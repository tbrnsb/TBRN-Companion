#!/usr/bin/env bash
#
# Why /tmp keeps filling up on this machine, and the one-line fix.
#
# THE CAUSE. A `flutter test` run that is killed by its own timeout leaves
# `flutter_tester` — the per-file test binary — running as an orphan. `timeout`
# kills the `flutter` wrapper and not that child. The orphan never exits. It
# writes 14MB `.so` scratch files into /tmp continuously, and because
# `flutter_tester` does not route those through TMPDIR, exporting TMPDIR does
# nothing about them.
#
# WHY IT LOOKED LIKE SOMETHING ELSE. /tmp here is a 3.6G tmpfs. Once it passes
# about 80% full, every flutter command dies with:
#
#     FileSystemException: writeFrom failed, path =
#     '/tmp/flutter_tools.XXXX/flutter_test_listener.YYY/listener.dart.dill'
#     (OS Error: Disk quota exceeded, errno = 122)
#
# which reads as a broken project. It is not: the code compiles, and the same
# suite passes a minute later once the space is back. Deleting the .so files by
# hand does not hold, because the orphan recreates them within seconds.
#
# THE FIX, in order of how often you need it:
#
#   1. tool/doctor-tmp.sh          # diagnose and clean, safe to run any time
#   2. tool/doctor-tmp.sh --kill   # also kill the orphans (the real fix)
#
# `tool/verify.sh` now reaps orphans on entry and on exit, so the gate does not
# create this any more. Use it rather than bare `flutter test`.

set -uo pipefail

KILL=0
[ "${1:-}" = "--kill" ] && KILL=1

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }

used_pct() { df -P /tmp | awk 'NR==2 {print $5}' | tr -d '%'; }
free_mb()  { df -Pm /tmp | awk 'NR==2 {print $4}'; }

echo
echo "== /tmp =="
info "filesystem: $(df -Ph /tmp | awk 'NR==2 {print $1}')"
info "used:       $(used_pct)%   free: $(free_mb)MB"

# --- the orphans -----------------------------------------------------------
ORPHANS=$(pgrep -f 'flutter_tester' 2>/dev/null | wc -l)
if [ "$ORPHANS" -gt 0 ]; then
  red "$ORPHANS orphaned flutter_tester process(es) — this is the cause"
  pgrep -al flutter_tester 2>/dev/null | head -3 | while read -r _ rest; do
    info "${rest:0:80}..."
  done
  if [ "$KILL" -eq 1 ]; then
    pkill -9 -f flutter_tester 2>/dev/null
    sleep 1
    grn "killed. re-run this script to confirm."
  else
    info "fix with:  tool/doctor-tmp.sh --kill"
  fi
else
  grn "no orphaned testers"
fi

# --- the scratch files -----------------------------------------------------
COUNT=$(ls /tmp/.9adb*.so 2>/dev/null | wc -l)
if [ "$COUNT" -gt 0 ]; then
  info "$COUNT flutter scratch files (.so) in /tmp, $(du -ch /tmp/.9adb*.so 2>/dev/null | tail -1 | cut -f1)"
  info "if nothing is running, these are leftovers and are safe to delete"
  if [ "$KILL" -eq 1 ] || [ "$ORPHANS" -eq 0 ]; then
    rm -f /tmp/.9adb*.so 2>/dev/null
    rm -rf /tmp/flutter_tools.* 2>/dev/null
    grn "swept."
  fi
else
  grn "no scratch files"
fi

# --- space held by unlinked files -----------------------------------------
HELD=$(bash -c 'tot=0; for p in /proc/[0-9]*; do for f in $p/fd/*; do t=$(readlink "$f" 2>/dev/null); case "$t" in *"(deleted)"*) s=$(stat -L -c %s "$f" 2>/dev/null || echo 0); tot=$((tot+s));; esac; done; done; echo $tot' 2>/dev/null)
if [ "${HELD:-0}" -gt 104857600 ]; then
  info "$((HELD/1024/1024))MB is held by DELETED-but-open files."
  info "space only returns when the holding process exits. restart the shell"
  info "and the app holding them if it stays this high."
fi

echo
info "free now: $(free_mb)MB   used: $(used_pct)%"
echo
