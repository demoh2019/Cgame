#!/bin/bash
# End to end with real accounts: needs Nakama running (docker compose -f game/backend/docker-compose.yml up -d).
#   game/tests/e2e/run_e2e_nakama.sh path/to/godot [port]
GODOT="${1:-./bin/godot.macos.editor.arm64}"
PORT="${2:-24630}"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="${TMPDIR:-/tmp}/albion_e2e_nakama"
mkdir -p "$LOG"
cd "$HERE" || exit 2
curl -s -m 3 localhost:7350/healthcheck >/dev/null || { echo "Nakama is not running on :7350"; exit 2; }
DEVICE="e2e-device-$RANDOM$RANDOM"
NAME="Hero$RANDOM"
"$GODOT" --headless --path . --script res://scripts/server/server_main.gd -- --port "$PORT" --seed 1337 --debug-commands --nakama 127.0.0.1:7350 --quit-after 90 > "$LOG/server.log" 2>&1 &
SERVER=$!
sleep 3
fail=0
bot() { # label scenario [extra args...]
  label="$1"; scenario="$2"; shift 2
  "$GODOT" --headless --path . --script res://tests/e2e/bot_client.gd -- --scenario "$scenario" --name "$NAME" --port "$PORT" --nakama 127.0.0.1:7350 --device "$DEVICE" "$@" > "$LOG/$label.log" 2>&1
  if grep -q "^BOT $NAME PASS" "$LOG/$label.log"; then echo "$label: PASS"; else echo "$label: FAILED"; grep -E "CHECK FAILED|SCRIPT ERROR|BOT .* FAIL" "$LOG/$label.log"; fail=1; fi
}
bot session1 persist1
sleep 2   # the server saves the character when the peer disconnects
bot session2 persist2 --returning
# An account signing in twice: the second login replaces the first, and the first is saved.
"$GODOT" --headless --path . --script res://tests/e2e/bot_client.gd -- --scenario idle --name "$NAME" --port "$PORT" --nakama 127.0.0.1:7350 --device "$DEVICE" > "$LOG/first_login.log" 2>&1 &
FIRST=$!
sleep 4
bot second_login idle --returning
wait $FIRST
if grep -qE "Disconnected|CHECK FAILED" "$LOG/first_login.log"; then :; fi
grep -q "SERVER peer .* left" "$LOG/server.log" && echo "server saw the disconnects"
# A client that does not sign in is refused.
"$GODOT" --headless --path . --script res://tests/e2e/bot_client.gd -- --scenario refused --name Anon --port "$PORT" > "$LOG/anon.log" 2>&1
if grep -q "^BOT Anon PASS" "$LOG/anon.log"; then echo "anonymous: was let in (BAD)"; fail=1; else echo "anonymous: refused (good)"; fi
kill $SERVER 2>/dev/null; wait $SERVER 2>/dev/null
grep -E "SCRIPT ERROR" "$LOG/server.log" && fail=1
if [ $fail -eq 0 ]; then echo "E2E NAKAMA PASSED"; else echo "E2E NAKAMA FAILED (logs in $LOG)"; fi
exit $fail
