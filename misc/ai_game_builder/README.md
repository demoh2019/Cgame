# AI Game Builder (Godot 4)

An optional Godot editor plugin that builds small self-contained games from natural-language prompts through an OpenAI-compatible chat-completions API. The add-on is intentionally separated from the engine core so that it can be developed and tested independently.

## Installation

1. Copy the directory addons/ai_game_builder from this folder into YOUR Godot project's addons/ directory. The plugin config must be at res://addons/ai_game_builder/plugin.cfg.
2. Open Project > Project Settings > Plugins and enable AI Game Builder.
3. Find the AI Game Builder dock in the editor. Supply your chat-completions API endpoint, model name, and an API key if your provider requires one.
4. Describe the game and click Generate.
5. Carefully read all generated files in the preview. Click Apply files... and confirm to write them.
6. Open the scene res://ai_generated/main.tscn and run it with F6.

A compatible default endpoint is https://api.openai.com/v1/chat/completions. A local model server is also supported, for example http://127.0.0.1:1234/v1/chat/completions. The model name is configurable.

The API key is held only in the dock's memory. This plugin does not persist it.

## Safety limits

- AI only returns candidate text files. It cannot execute commands, edit existing files, install packages, or make arbitrary changes to engine settings.
- No output is written until the preview is accepted. Existing paths are never overwritten.
- Only safe ASCII relative file paths within res://ai_generated/ are allowed.
- Allowed file types: .gd, .tscn, .tres, .gdshader, .json, .md, .txt.
- Up to 16 files, 64 KiB each, 256 KiB total, and a 1 MiB HTTP response body.
- Only HTTPS remote providers or HTTP loopback endpoints are allowed. Redirects are disabled.
- Generated GDScript may be incorrect or unsafe; inspect before running. The MVP does not compile generated scripts, run generated scenes, implement retries, or promise the generated game works.

## Testing

Run the standalone test project (this folder) from the source checkout:

    godot --headless --path misc/ai_game_builder --script res://tests/run.gd

The suite includes successful and rejected plans, JSON parsing, provider reply handling, path traversal prevention, sizes, duplicates, creation, and overwrite prevention. The writer tests create and remove a temporary file in the standalone project. Do not execute these tests from a production Godot project.

## Suggested follow-up milestones

1. Build headless validation for generated scripts and scenes, with opt-in repair loops.
2. Add agent planning and scoped tools for selected scenes/scripts, using diffs, backups, undo, and explicit approval.
3. Implement game templates, reusable mechanics, 2D/3D level generation, terrain, and procedural content.
4. Integrate asset generation from approved image, mesh, audio, and animation providers.
5. Add local inference and caching, request cancellation and budgets, performance tests, and CI.

This MVP deliberately does not claim universal AI-driven game creation. It is a tested architectural starting point for that goal.
