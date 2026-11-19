# Built-in AI Game Builder (experimental)

The custom Godot editor includes an **AI Game Builder** dock. It can generate a small
playable 2D/3D prototype, GDScript, scene files, shaders, resources, and text data
from one natural-language request. It is **not** an unrestricted autonomous agent:
it cannot build or export executables, download assets, edit arbitrary existing
files, run tests, or independently ship a finished commercial game.

## Setup

1. Compile the editor with `tools=yes` (standard Godot editor builds).
2. Start the editor with a provider API key in your environment:
   - Linux/macOS: `export GODOT_AI_API_KEY="..."`
   - PowerShell: `$env:GODOT_AI_API_KEY="..."`
3. Optionally set `GODOT_AI_MODEL` (default: `gpt-4o-mini`).
4. Optionally set `GODOT_AI_ENDPOINT` (default:
   `https://api.openai.com/v1/chat/completions`).
5. Open a Godot project, locate the **AI Game Builder** dock (right-hand docks),
   enter a request and click **Generate Plan**. Review every proposed file, then
   click **Create Files (No Overwrite)**.

For local OpenAI-compatible inference, set an endpoint such as
`http://127.0.0.1:1234/v1/chat/completions` and specify a supported model.
A key is optional for localhost HTTP. HTTPS endpoints require the key.

**Do not commit API keys** to `project.godot`, scripts, project assets, or
the repository. The plugin reads its key from the editor process environment,
does not print the key, and does not persist it in editor settings.

## Example request

> Create a playable 2D top-down arcade game: movement with WASD, three enemy
> types, basic projectiles, collision damage, a score counter, a game-over
> screen, restart with R, and a `scenes/main.tscn` scene. Use only built-in
> nodes and procedural visuals. Explain which generated scene to open.

After creating the generated files, open `scenes/main.tscn` and use **Play
Current Scene (F6)**. To use **Run Project (F5)**, set the main scene under
**Project Settings → Application → Run → Main Scene**.

## Security, privacy and limits

- The plugin sends only the prompt you type, model ID and system instructions;
  it does **not** upload project contents automatically.
- Remote endpoints must use HTTPS. Plain HTTP is allowed only for
  `localhost` or `127.0.0.1`. Endpoint userinfo characters are rejected.
- Generated files appear in a **read-only preview** and are created **only
  after explicit approval**; existing project files are never intentionally
  overwritten. Prefer source control to review AI-authored changes.
- Only a strict JSON `files` array is accepted. Maximum **64** files,
  **256 KiB** per file and **1 MiB** combined. HTTP response size is capped
  at **2 MiB**, with a 90-second timeout and a Cancel control.
- File names must use safe portable ASCII names and extensions:
  `.gd`, `.tscn`, `.tres`, `.gdshader`, `.gdshaderinc`, `.json`,
  `.txt`, `.md`, `.svg`, `.csv`.
- Absolute paths, path traversal, hidden directories, Windows device names,
  symlinked subdirectories, duplicate paths and project configuration
  overwrites are disallowed. Writes are rolled back on a reported failure.
- Generated scripts and scenes **are not executed automatically**, but may
  execute when you open or run them in the editor. Review first.
- Provider responses are not guaranteed to be complete, compilable, safe or
  performant. Always test the generated scene, review the GDScript, and
  inspect imported resources. Generated game content may require corrections.
- Only the `/v1/chat/completions`-style response shape is currently supported.

## Automated tests

The C++ regression tests live in `tests/editor/test_ai_game_builder.cpp`
and cover path sanitization, unsafe extensions, duplicate paths on
case-insensitive filesystems, malformed provider responses, Markdown JSON
fences, file-size bounds, file-count bounds and parser state reset.

Typical local commands (adjust the binary path for your machine):

```sh
scons platform=linuxbsd target=editor tests=yes -j4
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[AIGameBuilder]*"
```

Unit tests verify the parser and validation logic. A real provider integration,
editor UI smoke test, and cross-platform filesystem tests are still required
before release. This feature is experimental and intentionally conservative.

## Future development

High-value extensions: conversation sessions, user-approved editing with
diffs and backups, local GDScript diagnostics, asset-generation providers,
scene tree tools, test-execute-fix loops with time and permission budgets,
multiplayer templates, export assistants, and optional on-device models.
The architecture should retain explicit review for filesystem changes and
never silently run generated code.
