#!/bin/bash
# Starts a real dedicated server and real clients (all headless processes) and checks the game end to end.
#   game/tests/e2e/run_e2e.sh path/to/godot
GODOT="${1:-./bin/godot.macos.editor.arm64}"
PORT="${2:-24590}"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="${TMPDIR:-/tmp}/albion_e2e"
mkdir -p "$LOG"
cd "$HERE" || exit 2

"$GODOT" --headless --path . --script res://scripts/server/server_main.gd -- --port "$PORT" --seed 1337 --debug-commands --quit-after 300 > "$LOG/server.log" 2>&1 &
SERVER=$!
sleep 3
fail=0
run_bot() { # name scenario
  "$GODOT" --headless --path . --script res://tests/e2e/bot_client.gd -- --scenario "$2" --name "$1" --port "$PORT" > "$LOG/$1.log" 2>&1
}
run_bot Solo solo &
SOLO=$!
run_bot Victim victim &
VICTIM=$!
sleep 4
run_bot Killer killer &
KILLER=$!
for pid in $SOLO $VICTIM $KILLER; do
  wait $pid || fail=1
done
# The skill tree run is alone on the server, so the other bots cannot interfere with its checks.
run_bot Skiller skills || fail=1
kill $SERVER 2>/dev/null
wait $SERVER 2>/dev/null
# A bot that never ran (parse error, crash) must not count as a pass: demand its PASS line.
grep -q "SERVER listening" "$LOG/server.log" || { echo "the server never started"; fail=1; }
for name in Solo Victim Killer Skiller; do
  if grep -q "^BOT $name PASS" "$LOG/$name.log"; then
    grep -E "^BOT $name" "$LOG/$name.log"
  else
    echo "BOT $name did not report PASS"
    fail=1
  fi
done
grep -E "CHECK FAILED|SCRIPT ERROR" "$LOG"/*.log
if [ $fail -eq 0 ]; then echo "E2E PASSED"; else echo "E2E FAILED (logs in $LOG)"; fi
exit $fail
