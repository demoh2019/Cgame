# AI Game Builder: three offline game starters

First gameplay templates for [AI Game Builder #73](https://github.com/demoh2019/Cgame/issues/73). This independent command-line foundation generates **three new Godot 4 projects without an API key, network request, downloaded assets, or model-generated code**:

| Template | Mechanics | Main controls |
| --- | --- | --- |
| `platformer` | 2D player, jumping, solid platforms, finish flag | Left/right arrows, Up or Space/Enter to jump |
| `topdown` | Top-down movement, walls, three pickups, goal | Arrow keys |
| `fps3d` | First-person movement, camera, collisions, jumping, target orb | Arrow keys, Space/Enter to jump, mouse to look, Escape to release pointer |

## Create a starter

```sh
python3 misc/scripts/ai_game_starters.py --template platformer \
  --project-name 'My Platformer' --output /tmp/my-platformer
python3 misc/scripts/ai_game_starters.py --template topdown \
  --project-name 'Gem Quest' --output /tmp/my-topdown
python3 misc/scripts/ai_game_starters.py --template fps3d \
  --project-name 'First Person Walk' --output /tmp/my-fps
```

`--output` must be a **nonexistent directory** inside an existing real parent directory. The directory name is restricted to portable ASCII letters/digits/hyphens/underscores. It refuses to overwrite existing projects or directories. On a regular write failure it attempts to clean up the newly created destination only. This is not a hardened race-resistant installer; do not run it in adversarial shared directories.

Each project contains `project.godot`, `main.tscn`, `game.gd`, `README.md` and `ai_recipe.json`. `ai_recipe.json` records the template, entry scene, controls, editable script/scene paths and SHA-256 digests of the other generated files. This deterministic recipe can help a future AI editor plugin **inspect and propose a reviewed change**; this CLI does not communicate with or invoke an LLM.

Open `project.godot` in a recent Godot 4 editor and press Play. Scenes use native Godot physics/camera/geometry primitives, no external assets. All gameplay is in `game.gd` so a user or future AI code reviewer can edit mechanics in one place.

## Tests and validation

```sh
python3 -m py_compile misc/scripts/ai_game_starters.py misc/scripts/tests/test_ai_game_starters.py
python3 -m unittest discover -s misc/scripts/tests -p test_ai_game_starters.py -v
```

The Python suite tests deterministic files, checksums, scene/script cross references, all three templates, CLI success/failure, existing-path collisions, path restrictions, symlinks, and rollback. The GitHub Actions workflow additionally downloads the Godot editor with a pinned SHA-256, creates all three games, imports each project and performs a short 5-frame headless smoke run. Passing a smoke test does not prove game quality or a complete playthrough.

## Intended integration

1. Editor offers **New Game from Template** and previews the 5 files.
2. AI reads a user-approved `ai_recipe.json` and bounded scene context, then proposes edits to the user's copy.
3. Human approves changes. Run the opt-in `ai_project_smoke.py` against a staged project, feed concise diagnostics into an AI repair proposal.
4. After headless checks and human playtesting, export normally through Godot.

**Limitations:** This is an offline starter CLI, **not yet the AI editor dock**, an autonomous agent, a full 3D FPS production kit, an image generator, or a runtime-proven application until Godot integration CI completes. Existing draft AI editor PRs must be consolidated rather than merged together without review.
