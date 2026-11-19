# Project asset audit (Python, no editor required)

A small, standalone tool to help large Godot projects detect asset-path bugs
**before** asset imports, packaging, or platform-specific builds. This is the
initial implementation of Asset Pipeline Automation (#46 in the feature plan).
It does **not** perform imports, builds, or asset transformations.

Run against an existing Godot project:

```bash
python3 misc/scripts/project_asset_audit.py /path/to/godot-project
```

JSON report for CI:

```bash
python3 misc/scripts/project_asset_audit.py /path/to/godot-project --format json
```

GitHub Actions file/line annotations with escaped paths and messages:

```bash
python3 misc/scripts/project_asset_audit.py /path/to/godot-project --format github --fail-on-warning
```

Optional flags: `--exclude "vendor/*"` (repeatable), `--max-text-bytes N`,
`--fail-on-warning`, and `--no-cycles`. Exit codes: 0 for success, 1 for audit
violations, 2 for invalid configuration.

## Checks

The scanner walks resources deterministically and reports:

- **MISSING_RESOURCE**: a quoted `res://` reference targets a missing file.
- **CASE_MISMATCH**: path exists with different capitalization.
- **CASE_COLLISION**: distinct paths clash on case-insensitive/Unicode-normalizing filesystems.
- **INVALID_RESOURCE_PATH**: absolute path or parent traversal.
- **INVALID_SEPARATOR**: backslash rather than forward slash.
- **EMPTY_RESOURCE_PATH**, **RESOURCE_IS_DIRECTORY**: invalid resource targets.
- **RESOURCE_OUTSIDE_PROJECT**: a referenced file or directory symlink resolves outside the project.
- **UNRESOLVABLE_RESOURCE**, **UNRESOLVABLE_SYMLINK**: cycles or broken link targets cannot be used as project resources.
- **DEPENDENCY_CYCLE**: potential circular static `res://` dependencies among scripts,
  scenes, shaders, and text resources. Reported once per strongly connected group
  as a **warning**, because some references may be intentional. Use
  `--fail-on-warning` to fail CI or `--no-cycles` to suppress this diagnostic.
- Warnings for external symlinks, invalid UTF-8 text, or files exceeding the
  configured scan-size limit.
- Unreadable directories cause a scan failure (exit code 2), rather than a false clean report.

Checks are intentionally conservative: only quoted `res://` literals in
`.gd`, `.tscn`, `.tres`, `.godot`, `.gdshader`, `.gdshaderinc`, `.cs`,
`.cfg`, `.shader`, `.escn`, and `.json` are inspected. Generated
`.godot/` and `.import/` directories, Git metadata, and common vendor
dependencies are ignored. The command never modifies assets. JSON output also includes a deterministic
`dependencies` map of source file to sorted static dependency paths for tools
that need to inspect the resource graph. The cycle detector uses iterative
strongly connected components, avoiding recursion limits on large projects.

**Limitations:** This is not the Godot resource parser. It cannot resolve
`uid://` identifiers, dynamically concatenated paths, linked external files,
or references in binary resource formats; it does not validate whether an
existing path contains the expected resource type. It may flag a `res://`
literal that is only intended as a string. Run the Godot editor's import and
project validation too.

## Dependency and reverse-reference graph

To inspect which files use a particular asset (and which resources a scene
depends on), run the read-only [Asset Reference Graph](README_asset_reference_graph.md)
CLI. It shares this auditor's static-reference parser, supports multi-hop
dependency and referrer traversal, and exports text, JSON or Graphviz DOT.
Only existing static resource paths produce graph edges; run this auditor
to diagnose broken or invalid references.

## Tests

The tool uses Python's standard library and needs no engine build:

```bash
python3 -m unittest discover -s misc/scripts/tests -p 'test_project_asset_audit*.py' -v
```

The regression suites cover collision/case handling, Unicode, symlink containment
and cycles, circular resource dependency graphs (including very long chains),
unreadable directory failures, import exclusions, static paths,
invalid text, JSON output, exit codes, and deterministic findings. The
`project-asset-audit.yml` workflow runs them on pull requests and `develop`
pushes. Suitable for a lightweight CI job:

```yaml
- name: Audit project assets
  run: python3 misc/scripts/project_asset_audit.py game/ --fail-on-warning --format json
```
