# AI Game Builder (Godot 4)

An optional Godot editor plugin that builds small self-contained games from natural-language prompts through an OpenAI-compatible chat-completions API. The add-on is intentionally separated from the engine core so that it can be developed and tested independently.

## Installation

1. Copy the directory addons/ai_game_builder from this folder into YOUR Godot project's addons/ directory. The plugin config must be at res://addons/ai_game_builder/plugin.cfg.
2. Open Project > Project Settings > Plugins and enable AI Game Builder.
3. Find the AI Game Builder dock in the editor. Supply your chat-completions API endpoint, model name, and an API key if your provider requires one.
4. Click **Instant 2D Starter (Offline)** to prepare a playable arcade game immediately without a model or API key, or describe your own game and click **Generate** to use an AI provider.
5. The built-in static inspector checks for a main scene and broken or external resource paths. When it flags errors, click **Repair** to request a complete replacement from the model. You can also enter a change request (for example, `Add a boss fight`) and click **Refine** to evolve the current preview without losing the original description. Each click makes another API request and can incur usage costs.
6. Carefully read all generated files in the preview, including security warnings. Click **Apply files...** and confirm to write them.
7. Open the scene res://ai_generated/main.tscn and run it with F6.

A compatible default endpoint is https://api.openai.com/v1/chat/completions. A local model server is also supported, for example http://127.0.0.1:1234/v1/chat/completions. The model name is configurable.

The API key is held only in the dock's memory. This plugin does not persist it.

## Product focus: fast, reliable game creation

AI Game Builder is the highest-priority product workflow in Cgame. The
immediate goal is a **repeatable prompt → review → check → repair → approve**
cycle for a playable prototype, not uncontrolled autonomous code execution.

Provider connection safety is part of that workflow. The endpoint validator
accepts HTTPS with a syntactically valid hostname, and HTTP only for the
exact loopback hostnames `localhost`, `127.0.0.1`, and `[::1]`. It rejects
URL userinfo, host-prefix spoofing such as
`http://localhost:1234@other-server`, invalid ports, fragments,
backslashes, and control characters. API keys remain in memory and cannot
contain header-control characters. The URL validation is not a full
network-isolation sandbox; review any custom HTTPS endpoint before sending
your prompt or key.

Generated files must also have portable names (including Windows device-name
rules); the writer rechecks output paths before each file operation. This
reduces accidental overwrites and common symlink redirects, but malicious
concurrent filesystem races require operating-system sandboxing.

The standalone test suite includes endpoint policy, credentials/header,
reserved filename, and multi-file no-overwrite regression cases.

## Instant playable arcade starter (no network required)

AI Game Builder includes a bundled 2D collection game under
`addons/ai_game_builder/templates/arcade_2d/`. It reuses and adapts the
offline template developed in Cgame PR #74 without introducing a second plugin.

Use **Instant 2D Starter (Offline)** from the existing AI dock to prepare a
3-file game plan with `main.tscn`, `scripts/arcade.gd` and `README.md`.
The starter includes blue player movement (WASD and arrows), a moving green
collectible, a 60-second timer, a ten-point goal, and restart with R. The
scene and script require no external images, sound, services or downloaded
packages. It can later be refined through the normal AI model workflow.

The starter runs through exactly the same path validation, static inspection,
review/confirmation, and file writer as an AI-generated plan. **Nothing is
written when clicking the starter button.** Applying the files still requires
approval, refuses overwriting files, and works best in a new/empty project.

The automated suite validates its content, paths and dependencies, writes a
temporary copy in the disposable test project, uses Godot's actual resource
loader to check the scene and GDScript, rejects a second write and cleans up.

## Check approved games with Godot (headless)

After you click **Apply files...** and explicitly approve the generated files,
the AI Game Builder dock offers **Check Game (Headless)**. This is an
**opt-in** quality check — it does not run when a plan is generated or saved.

The editor launches its own Godot executable as a separate headless process
and asks it to inspect **only the newly approved files**. The check:

- Confirms paths are limited to `res://ai_generated/`, files are present
  and readable, filenames are portable, and files are within size limits.
- Uses Godot's actual resource loader on approved GDScript, `.tscn`,
  `.tres` and shader resources; checks JSON game data with Godot's JSON parser.
- Does **not** instantiate the generated `PackedScene`, start gameplay,
  or automatically ask the provider to fix or overwrite files.
- Displays a bounded error list in the dock; the user can use it as context
  for a subsequent AI repair request. The first version does not yet
  automatically apply repairs to already-created files.
- Runs outside the editor process and has a **30-second timeout**,
  a Cancel action, and automatic cleanup of the JSON report saved under
  `user://ai_game_builder/`. No shell invocation or extra API request is used.

**Trust boundary:** loading game resources can still trigger parsing,
importers or dependencies, and a malicious script might have side effects.
Review the AI-generated files first and use an OS sandbox or VM for fully
untrusted content. Timeout is not a full process/security sandbox.
This check verifies *loading and compilation*, not game mechanics,
playability, performance, physics, networking, or visual correctness.

The headless checker is also available from the command line, after you
have explicitly reviewed and created a game in a disposable project:

```sh
godot --headless --path /path/to/project \
  --script res://addons/ai_game_builder/smoke_check.gd \
  -- --report user://ai_game_builder/manual_report.json \
  --paths '["res://ai_generated/main.tscn","res://ai_generated/player.gd"]'
```

Exit code 0 means loaded successfully, 1 reports resource/validation errors,
and 2 reports invocation or diagnostic-write errors. The report file is
JSON with `ok`, `checked` and `errors` fields. An exit code of 0 is not
a guarantee of a working game.

CI executes both this real subprocess check and headless tests of the
validation rules, after creating disposable fixtures. No generated game is
published or distributed by these tests.

## Safety limits

- AI only returns candidate text files. It cannot execute commands, edit existing files, install packages, or make arbitrary changes to engine settings.
- No output is written until the preview is accepted. Existing paths are never overwritten.
- Only safe ASCII relative file paths within res://ai_generated/ are allowed. Pre-existing symlinks in the output path are rejected.
- Allowed file types: .gd, .tscn, .tres, .gdshader, .json, .md, .txt.
- Up to 16 files, 64 KiB each, 256 KiB total, and a 1 MiB HTTP response body.
- Only HTTPS remote providers or HTTP loopback endpoints are allowed. Redirects are disabled.
- A non-executing static inspector blocks plans missing `main.tscn`, lacking its scene header, or using missing/external `res://` dependencies. It also blocks generated `@tool` scripts and basic process-spawning patterns, and warns about file I/O or network-related APIs. These are **heuristics**, not a full parser or malware sandbox, and can produce false positives or miss problems.
- **Repair** requests one replacement plan from model diagnostics; **Refine** requests a replacement that follows your additional instructions. Neither action automatically loops or writes to disk. Each attempt has provider costs.
- Generated GDScript may still be incorrect or unsafe; inspect before running. The MVP does not compile generated scripts or execute generated scenes, and cannot promise a functional game.

## Testing

Run the standalone test project (this folder) from the source checkout:

    godot --headless --path misc/ai_game_builder --script res://tests/run.gd

The suite includes up to 103 assertions for successful and rejected plans, JSON parsing, provider reply handling, path traversal prevention, size limits, duplicates, generated dependencies, repair context, script loading, creation, and overwrite prevention. The writer tests create and remove a temporary file in the standalone project. Do not execute these tests from a production Godot project.

## Suggested follow-up milestones

1. Build isolated headless Godot compilation/smoke checks for generated scripts and scenes, with an opt-in capped iterative repair loop.
2. Add agent planning and scoped tools for selected scenes/scripts, using diffs, backups, undo, and explicit approval.
3. Implement game templates, reusable mechanics, 2D/3D level generation, terrain, and procedural content.
4. Integrate asset generation from approved image, mesh, audio, and animation providers.
5. Add local inference and caching, request cancellation and budgets, performance tests, and CI.

This MVP deliberately does not claim universal AI-driven game creation. It is a tested architectural starting point for that goal.
