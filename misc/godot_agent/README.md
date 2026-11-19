# Godot Agent: token-lean MCP server for AI game building

A single drop-in addon that lets any MCP-capable coding agent (Claude Code, Cursor, Codex, …)
inspect, edit, check and *play-test* a Godot project through nine small tools. It is designed
around one goal: **the model gets full access to the engine with as few tokens as possible**.

No editor, GUI or API key is needed; it runs on any Godot 4.x binary (including this fork's
build) in `--headless` mode and listens on `127.0.0.1` only.

## Quick start

```sh
# 1. copy the addon into your game project
cp -R misc/godot_agent/addons/godot_agent  <your-project>/addons/

# 2. start the server (keep it running)
godot --headless --path <your-project> --script res://addons/godot_agent/serve.gd -- --port 7777 --token SECRET

# 3. register it with your agent, for example Claude Code:
claude mcp add --transport http godot http://127.0.0.1:7777/mcp --header "Authorization: Bearer SECRET"
```

`--token` is optional but recommended: tools write files and run project scripts.
Requests carrying a foreign `Origin` header are rejected, `GET` is refused, and every path is
confined to the project (no `..`, no hidden folders, `project.godot` only via the `setting` tool).

## Tools

| tool | purpose | typical output |
|---|---|---|
| `project` | settings, autoloads, input actions, collision layers, compact file tree | ~100 tokens |
| `api` | engine class reference straight from `ClassDB` (never stale, never guessed) | `P`roperties / `M`ethods / `V`irtuals / `S`ignals / `K`onstants, own members only by default |
| `outline` | scene tree with non-default properties, no instantiation | one line per node |
| `edit` | create/modify scenes with a line-based DSL | `ok 6 ops, 4 nodes` + only the failed lines |
| `read` / `write` | read ranges, write files, or patch with a unique `old`→`new` | `.gd` writes are parse-checked and return `file:line` errors |
| `setting` | project settings, main scene, autoloads, input actions, layer names | `ok N ops` |
| `check` | parse-check every script and load-check every scene in one child process | `ok 12 files` or `file:line message` |
| `run` | play a scene headless for N frames with scripted input and assertions | `PASS`/`FAIL expr => value`, game `print()` output, condensed errors |

### Scene DSL (sent once in the MCP `instructions`)

```
root Node2D Level
+ Player CharacterBody2D position=100,200 groups=player
+ Player/Col CollisionShape2D shape=new:RectangleShape2D shape.size=32,48
+ Player/Sprite Sprite2D texture=res://icon.svg modulate=#ff8800 scale=0.5,0.5
+ HUD/Score Label text="Score: 0" horizontal_alignment=Center
+ Enemy @res://enemy.tscn position=300,100
~ Player script=res://player.gd speed=250
conn Player died HUD _on_died
- OldNode          mv Node NewParent          rename Node NewName
```

Values are typed from the target property: `10,20` for vectors, `#rrggbb` or names for colors,
enum **names**, `res://` paths load resources, `new:Class` creates sub-resources and
`prop.sub=value` configures them. Unknown types, missing properties and bad values are reported
per line while the valid lines are still applied, so the model only re-sends what failed.

### Play-testing without screenshots

```
run scene=level.tscn frames=120 inputs="ui_right@0-60 jump@30-31"
    expect="get_node('Player').position.x > 150
            get_node('Player').is_on_floor()"
    watch="get_node('HUD/Score').text"
```

The scene runs on the real engine at a fixed 60 fps without rendering, input is injected as
actions, and each `expect` line is a GDScript expression evaluated on the scene root. The model
sees a handful of lines instead of images, which is what keeps the automatic
write → check → run → fix loop cheap.

## Why it is cheap

* `tools/list` is under 3.5 KB and the DSL cheat sheet (≈250 tokens) is delivered once in the
  `initialize` instructions, not repeated per call.
* Outputs are line-oriented text, not JSON: no keys repeated per node, only non-default
  properties, accessor methods hidden when a property already covers them, lists capped with a
  `…+N (narrow with q=)` hint.
* Batch operations: one `edit` call can build a whole scene; `check` validates the whole project
  in one process; `run` returns assertions instead of logs. Engine log noise is condensed to
  deduplicated `file:line message` lines and engine-internal locations are mapped to the script
  frame that raised them.
* `api` answers from the running binary, so the model neither burns tokens on documentation
  searches nor hallucinates members that do not exist in this engine build.

## Tests

```sh
godot --headless --path misc/godot_agent --script res://tests/test_common.gd   # DSL/value unit tests
misc/godot_agent/tests/e2e.sh /path/to/godot                                   # MCP protocol + all tools
```

## Limits and notes

* Child processes (`check`, `run`) execute project scripts. They are killed after a timeout, but
  treat the server like a local development tool, not a sandbox.
* Assertions need a headless-compatible scene (no GPU readback). Pixel-level checks and
  screenshots are not part of this addon yet.
* The server is single-threaded and handles one request at a time.
* It edits files on disk. If the Godot editor has the same project open, reload scenes after edits.
