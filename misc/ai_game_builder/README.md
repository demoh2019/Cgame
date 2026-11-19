# AI Game Builder for the Godot editor

A small, opt-in EditorPlugin for Godot **4.8** (the version used by this fork).
It can draft new 2D/3D game scenes, GDScript controllers, shaders, and text resources using
an OpenAI-compatible chat-completions endpoint. It is a *review-first MVP*, not an
autonomous engine developer or a guarantee that generated games will run flawlessly.

## Install

Copy `misc/ai_game_builder/addons/ai_game_builder` into your **game project's**
`res://addons/ai_game_builder/` directory. In the editor, open
**Project > Project Settings > Plugins** and enable **AI Game Builder**.
This source-tree folder is a distributable addon; it is not pre-enabled in every
Godot project. `misc/ai_game_builder/project.godot` is a minimal test project.

## Configure

1. Enter a chat-completions API endpoint and model:
   - OpenAI-compatible: `https://api.openai.com/v1/chat/completions`
   - Local Ollama: `http://localhost:11434/v1/chat/completions`, using
     a local model with an OpenAI-compatible interface.
2. For hosted providers, enter the API key in the dock or set the process environment
   variable `GODOT_AI_API_KEY`. The key is held in memory for the editor session,
   not saved to the project or a settings file.
3. Describe the game, scene, improvement, or bug fix in Russian or English.
4. **Include project text files** is OFF by default; enabling it sends up to eight
   small files (maximum 48,000 characters combined) with the prompt.
   Review your project for secrets before opting in.
5. Click **Generate proposal**, inspect every proposed new/overwritten file,
   and select **Apply reviewed changes**. Existing files are backed up under
   Godot's `user://ai_game_builder/backups/` before applying; this location
   is outside your project and is not automatically pruned.
6. If a main scene is proposed, the plugin will change the project's startup scene
   after confirmation. You can then run and test the game.
7. If Godot reports errors, paste them into the **Godot error log** field and
   click **Generate repair proposal from errors**. The diagnostics and up to 12
   small generated files (48,000 characters maximum) are sent to your selected
   provider when clicked. Inspect and explicitly approve the repair as usual.

Generated proposals receive **basic preflight checks** for JSON, scene/resource
headers, empty scripts, shader headers, and SVG roots. These are not a substitute
for parsing or running the whole project. If a file changes between proposal
preview and confirmation, the plugin refuses to overwrite it; regenerate instead.

The addon sends data directly from the editor to the configured endpoint.
Plain HTTP is restricted to loopback hosts to protect credentials.
The AI cannot automatically execute shell commands, delete files, edit
`project.godot` directly, or write outside `res://`. Generating executable
GDScript still carries risk: review it before running. Use version control,
and run your game's tests before committing.

## Testing

From the engine or project with a compatible Godot binary:

```bash
godot --headless --path misc/ai_game_builder --script res://tests/test_ai_changes.gd
```

The test suite exercises response parsing, path safety, payload limits,
duplicate detection, lightweight content preflight, repair prompt structure,
preview hashes, and endpoint policy. It does *not* validate actual model
quality; model requests and editor UI require separate integration tests.

## Roadmap

- Project-aware multi-stage planning and selective context retrieval.
- Full Godot parser validation for generated scenes and scripts before applying.
- Automated, explicitly approved repair loops using Godot's headless diagnostics and project test suite.
- Diffs, one-click undo, provider presets, locally generated 2D/3D assets.
- Agent actions for editing nodes and resources, with explicit user confirmation.
