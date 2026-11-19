# Godot headless editor test matrix

An **opt-in**, standard-library-only smoke-test runner for roadmap #61 item 44 (Advanced Editor Testing). It executes the existing Godot editor binary; it does not replace engine doctest, compile Godot or assert that a scene renders correctly.

The JSON matrix (format 1) lives next to the test projects. A case runs --headless --path PROJECT with one of three action sets:

- import: --editor --import to import project assets.
- script: --script res://tests/smoke.gd for a GDScript extending SceneTree which calls quit().
- scene: --quit-after N --scene res://main.tscn to run a scene for a bounded number of frames.

Example smoke.json:

    {
      "format": 1,
      "cases": [
        {"name": "asset_import", "kind": "import", "project": "demo", "timeout_seconds": 120},
        {"name": "game_launch", "kind": "scene", "project": "demo", "entry": "res://main.tscn", "frames": 30, "timeout_seconds": 90},
        {"name": "script_tests", "kind": "script", "project": "demo", "entry": "res://tests/smoke.gd", "timeout_seconds": 60}
      ]
    }

Run from repository root:

    python3 misc/scripts/editor_ci_runner.py path/to/smoke.json --godot /path/to/godot --report /tmp/godot-smoke-report.json
    python3 -m unittest discover -s misc/scripts/tests -p test_editor_ci_runner.py -v

The CLI returns 0 when all cases pass, 1 on failing/timeout/unlaunchable cases, and 2 on invalid matrix or report-write error. It emits ordered JSON results with case name, status, exit code, duration and up to 8 KiB of combined output per case. The matrix is limited to 256 KiB and 256 cases. Cases accept only known Godot switches (no user-provided shell arguments), bounded timeouts (1–300 seconds) and strict res:// entry paths. Project paths are relative to the matrix directory; traversal and symlinks are rejected.

Run only on **trusted projects**: Godot scripts execute code; this tool is not a sandbox.

**Limitations:** this is an initial CI tool, not editor GUI automation or snapshot testing. Actual integration runs require a compatible Godot editor; offline unit tests use a fake editor executable. Real engine smoke runs on each platform have not been completed. Windows requires --godot to point to the editor .exe.
