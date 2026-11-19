# AI Game Builder — experimental Godot 4.x EditorPlugin

Describe a game in natural language and generate a **reviewable** set of Godot scenes, scripts, and text resources. This is an early, intentionally small foundation for AI-assisted game creation, **not** a fully autonomous engine or guarantee of a polished game.

## Install

From the root of a Godot source checkout:

```bash
python misc/ai_game_builder/install.py --project /path/to/your/game
```

Alternatively, copy the `addons/ai_game_builder` directory into `<your project>/addons/ai_game_builder`. Then enable **AI Game Builder** in **Project > Project Settings > Plugins**.

## Configure

The plugin uses an OpenAI-compatible `chat/completions` JSON endpoint and makes the request from the Godot editor (not the exported game). Configure the environment **before launching Godot**:

```bash
export GODOT_AI_API_KEY='your-api-key'
export GODOT_AI_ENDPOINT='https://api.openai.com/v1/chat/completions'
export GODOT_AI_MODEL='gpt-4.1-mini'
```

Do not commit keys to `.gd` files or `project.godot`. The key stays in the editor process and is sent as a Bearer token only when you press **Generate plan**. For local providers on `127.0.0.1`/`localhost`, HTTP is accepted only if the API key is empty. Custom compatible providers may have different token and message-format requirements.

## Create a game

1. Open the **AI Game Builder** dock and describe the game (or choose a sample prompt).
2. Select **Generate plan**. The AI returns a JSON manifest of new `.tscn`, `.gd`, `.tres`, or other text files. Models can make mistakes; invalid responses are rejected.
3. Inspect **every file** in the preview, then check **I reviewed the generated files**.
4. Optionally enable **Set the generated main scene**; select **Create files**. The plugin writes only under `res://ai_generated/`, never replaces existing files, and uses temporary staging plus cleanup on failure.
5. Open and run the generated main scene. If an improvement is needed, prompt for a *new version with different filenames* (overwriting is deliberately unsupported).

The engine-side starter is restricted to 32 files, 128 KiB per file and 512 KiB total, to avoid excessive or accidental writes. Generated GDScript is untrusted code: review it before running the scene. The plugin rejects generated `@tool` scripts so generated code does not automatically run in the editor, but it is **not a complete code-sandbox or malware scanner**. Generated scenes may refer to other resources, and scripts can do harmful things when executed. Always work on a version-controlled game project.

## Development and tests

Run the GDScript contract and writer tests with a locally built Godot 4.x binary:

```bash
godot --headless --path misc/ai_game_builder --script res://tests/test_plan.gd
```

Run installer tests (no Godot binary required):

```bash
python -m unittest discover -s misc/ai_game_builder/tests -p 'test_install.py' -v
```

## Scope and next milestones

This first version can plan and write small 2D/3D prototypes and UI flows. It does **not** control the running game, run builds, modify arbitrary files, generate image/audio assets, perform autonomous multi-step execution, or repair compilation errors. Those capabilities should be added incrementally behind explicit review, test execution, cancellation and authorization boundaries.
