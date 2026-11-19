# AI Game Builder (prototype)

This is an **optional Godot 4 editor plugin** housed in the Godot source
repository. It is not automatically built into the engine binary. It offers a
reviewable, structured AI file-generation workflow for creating and iterating
on playable 2D/3D game prototypes.

## Installation

Copy misc/ai_game_builder/addons/ai_game_builder from this repository into
your game's res://addons/ai_game_builder folder. In Godot open
Project > Project Settings > Plugins and enable AI Game Builder.
Then open the AI Game Builder bottom panel.

Set an OpenAI-compatible Chat Completions endpoint, the provider model, and
an API key (if required). The default URL is
https://api.openai.com/v1/chat/completions. The key exists only in the
current editor session and is not written to the project.

Describe the game, click Generate plan, inspect the full proposed JSON and
generated scripts, then click Review and apply and approve the confirmation.
Open res://ai_generated/main.tscn and run it (F6). For follow-up prompts,
the plugin sends limited text content from already generated files to the
chosen provider, allowing those files to be updated.

## Validation and repair (manual, reviewable)

Every new proposal receives a **non-executing static inspection**. It checks:
- Scene/resource headers and JSON syntax.
- Existing or proposed resource references in .tscn/.tres files and common
  GDScript preload()/load() calls.
- Missing generated entry scene, suspicious OS.execute use and shader headers.
- Rejects generated @tool GDScript which can execute in the editor.

A plan with static errors cannot be applied through the UI. Click
**Ask AI to repair** to send diagnostics and the unapplied proposal (within
size limits) to the configured AI provider. The AI returns a NEW plan that must
be reviewed and explicitly approved again. There are no unbounded retries.

Click **Check generated files** to statically inspect saved content. You can
also paste real errors from the Godot Output / Debugger panel into the
diagnostics field and click **Ask AI to repair**. This flow is especially useful
after running a generated scene manually.

To check GDScript parsing separately using the installed Godot executable:

    godot --headless --path /path/to/your/project --check-only --script res://ai_generated/player.gd

Godot supports --check-only with --script for syntax/parser checks; run it
for every relevant .gd script. Static inspection by this addon **does not**
validate GDScript syntax, fully parse .tscn files, exercise game mechanics, run
scripts or prove that a generated game is playable. Execute untrusted
generated games only in a suitably isolated environment.

## Scope and safety

- Supports create/update of GDScript, scenes, resources, shaders and a few
  text formats only in res://ai_generated/. Existing project files outside
  this folder are never modified.
- No shell commands, automatic code execution, remote asset downloads or
  automatic project settings changes.
- A proposed change is not written before explicit review and confirmation.
- API requests may transmit your prompt, edited scene name and the contents
  of res://ai_generated/ to your chosen endpoint. Do not use a provider you
  do not trust. The HTTP client does not follow redirects.
- Plans are size-limited and path-validated, and symlinks in destination
  paths are rejected before writing. Generated GDScript is still
  **untrusted code**. Examine it before loading/running the resulting scene.
- File writes are preflighted and best-effort rolled back on write failure.
  This is not a substitute for version control or a full sandbox.
- The quality/playability of the generated game depends on the configured
  model; this plugin does not itself execute or automatically test games.

## Tests

From a local Godot 4 installation, run from the Godot repository root:

    godot --headless --path misc/ai_game_builder --script res://tests/run_tests.gd

The suite checks schema validation, path security, duplicate and size limits,
JSON parsing, file creation, update, overwrite refusal, preflight behavior,
resource-reference validation, JSON diagnostics, unsafe editor scripts, and
risk warnings.
Run a manual editor smoke test to validate API integration and UI behavior.

## Future work

For production-level autonomy, add an optional provider abstraction, a
diff-based editor for arbitrary project files, automated compile/test/repair loops,
scene-aware tools, asset generation services, task planning, and integration
into the editor core. These capabilities are not part of this prototype.
