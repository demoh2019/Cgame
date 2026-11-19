# Headless scene smoke tests (roadmap #61, item 44)

`scene_smoke.py` adds a lightweight **Advanced Editor Testing** workflow for Godot 4 projects. It scans `.tscn`/`.scn` files, optionally imports assets, launches **each scene in its own headless Godot process** for a bounded number of iterations and reports failures. This catches process crashes, hangs, nonzero exits and `ERROR:`/`SCRIPT ERROR:` log lines, even when Godot returns exit code 0.

```sh
python3 misc/scripts/scene_smoke.py /path/to/game --godot /path/to/godot --import-first
python3 misc/scripts/scene_smoke.py /path/to/game --godot godot --format json --frames 3 --timeout 45 --exclude 'experiments/*'
python3 misc/scripts/scene_smoke.py /path/to/game --godot godot --format junit > scene-smoke-results.xml
python3 misc/scripts/scene_smoke.py /path/to/game --godot godot --scene res://ai_generated/scenes/main.tscn --require-scenes --format json
python3 -m unittest discover -s misc/scripts/tests -p test_scene_smoke.py -v
```

Output is sorted by scene path. Exit status: `0` all scenes passed (including an empty scene set), `1` a scene or optional import failed or timed out, `2` invalid arguments, unsafe project tree or missing Godot executable. JSON contains an `ok` boolean and `results` with per-scene `scene`, `status`, `exit_code` and an error log tail; `--format junit` prints a JUnit-compatible `<testsuite>` containing one `<testcase>` per scene with `<failure>` children for errors/timeouts, and a dedicated `__import__` case if import fails (XML escaping and invalid control characters are handled); when importing fails, `import` contains the failure and `results` is empty. Error detection examines the **complete captured process log** before truncating reported diagnostics to 6000 characters.

`--max-scenes` (1000 by default) caps test selection; `--timeout` applies to each Godot process (and separately to import), and `--frames` defaults to 2. Hidden generated directories including `.godot` are skipped; symlinked scene files or traversed directories are rejected to avoid unintentionally checking outside the target project. Scene paths are passed as separate subprocess arguments, never via a shell. Python 3.9+ and an installed Godot 4 **editor build** are required for optional `--import-first`.

## Verify AI-generated scenes without false-green results

`--scene` accepts an **exact** `res://` or project-relative scene path and may be repeated to select multiple scenes. Its spelling and capitalization must match the project; missing or excluded scenes, path traversal, empty names, and absolute paths are rejected with exit code 2. The tool never invokes a shell or executes a different scene merely because a requested path does not exist.

Add `--require-scenes` to CI and AI Game Builder validation: otherwise, checking an empty scene set is intentionally a successful no-op for backward compatibility. Together, `--scene res://ai_generated/scenes/main.tscn --require-scenes` validates precisely the intended generated scene rather than unrelated files.

The real-Godot CI fixture now exercises exact scene selection for both a valid project and a deliberately invalid script.

## Real Godot 4.7.2 integration checks

The `.github/workflows/scene-smoke.yml` workflow has two types of jobs:

- Python 3.9 and 3.13 regression tests for CLI behavior, including JUnit XML serialization.
- A Linux real-engine job that downloads the **official Godot 4.7.2 editor**, verifies the fixed SHA-256 digest before execution, then checks a valid project with `--import-first` and a separate project whose GDScript cannot parse. CI asserts both the expected exit status and one matching scene result, including an engine parser error for the invalid project. The fixtures are in `misc/scripts/tests/fixtures/scene_smoke/`.

These integration checks cover a single pinned Linux editor version, not Windows, macOS, .NET, renderer-specific functionality, or a custom-built Cgame editor. A queued or absent CI result is **not** evidence the checks passed.

## Scope and limitations

- **This is a smoke test, not a screenshot comparison or a deterministic gameplay test.** It does not certify rendering fidelity, physics determinism, scene correctness after the chosen number of frames, or availability of platform-specific resources.
- Running a game scene executes **project code**, which can write files, access the network or start processes. Use only trusted projects, preferably inside disposable CI sandboxes. A timeout limits execution duration, not resource consumption.
- Non-error warnings are allowed. Some engine diagnostics use formats other than the recognized error prefixes and may not fail the run; review logs and run other tests for full coverage. On platforms without a compatible headless renderer, skip scenes requiring graphics.
- The Python test suite uses a fake Godot executable for deterministic subprocess, timeout, import and error-detection coverage. Passing those tests does **not** prove an actual Godot engine build or game project passed.

This is the first incremental testing tool for issue #61; **do not mark roadmap item 44 complete** without real-engine CI, examples, and broader editor integration.
