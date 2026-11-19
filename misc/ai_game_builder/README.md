# AI Game Builder (experimental Godot Editor plugin)

An opt-in AI game prototyping assistant for Godot 4.6+ (including this fork's
4.8 beta). It turns a natural-language game request into a **reviewable set
of GDScript scenes, scripts and text resources**. It does not silently modify
a project or run generated code.

## Quick start

1. Open `misc/ai_game_builder` as a Godot project. The addon is enabled in
   its `project.godot`. To use another project, copy `addons/ai_game_builder/`
   to the project's `addons/` and enable **AI Game Builder** in Plugins.
2. Choose an OpenAI-compatible Chat Completions endpoint and a model. The
   default is `https://api.openai.com/v1/chat/completions`; local compatible
   endpoints on localhost HTTP are supported.
3. Provide an API key in the dock or start Godot with `GODOT_AI_API_KEY` set.
   The key stays in memory and is not saved to the game project.
4. Describe a playable game. Optionally enable **Include only selected project
   files in AI request** and explicitly list relative project paths, one per
   line (for example `scripts/player.gd`). Only these files are sent, up to
   eight source files with a 48 KiB combined limit; **this is opt-in**. Review
   each selected source file for secrets first. Simple pattern checks are not
   a guarantee against credential leaks.
5. Click **Generate preview**. Examine every generated file. The list marks
   NEW versus UPDATE destinations. Nothing is written yet.
6. Optionally write feedback and click **Refine previous preview with
   feedback**. This sends the previous generated plan and the feedback back to
   the provider for another generation pass. An unsuccessful call preserves
   the previous preview; no files are automatically changed.
7. Click **Apply reviewed files to project** when satisfied. Existing files
   require an explicit overwrite opt-in. If overwriting, backups are written
   under `user://ai_game_builder_backups/`.
8. Click **Play approved game scene** to launch the generated scene *only
   after reviewing and applying its files*. This runs the generated scripts
   with your normal Godot project permissions. Use a disposable project or a
   version-control checkpoint for untrusted outputs.

The model/provider determines cost, latency and quality. The addon does not
include an LLM, subscription or hosted generation service.

## Design and safety

- Uses built-in HTTPRequest and an OpenAI-compatible chat completions API.
- "Fast" asks for at most 8 files; "Quality" asks for a more polished game.
  Both still use the model selected in the dock.
- Sends the prompt and currently edited scene path by default. Source code is
  sent **only** when an explicit context opt-in checkbox is enabled and
  individual relative paths are listed. It refuses symlinks, large files,
  hidden paths, binaries and obvious credential patterns, but users must
  still inspect selected content themselves.
- Expects a JSON response with summary, files [{path, content}] and optional
  main_scene. Markdown code fences are tolerated.
- Validates generated relative paths, forbids traversal, symlinks, hidden
  files, addons/ edits, binaries and unsupported extensions.
- Limits the plan to 24 text files, 256 KiB/file and 1 MiB total. Approving
  a preview is required before any generated file is written.
- Backups of overwritten files are saved under
  user://ai_game_builder_backups/<timestamp>/.
- Rejects generated GDScript containing `@tool`, which otherwise could run
  inside the editor during imports. The checker does **not** prove arbitrary
  generated scripts safe; never treat generated code as trusted.
- Does not execute commands, install packages, create binary assets, or invoke
  an image generator. Running the generated game requires an explicit click.
- On mid-write failure, attempts to restore overwritten files from backups
  and remove newly created files. This rollback is best-effort, not an atomic
  transaction (power loss, disk errors and OS races can still leave changes).
  Always use version control.

## Headless tests

With a Godot 4.6+ executable available:

    godot --headless --path misc/ai_game_builder --script res://tests/test_plan.gd
    godot --headless --path misc/ai_game_builder --script res://tests/test_context.gd
    godot --headless --editor --path misc/ai_game_builder --quit

The tests cover path validation, JSON plans, size limits, filename collisions,
opt-in overwrite, backup and rollback recovery, explicit context selection,
UTF-8 validation, symlinks and secret-pattern rejection. CI also runs a Godot
headless editor smoke test. Neither suite validates live model requests,
rendered UI, gameplay quality or full-game reliability.

## Follow-on milestones

1. Project-aware context: optional selected nodes and a token-budgeted
   project map, with per-file preview and strict secret handling.
2. Agent loop: structured patch review, per-file approval, diagnostics,
   parse tests, automated repair and regression tests; isolate untrusted code.
3. Game tooling: 2D/3D scene authoring, UI, audio/image generation through
   optional providers, reusable characters, environment generation, testing,
   profiling and iterative optimization.
4. Performance/reliability: response streaming, cancellation, caching,
   bounded parallel work, usage/cost budgets and measurable evaluations.

This is a **first usable integration**, not an autonomous "build any finished
game" agent. Further steps require explicit tooling permissions, real model
access, gameplay checks and iterative validation.

Roadmap reference: https://github.com/demoh2019/godot/issues/61
