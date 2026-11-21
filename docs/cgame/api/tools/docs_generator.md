# docs_generator.gd

> Cgame API documentation generator.

`res://scripts/tools/docs_generator.gd`

## Overview

```text
Cgame API documentation generator.

Scans GDScript files in one directory and writes one Markdown page per script plus a
top-level index grouped by folder. Extracted per script: the leading `##` header comment,
top-level `const` / `enum` / `signal` / `class` declarations, documented top-level `var`s and
every public `func` / `static func` signature (names starting with `_` are skipped) together
with the `##` comment directly above it. A `##` after a declaration on the same line is used
when there is no comment above.

CLI (arguments after `--`):
  godot --headless --path game --script res://scripts/tools/docs_generator.gd -- \
      --path res://scripts/shared --out /absolute/output/dir
Pages land in <out>/<folder>/<script>.md and <out>/index.md is rebuilt from every folder
already present under <out>, so several runs can share one output directory.

Limits: a plain text scan, not a GDScript parser. Doc comments must start in column 0 and
sit immediately above the declaration; blank lines detach them. Inner-class members and
multi-line constant bodies are not documented.
```

## Functions

### `extract`

```gdscript
static func extract(source: String) -> Dictionary
```

Splits `source` into a Dictionary with the keys header (String), consts, signals, classes,
vars and funcs (Arrays of Dictionaries with name / decl / doc, funcs also sig / is_static)
and private_count (int).

### `summary_of`

```gdscript
static func summary_of(header: String) -> String
```

First sentence of the header comment (at most ~160 characters), used by the index pages.

### `doc_block`

```gdscript
static func doc_block(doc: String) -> String
```

Doc text as Markdown. Text with indented lines (asset layouts, ASCII tables) is fenced so the
layout survives; plain prose is emitted as is.

### `render_page`

```gdscript
static func render_page(script_name: String, res_path: String, info: Dictionary) -> String
```

Renders the Markdown page for one script. `res_path` is shown verbatim under the title.

### `generate`

```gdscript
static func generate(res_dir: String, out_dir: String) -> int
```

Writes one page per .gd file directly inside `res_dir` into <out_dir>/<folder>/. Returns the
number of pages written, or -1 when the directory cannot be read.

### `build_index`

```gdscript
static func build_index(out_dir: String) -> int
```

Rebuilds <out_dir>/index.md from every sub-folder of `out_dir` that holds generated pages.
Returns the number of pages listed.

### `parse_args`

```gdscript
static func parse_args(args: PackedStringArray) -> Dictionary
```

_7 private function(s) starting with `_` are not listed._
