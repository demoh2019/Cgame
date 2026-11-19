# AI Game Builder (experimental Godot Editor plugin)

An opt-in AI game prototyping assistant for Godot 4.6+ (including this fork's
4.8 beta). It turns a natural-language game request into a **reviewable set
of GDScript scenes, scripts and text resources**. It does not silently modify
a project or run generated code.

## Quick start

1. Open this directory (misc/ai_game_builder) as a Godot project.
   The addon is enabled in its project.godot. Alternatively, copy
   addons/ai_game_builder/ into the addons/ directory of an existing game
   project, then enable **AI Game Builder** in Project > Project Settings >
   Plugins.
2. Open the **AI Game Builder** dock on the right.
3. Choose an OpenAI-compatible Chat Completions endpoint and model.
   The defaults are https://api.openai.com/v1/chat/completions and gpt-4.1-mini.
   For a local compatible service, localhost HTTP is also accepted.
4. Provide a key in the dock, or start the Godot editor with
   GODOT_AI_API_KEY set. The key is kept in memory for the current editor
   session and is **not** written into project files by this addon.
5. Describe a game, e.g. "Create a playable top-down shooter with keyboard
   movement, enemies, health, scoring, restart, and an instruction screen".
   Click **Generate preview**.
6. Examine the **full text** of every proposed file in the preview. Only then
   click **Apply reviewed files to project**. The addon will refuse to
   overwrite existing files unless you explicitly check the overwrite box.
7. If the output contains a main scene, optionally check **Set generated scene
   as project main scene**. Open/run the generated scene and verify gameplay.

The model/provider determines cost, latency and quality; the addon itself
does not include an LLM, subscription or hosted generation service.

## Design and safety

- Uses built-in HTTPRequest and an OpenAI-compatible chat completions API.
- "Fast" asks for at most 8 files; "Quality" asks for a more polished game.
  Both still use the model selected in the dock.
- Sends the prompt and the path of the currently edited scene, **not** the
  project's source code or other files.
- Expects a JSON response with summary, files [{path, content}] and optional
  main_scene. Markdown code fences are tolerated.
- Validates generated relative paths, forbids traversal, symlinks, hidden
  files, addons/ edits, binaries and unsupported extensions.
- Limits the plan to 24 text files, 256 KiB/file and 1 MiB total. Approving
  a preview is required before any generated file is written.
- Backups of overwritten files are saved under
  user://ai_game_builder_backups/<timestamp>/.
- Does not execute commands, install packages, create binary assets, invoke
  an image generator, or auto-run the game. Godot may execute scripts marked
  @tool when it imports a project: **treat model-produced code as untrusted**.
- File writes are not a transaction: disk errors partway through an apply
  can leave a partially modified project. Use version control.

## Headless tests

With a Godot 4.6+ executable available:

    godot --headless --path misc/ai_game_builder --script res://tests/test_plan.gd

The tests exercise path validation, plan parsing and size limits, filename
collisions, opt-in overwrite, and backup restoration. They do not test live
network requests, model quality, GUI rendering or whether generated games are
playable. Run those separately in the editor before releasing.

## Follow-on milestones

1. Project-aware context: explicit opt-in files, reference scenes, selected
   nodes and a token-budgeted project map; do not send hidden/secrets.
2. Agent loop: plans, editable diffs, per-file approval, undo, diagnostics,
   build/parse test, repair and regression tests; isolate untrusted code.
3. Game tooling: 2D/3D scene authoring, UI, audio/image generation through
   optional providers, reusable characters, environment generation, testing,
   profiling and iterative optimization.
4. Performance/reliability: response streaming, cancellation, caching,
   bounded parallel work, usage/cost budgets and measurable evaluations.

This is a **first usable integration**, not an autonomous "build any finished
game" agent. Further steps require explicit tooling permissions, real model
access, gameplay checks and iterative validation.

Roadmap reference: https://github.com/demoh2019/godot/issues/61
