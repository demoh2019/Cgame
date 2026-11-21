# Cgame documentation portal

Documentation for the game-side engine libraries in `game/scripts/` (GDScript, Godot 4 fork).
Everything here describes what is in the repository today; nothing is a performance promise unless a
test or tool in the repo measures it.

## Navigation

| Page | What it is for |
| --- | --- |
| [API reference](api/index.md) | One generated page per script (`shared`, `client`, `server`, `tools`): header comment, constants, signals, public function signatures with their `##` docs. |
| [Experimental systems](experimental-systems.md) | Purpose, status (library vs wired into the game), guarantees and known limitations for each recently added library. |
| [Versioning and compatibility](versioning.md) | Semantic versioning policy, deprecation window, LTS policy. |
| [Migration guide template](migration-guide-template.md) | Copy this for every release that changes a public API or data format. |
| [Sample-project guides](samples.md) | Step-by-step builds for a large world partition, a PCG graph, a mass crowd and virtual geometry. |

## Conventions

- **Library** means the code exists, is covered by headless tests, and is not called from the running game.
  **Wired** means the game client or server calls it. Each section of the experimental-systems page says which.
- Libraries are plain GDScript, mostly `RefCounted` classes with static functions, and take and return plain
  Dictionaries / packed arrays so they run headless (`godot --headless`) and in tests.
- Scripts have no `class_name`; load them with `const X = preload("res://scripts/shared/x.gd")`.
- Warnings are errors in this project: type every variable, avoid `:=` on Dictionary/Array lookups, mark
  intentional integer division with `@warning_ignore("integer_division")`.

## Regenerating the API reference

The pages under `api/` are produced by `game/scripts/tools/docs_generator.gd`. Run it once per folder; the index
is rebuilt from every folder already present in the output directory.

```text
for d in shared client server tools; do
  godot --headless --path game --script res://scripts/tools/docs_generator.gd -- \
    --path res://scripts/$d --out "$PWD/docs/cgame/api"
done
```

The generator is a text scan, not a GDScript parser: it reads `##` comments that start in column 0 directly above
a declaration. Scripts without `##` comments therefore get a page with signatures only. Improve a page by
improving the comments in the source, then regenerate. The generator itself is covered by
`game/tests/test_docs_generator.gd`:

```text
godot --headless --path game --script res://tests/run_one.gd -- test_docs_generator
```

## Where to start

- Writing gameplay AI: [planners](experimental-systems.md#1-planners-goap-htn-utility-ai), [StateTree](experimental-systems.md#23-statetree-and-smart-objects).
- Building a big streamed level: [sample: large world partition](samples.md#1-large-world-partition).
- Populating a level procedurally: [sample: PCG graph](samples.md#2-pcg-graph).
- Thousands of agents: [sample: mass crowd](samples.md#3-mass-crowd-simulation).
- High-poly static meshes: [sample: virtual geometry](samples.md#4-virtual-geometry).
