# Migration guide: Cgame X.Y -> X.Z

Copy this file to `docs/cgame/migrations/X.Y-to-X.Z.md` for every release that contains a breaking or
deprecating change (see [versioning policy](versioning.md)). Delete the guidance in italics. Keep entries
factual: what changed, how to detect it, how to fix it.

## Summary

- Release: `X.Z` (date). Upgrades from: `X.Y` (and the oldest supported version, `X.W`).
- Breaking changes: N. Deprecations: N. Format changes: N.
- Automatic migrations: list (for example save `version` 3 -> 4).
- Needs manual action: yes / no.

## Before you upgrade

- [ ] Back up save data, baked worlds and recorded replays you still need.
- [ ] Run the test suite on the old version and note failures (`godot --headless --path game --script res://tests/run_all.gd`).
- [ ] Search your code for each symbol in the tables below.
- [ ] Rebuild the Godot fork if the engine commit changed (see "Engine" below).

## Breaking changes

*One row per change. "Detect" is a grep pattern or a test failure message, not a description.*

| Area | Old | New | Detect | Fix |
| --- | --- | --- | --- | --- |
| `res://scripts/shared/example.gd` | `func plan(start)` | `func plan(start, goal)` | `grep -rn "\.plan(" game/` | Pass the goal; use `Vector3.ZERO` for the old behaviour. |

### Details

*One subsection per row when the table is not enough: reason for the change, before/after code, edge cases.*

```gdscript
# before
var route: Array = Example.plan(start)
# after
var route: Array = Example.plan(start, Vector3.ZERO)
```

## Deprecations

| Symbol | Deprecated in | Replacement | Removal |
| --- | --- | --- | --- |
| `Example.old_name()` | X.Z | `Example.new_name()` | earliest `X.(Z+2)` and not before DATE |

## Data format changes

| Format | Old version | New version | Migration | Rollback |
| --- | --- | --- | --- | --- |
| Character save | 3 | 4 | automatic: `save_migrations.gd` step 3 -> 4 | restore backup; downgrades are refused by design |
| Baked world partition | - | - | re-bake required / not required | keep old bake output |

*Describe fixtures: which sample was run through `verify_roundtrip()`.*

## Behaviour changes without API changes

*Determinism-affecting changes belong here: same seed now gives different output, tick order changed, default values changed.*

- What changed, which seeds / replays / bakes are affected, how to regenerate them.

## Engine

- Godot fork commit: old `<sha>`, new `<sha>`. Rebuild command and platforms checked.
- Changes to custom modules under `modules/` that scripts can observe.

## Verification after upgrading

- [ ] Test suite passes: record the TOTAL line.
- [ ] Regenerate the API reference and diff against the previous one.
- [ ] Spot-check the wired features affected by this release (list them).
- [ ] If performance matters for the change: compare two runs with `res://scripts/tools/perf_regression.gd` and attach the result.

## Known issues

- Issue, workaround, tracking link.

## Rollback

- Steps to return to `X.Y`, and which data written by `X.Z` will not load there.
