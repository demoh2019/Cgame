# AI Game Builder (Godot 4)

An optional Godot editor plugin that builds small self-contained games from natural-language prompts through an OpenAI-compatible chat-completions API. The add-on is intentionally separated from the engine core so that it can be developed and tested independently.

## Installation

1. Copy the directory addons/ai_game_builder from this folder into YOUR Godot project's addons/ directory. The plugin config must be at res://addons/ai_game_builder/plugin.cfg.
2. Open Project > Project Settings > Plugins and enable AI Game Builder.
3. Find the AI Game Builder dock in the editor. Supply your chat-completions API endpoint, model name, and an API key if your provider requires one.
4. Describe the game and click Generate.
5. The built-in static inspector checks for a main scene and broken or external resource paths. When it flags errors, click **Repair** to request a complete replacement from the model. You can also enter a change request (for example, `Add a boss fight`) and click **Refine** to evolve the current preview without losing the original description. Each click makes another API request and can incur usage costs.
6. Carefully read all generated files in the preview, including security warnings. Click **Apply files...** and confirm to write them.
7. Open the scene res://ai_generated/main.tscn and run it with F6.

A compatible default endpoint is https://api.openai.com/v1/chat/completions. A local model server is also supported, for example http://127.0.0.1:1234/v1/chat/completions. The model name is configurable.

The API key is held only in the dock's memory. This plugin does not persist it.

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
