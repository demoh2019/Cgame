# Cross-engine project import (experimental)

`engine_project_import.py` is a **conservative offline migration tool** for bringing
portable source assets into an existing Godot/Cgame project. It does **not** run a
Unity/Unreal game, unpack proprietary games, convert C# gameplay, or guarantee
that a migrated scene looks or behaves like the original.

## Supported input

| Source | Detected from | Current migration |
| --- | --- | --- |
| Unity | `Assets/` + `ProjectSettings/` | Portable resources; basic text `.unity` and `.prefab` 3D `GameObject`/`Transform` hierarchies to Godot `.tscn` placeholder Node3Ds |
| Unreal Engine | `*.uproject` | Portable exports under `Content/`; **not** `.uasset` / `.umap` binaries |
| GameMaker | `*.yyp` | Portable resource files, not `.yy` rooms / GML scripts |
| Defold | `game.project` | Portable resource files, not Lua scripts / collections |
| Other engines | `--engine generic` | Portable exported files from any directory |

Portable extensions: PNG, JPG/JPEG, WebP, BMP, TGA, SVG, HDR, EXR,
WAV, OGG, MP3, TTF, OTF, GLB, glTF, FBX, OBJ, MTL, DAE and Blend.
Relative glTF buffers/images, including `.bin` sidecars, are copied when present.
FBX and Blender imports can require external tools and depend on your Godot version;
**glTF 2.0 (`.glb`) is preferred** for interchange.

## Usage

```bash
# Dry run: writes nothing, prints JSON report
python3 misc/scripts/engine_project_import.py /path/to/UnityProject /path/to/GodotProject

# Explicitly apply the reviewed import
python3 misc/scripts/engine_project_import.py /path/to/UnityProject /path/to/GodotProject --apply

# A folder of exported assets from another engine
python3 misc/scripts/engine_project_import.py /path/to/exports /path/to/GodotProject --engine generic --apply
```

The Godot destination must already contain `project.godot`, and must not contain
or be contained in the input directory. Output is isolated under
`res://imported/<engine>/`; it includes `import_manifest.json` with asset
checksums, source-to-target mapping, unsupported extension counts and warnings.
**The importer never overwrites differing files.** Repeated identical imports
are safe; a changed asset requires manual review/removal of the old imported
copy and manifest before reapplying. Dry run is the default. Files are rolled
back on a failed partial copy. Source assets are never modified.

Unity text conversion preserves basic object names, active state, local positions,
rotations and scales, converting Z axis to Godot's right-handed coordinates.
It preserves supported parent-child hierarchy but intentionally makes only
`Node3D` placeholders: materials, cameras, mesh renderers, physics, prefabs
with overrides, animation, lighting, UI and `MonoBehaviour` scripts **are not
converted**. Components not handled are reported by Unity class ID.
Binary Unity scenes and unsupported YAML shapes are skipped and reported.
For Unreal, export models as `.glb`/`.gltf` or `.fbx` before migration.

## Safety notes

- Review the JSON report *before* applying. Generated scenes can still need manual fixes.
- External URLs in glTF are never fetched. Symlinked and path-traversing resources
  are not imported, and common build caches/hidden directories are ignored.
- No external Python dependencies, no proprietary format decryption, no code execution.
- Imported games are not automatically playable. Only use assets you have permission to migrate.

## Tests

```bash
python3 -m unittest discover -s misc/scripts/tests -p 'test_engine_project_import.py' -v
```

Tests cover engine detection, Unity hierarchy/transforms, portable assets,
glTF dependencies, security paths, dry runs, conflict preflight, idempotency,
and CLI failures. See `.github/workflows/engine-project-import.yml`.

### Follow-on work

Add a Godot EditorPlugin import wizard and AI migration assistant for unsupported
scripts/components, then implement a limited Unity 2D SpriteRenderer converter,
material/shader conversion, prefab overrides, animation and physics mappings.
Treat each supported Unity version and renderer as a separate compatibility target.