# AI Game Builder (Godot 4.8 prototype)

An optional Godot editor addon for generating **small game prototypes, scenes, scripts, shaders and design documents** from natural-language requests. A single model request proposes a set of source files; **nothing is written until the developer reviews and clicks Apply**.

## Instant offline arcade starter

The editor dock includes **Preview offline 2D starter (no API key)**. Click it to load a bundled, working-style Godot 2D arcade game into the regular review panel without contacting any model. Inspect the files and click Apply to create them under `res://ai_generated/`. Open the main scene and press F6 to play. Move with WASD/arrows, collect ten green squares in 60 seconds, and press R to restart. You can use **Improve current draft** to send the starter to AI for further development, after entering an API key.

## Instant offline 3D arena starter

Click **Preview offline 3D starter (no API key)** in the dock. It produces three
reviewable files: a Node3D entry scene, a standalone GDScript controller, and a
README. Apply only after inspecting the proposed files, then open
`res://ai_generated/scenes/main.tscn` and press **F6**.

The starter builds a visible 3D arena from BoxMesh primitives, sunlight and
an overhead camera. Move with WASD or arrow keys and collect six green targets
within 90 seconds; R restarts a completed round. It does not require imported
assets, a custom InputMap, an API key, networking or any other plugin. As with
the 2D starter, nothing is automatically written or executed during preview.
Applying either starter does **not** overwrite existing generated files, so a
new starter is best applied to a clean project.

CI stages both offline starters into **separate clean projects** and runs Godot
headlessly to check scene imports and runtime script errors. The 3D tests also
instantiate the scene and check procedural objects, scoring, victory and timeout.
These are bundled trusted templates, **not** unreviewed model output.

## Setup

1. Copy `addons/ai_game_builder` into your Godot project's `res://addons/ai_game_builder`.
2. In Godot, enable **Project > Project Settings > Plugins > AI Game Builder**.
3. Open the **AI Game Builder** editor dock, enter an OpenAI API key and a compatible Chat Completions model (default `gpt-4.1-mini`).
4. Choose 2D game, 3D game, scene, scripts/mechanics or game design document; describe what to build.
5. Click **Generate**, review each proposed file with the file picker, then click **Apply reviewed files**.
6. Open `res://ai_generated/scenes/main.tscn` if a game scene was generated. Run the scene from the editor. Configure a project main scene yourself if desired.

The root of this directory is also a minimal Godot project, so you can open it directly to try the plugin.

## Safety and limitations

- The API key is held in the dock's masked input for the current session, **not saved** in Godot project files. Network requests go only to `https://api.openai.com/v1/chat/completions`. The task text and system instructions go to the provider; existing project files are **not uploaded**.
- Output is JSON validated before preview and before application, including checks for references to missing generated resources (static paths only): at most 20 text files, allowed resource extensions, ASCII safe relative paths, size limits, case-insensitive duplicate rejection, no `@tool` scripts.
- Output goes only under `res://ai_generated/`; existing files are not overwritten. A directory/write failure rolls back newly written files where possible. Generated code should still be reviewed before running: it is **not sandboxed**.
- This prototype creates code, scenes and simple procedural visuals, **not** trained AI models, 3D meshes, voices, audio recordings or production-quality game assets.
- The model may produce incorrect code or references. There is currently no automatic syntax repair, compiler feedback loop, scene execution, model-switching router, offline local model, multi-file refactoring or image generation.
- Large games should be built iteratively, in small reviewed steps. The current implementation makes one bounded generation request and does not automatically modify existing scenes/scripts.

## Headless validation tests

With a Godot 4.8 executable available:

```sh
godot --headless --path misc/ai_game_builder --script res://tests/test_validator.gd
```

From inside this directory instead:

```sh
godot --headless --path . --script res://tests/test_validator.gd
```

The tests cover path traversal, unsafe names, extensions, duplicate files, malformed API responses, oversized output, forbidden tool scripts, valid payloads and provider errors. These tests do **not** require an API key or network access.



## Pre-apply quality gate and bounded AI repair

The addon now reviews generated scene (.tscn) and resource (.tres) headers, looks for scene nodes, validates .json, checks basic SVG and shader structure, and requires a main scene for game prompts. This is **static inspection only**, not a Godot compiler or runtime test; do not run untrusted code without review. Validation errors block applying a draft.

**Auto-repair invalid AI output** is enabled by default and may make up to **two extra paid API requests** per Generate/Improve operation. Uncheck the option to disable retries. Each retry starts from the original task and includes a bounded fragment of the rejected model reply plus the validation error. Failed replies do not replace a previously valid draft.

## Iterative improvement and optional project context

Before applying a generated draft, type feedback in **What should AI improve?** and click **Improve current draft**. The model receives the entire proposed draft and returns an updated full file list. You can repeat this until you are satisfied, then inspect individual files and apply once. If the request fails, the last valid draft remains available.

Project context sharing is **disabled by default**. Enable the checkbox and explicitly list up to 8 non-sensitive project text files, one path per line (such as `res://scenes/main.tscn`). Each file is capped at 16 KiB, with a 64 KiB total limit. Hidden/credential-looking files, addons, generated outputs and symlinks are blocked. Never select private keys or personal data. The selected file contents are sent to the configured AI provider; they are not modified by the addon. This is context for generation, **not permission to edit existing files**.

## Automated tests

```sh
godot --headless --path misc/ai_game_builder --script res://tests/test_validator.gd
godot --headless --path misc/ai_game_builder --script res://tests/test_context.gd
godot --headless --path misc/ai_game_builder --script res://tests/test_quality.gd
godot --headless --path misc/ai_game_builder --script res://tests/test_starter.gd
godot --headless --path misc/ai_game_builder --script res://tests/test_starter_3d.gd
godot --headless --editor --path misc/ai_game_builder --quit
```

GitHub Actions runs validator, context, quality and starter headless suites, a
Godot 4.8-beta4 editor-startup smoke check, and separate clean-project 2D/3D
scene imports and runtime tests when this addon or its workflow changes.
The 3D runtime test (`tests/test_runtime_3d.gd`) runs only inside the staged
project where `res://ai_generated/` is present. No API key is required in CI.

## Agent mode (MCP)

For fully automatic building by an external coding agent, see [`misc/godot_agent`](../godot_agent/README.md): a token-lean MCP server with scene, script, project, check and headless play-test tools.

## Next steps

For production use, add a project-context selector (opt-in), plan/execute/verify agent loop, background task queue, undoable edits, Godot parser checks, automated headless scene smoke tests, local model endpoints, tool policies and asset-generation backends.
