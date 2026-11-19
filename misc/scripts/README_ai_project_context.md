# AI Game Builder: privacy-bounded project outline

ai_project_context.py provides a **read-only, opt-in, deterministic** project summary for a future scene-aware AI Game Builder (issue #73). It closes one small tooling gap with project-aware AI assistants: the context includes the scene node hierarchy, external resource paths, GDScript class/function names and resource kinds, **without transmitting complete scripts, arbitrary file bodies or credentials**.

    python3 misc/scripts/ai_project_context.py /path/to/my-godot-game > context.json
    python3 misc/scripts/ai_project_context.py /path/to/my-godot-game --max-files 50 --max-output-bytes 8192
    python3 -m unittest discover -s misc/scripts/tests -p test_ai_project_context.py -v

The CLI prints compact JSON to stdout. Its schema is cgame.ai_project_context.v1; files contains sorted, bounded summaries. truncated and skipped_files warn when limits are reached. It neither runs Godot nor invokes a model or network API, and it does not modify the project. A future editor plug-in may request explicit consent to load this summary into an LLM prompt; **the CLI never uploads it**. Treat scene/node names and resource paths as potentially sensitive and review output before sharing externally.

Defaults: at most 128 indexed files, 64 KiB of source examined per file, 64 KiB of JSON output. Hidden directories, Godot import caches, binary/unreadable files, oversized files and symlinks are skipped. Only .tscn, .tres, .gd and .gdshader files are inspected. This is structural indexing, **not** a full GDScript parser, parser diagnostics or an autonomous game-building agent. Godot integration, scene modification, undo, prompted iteration and end-to-end game tests are tracked separately in issue #73.

The offline tests cover encoding, security boundaries, deterministic order, size budgets and subprocess CLI behavior. The standalone CI workflow tests Linux, Windows and macOS using the Python standard library without downloading an engine.
