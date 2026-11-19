#!/usr/bin/env bash
# End-to-end test of the MCP server: usage tests/e2e.sh /path/to/godot
set -euo pipefail
GODOT=${1:?usage: e2e.sh /path/to/godot}
SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'kill "$PID" 2>/dev/null || true; rm -rf "$WORK"' EXIT
cp -R "$SRC/project.godot" "$SRC/addons" "$SRC/sample" "$WORK/"
PORT=$((20000 + RANDOM % 20000))
"$GODOT" --headless --path "$WORK" --script res://addons/godot_agent/serve.gd -- --port "$PORT" --token s3cret >"$WORK/server.log" 2>&1 &
PID=$!
for _ in $(seq 1 100); do
	curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/mcp" && break
	sleep 0.1
done

fails=0
rpc() { curl -s -m 120 -X POST "http://127.0.0.1:$PORT/mcp" -H 'content-type: application/json' -H 'authorization: Bearer s3cret' -d "$1"; }
tool() { rpc "$(jq -nc --arg n "$1" --argjson a "${2:-{\}}" '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$n,arguments:$a}}')" | jq -r '.result.content[0].text'; }
expect() { # expect <description> <haystack> <needle>
	if [[ "$2" != *"$3"* ]]; then echo "FAIL $1: wanted '$3' in:"; echo "$2"; fails=$((fails + 1)); else echo "ok   $1"; fi
}

# Security: token required, GET refused, foreign origin refused.
[[ $(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/mcp" -d '{}') == 401 ]] && echo "ok   token required" || { echo "FAIL token"; fails=$((fails + 1)); }
[[ $(curl -s -o /dev/null -w '%{http_code}' -H 'authorization: Bearer s3cret' "http://127.0.0.1:$PORT/mcp") == 405 ]] && echo "ok   GET refused" || { echo "FAIL GET"; fails=$((fails + 1)); }
[[ $(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'origin: https://evil.example' -H 'authorization: Bearer s3cret' "http://127.0.0.1:$PORT/mcp" -d '{}') == 403 ]] && echo "ok   foreign origin refused" || { echo "FAIL origin"; fails=$((fails + 1)); }

# Protocol.
init=$(rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
expect "initialize" "$init" '"godot-agent"'
expect "instructions sent once" "$init" "edit ops"
list=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
expect "tools/list" "$list" '"run"'
size=$(echo -n "$list" | wc -c)
[[ $size -lt 3500 ]] && echo "ok   tools/list is $size bytes" || { echo "FAIL tools/list too large: $size"; fails=$((fails + 1)); }
[[ -z $(rpc '{"jsonrpc":"2.0","method":"notifications/initialized"}') ]] && echo "ok   notification has no body" || { echo "FAIL notification"; fails=$((fails + 1)); }

# Tools.
expect "project" "$(tool project)" "main=res://sample/main.tscn"
expect "api" "$(tool api '{"class":"Node2D"}')" "position:Vector2"
expect "outline" "$(tool outline '{"scene":"sample/main.tscn"}')" "speed=200.0"
out=$(tool edit '{"scene":"sample/level.tscn","ops":"root Node2D Level\n+ Mover Node2D script=res://sample/mover.gd speed=300\n+ Player CharacterBody2D position=100,200\n+ Player/Col CollisionShape2D shape=new:RectangleShape2D shape.size=32,48\n+ Bad Nope\n~ Player nothere=1"}')
expect "edit applied" "$out" "ok 6 ops, 4 nodes"
expect "edit reports bad type" "$out" "unknown type 'Nope'"
expect "edit reports bad prop" "$out" "no property 'nothere'"
expect "scene saved" "$(tool outline '{"scene":"sample/level.tscn"}')" "Col:CollisionShape2D"
expect "write ok" "$(tool write '{"path":"sample/p.gd","content":"extends Node\nvar a := 1\n"}')" "ok res://sample/p.gd"
expect "write reports parse errors" "$(tool write '{"path":"sample/q.gd","content":"extends Node\nfunc f(:\n"}')" "res://sample/q.gd:"
expect "patch" "$(tool write '{"path":"sample/p.gd","old":"a := 1","new":"a := 2"}')" "ok"
expect "read lines" "$(tool read '{"path":"sample/p.gd","lines":"2-2"}')" "2|var a := 2"
expect "path escape refused" "$(tool write '{"path":"../evil.gd","content":"x"}')" "ERR bad path"
expect "project.godot protected" "$(tool write '{"path":"project.godot","content":"x"}')" "ERR bad path"
expect "setting" "$(tool setting '{"ops":"action go Right D\nmain res://sample/level.tscn"}')" "ok 2 ops"
expect "check finds errors" "$(tool check)" "q.gd"
out=$(tool run '{"scene":"sample/level.tscn","frames":60,"inputs":"ui_right@0-60","expect":"get_node(\"Mover\").position.x > 100\nget_node(\"Mover\").position.x < 1","watch":"get_node(\"Mover\").position"}')
expect "run pass" "$out" 'PASS get_node("Mover").position.x > 100'
expect "run fail" "$out" 'FAIL get_node("Mover").position.x < 1'
expect "run watch" "$out" 'get_node("Mover").position = '

if [[ $fails -gt 0 ]]; then echo "$fails FAILED"; tail -20 "$WORK/server.log"; exit 1; fi
echo "all passed"
