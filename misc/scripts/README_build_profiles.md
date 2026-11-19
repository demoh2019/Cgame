# Build Profiles for Godot projects (CLI)

A small, dependency-free **command-line** build profiles tool inspired by Unity's
Build Profiles. It selects an existing native Godot export preset, the build
mode and a reproducible output destination. It does **not** add a new editor UI,
change Godot export settings, install templates, sign builds or compile the engine.

## Configure a project

Create `build_profiles.json` next to `project.godot` and `export_presets.cfg`:

```json
{
  "version": 1,
  "profiles": {
    "windows-release": {
      "preset": "Windows Desktop", "mode": "release", "output": "builds/windows/game.exe"
    },
    "web-debug": {
      "preset": "Web", "mode": "debug", "output": "builds/web/game.zip"
    },
    "base-pack": {
      "preset": "Windows Desktop", "mode": "pack", "output": "builds/packs/base.pck"
    }
  }
}
```

The `preset` must already be listed in `export_presets.cfg` (Project > Export).
Set up export templates and any platform SDKs separately. Use a `.gitignore`
entry for `builds/` in each game project.

## Run

From the Godot engine source checkout:

```sh
python3 misc/scripts/build_profiles.py list --project /path/to/game
python3 misc/scripts/build_profiles.py validate --project /path/to/game
python3 misc/scripts/build_profiles.py plan windows-release --project /path/to/game
python3 misc/scripts/build_profiles.py build windows-release --project /path/to/game --godot godot
python3 misc/scripts/build_profiles.py build windows-release --project /path/to/game --overwrite
```

`plan` prints the exact command as a JSON argument array without touching the
filesystem. `build` invokes the Godot editor with `--headless --path PROJECT`
and the appropriate native `--export-release`, `--export-debug` or
`--export-pack` switch. Existing build files require explicit `--overwrite`.
The tool returns Godot's exit code on export failure, or `2` on invalid input.

## Format, restrictions and limitations

- JSON format is versioned and strict. Duplicate/unknown keys, duplicate output
  targets, invalid preset names/modes and invalid output formats are rejected.
- Export destinations must use portable slash-separated paths beneath `builds/`
  in the project. The tool rejects traversal, symlinks and unsafe Windows names.
- Outputs are created in a project-local directory, not in a sandbox. Do not
  run untrusted projects or trust `export_presets.cfg` plugin/extension scripts.
- The tool only checks preset names, not all platform-specific dependencies.
  A successful build is **not** proof of game runtime correctness. `plan` and
  `validate` do not run Godot or check export template availability.
- Concurrent exports to the same output path are not supported. The symlink
  checks reduce common mistakes but do not defend against a malicious process
  modifying the filesystem concurrently.

Run the standalone tests:

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_build_profiles.py' -v
```
