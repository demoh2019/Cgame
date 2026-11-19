# AI Game Builder (Godot 4.8 prototype)

A small, opt-in **Godot editor plugin** that generates playable game prototypes and
features from natural-language prompts using an OpenAI-compatible Chat Completions API.
It ships as a source addon in the fork (not as a built-in engine feature).

## Try it

1. Copy the folder `addons/ai_game_builder` from this directory into your Godot
   project's `res://addons/ai_game_builder/`.
2. Open **Project → Project Settings → Plugins** and enable **AI Game Builder**.
3. In the **AI Builder** dock, set the endpoint, model ID, and API key.
   - Cloud example: `https://api.openai.com/v1/chat/completions`.
   - Local Ollama OpenAI-compatible endpoint:
     `http://127.0.0.1:11434/v1/chat/completions`, using your installed model,
     with the key field left empty.
4. Describe a game (e.g. "Make a playable 2D platformer with a score and menu").
   Click **Generate** and **review the complete proposed file contents**.
5. Click **Apply** to create files, then **Open scene** to inspect the result.
   Set a main scene manually if desired.

The model and endpoint are configurable, with no bundled API key. The key is
kept only in the dock's password field; it is not written to disk by the plugin.

## Safety and scope

- Only a bounded list of *new* files under `res://ai_generated/` can be
  written: GDScript, scenes, resources, shaders, JSON, and Markdown.
- File path traversal, symlink components, case-insensitive path collisions, absolute paths outside the output directory,
  duplicate paths, unsupported extensions, oversized plans, and overwrites
  are rejected. Partial writes are rolled back on detected file errors.
- Generated JSON is parsed, generated scene/resource references are checked for missing output files, and generated `@tool` GDScript is rejected.
- API access is HTTPS only except for localhost HTTP. Redirects are disabled.
- The provider receives the user prompt, project name, main scene, and at most
  80 relevant **file paths**. The plugin does **not** send file contents.
- The model does not have shell access, direct filesystem tools, or automatic
  permission to modify existing project assets.
- Generated code is untrusted until reviewed; avoid executing generated code
  without examining its behavior. A successful HTTP response does not prove
  that a generated game runs correctly.
- This is an MVP: it does not yet iterate on compiler errors, read selected
  files, modify existing code, build 3D assets, or run an autonomous agent.

## Tests

Run with a Godot 4.8 editor or headless build:

    godot --headless --path misc/ai_game_builder --script tests/test_plan.gd

Tests cover JSON parsing, file limits, path sanitization, endpoint policies,
resource dependencies, editor-script restrictions, actual file creation, and overwrite protection.
The Linux CI editor build also runs a headless project smoke test with the plugin enabled.

## Next stages

Add opt-in selected-file context, semantic AST-aware edits, a structured
action/tool API, diff review, undo support, background import validation,
headless play tests, test-driven repair loops, and profiling. For production,
consider including this addon in project templates or integrating a native
editor module after the security model and tests mature.
