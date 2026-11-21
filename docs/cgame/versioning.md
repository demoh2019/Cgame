# Versioning and compatibility policy

Applies to the public API of the Cgame game-side libraries (`game/scripts/shared`, `client`, `server`,
`tools`) and to the data formats they read or write (graph assets, save data, replay files, bake output).

The game version lives in `game/project.godot` (`config/version`, currently `0.9.0`). This document is a
policy for how that number and the API surface move; it does not claim that past releases followed it.

## What counts as public API

- Public `func` / `static func` signatures, constants, signals and Dictionary key layouts documented with `##` in
  the API reference pages. Names starting with `_` are private and may change at any time.
- Serialized formats: asset dictionaries (PCG, VFX graph, audio graph, visual script, StateTree, cinematics),
  save data (`version` field, see `server/save_migrations.gd`), replay recordings, world-partition bake output,
  the wire format of `destruction_replication.gd` and the snapshot delta formats.
- CLI entry points under `scripts/tools` (arguments after `--`, exit codes).

Not public: anything marked experimental below the 1.0 line (see Stability levels), test helpers, `.uid` files.

## Semantic versioning

Version numbers are `MAJOR.MINOR.PATCH`.

| Change | Bump |
| --- | --- |
| Breaking change to a public signature, Dictionary key meaning, serialized format without an automatic migration, removed constant/signal | MAJOR |
| New function, new optional parameter at the end of a signature, new key in a returned Dictionary, new node/module type, new asset-format field with a default | MINOR |
| Bug fix, performance change that keeps results identical, doc change | PATCH |

Before 1.0 (the current `0.x` line) the minor number carries breaking changes: `0.MINOR` may break, `0.x.PATCH` must not.
Every breaking change, in any line, needs an entry made from the [migration guide template](migration-guide-template.md).

### Determinism and formats are part of the contract

Several libraries promise deterministic output for a given seed or input (planners, PCG, erosion, rollback,
replays, fracture seeds). Changing the output for an unchanged input is a breaking change for the library
concerned, because replays, baked worlds and tests depend on it. If a fix must change output, bump the version
of that format and ship a migration or a re-bake instruction.

## Stability levels

Every library is in one of three levels; the experimental-systems page lists the level in each section.

| Level | Meaning |
| --- | --- |
| Experimental | Library exists with tests, may not be wired into the game. API and formats can change in any MINOR release with a changelog line, but the migration guide is still required if a documented format changes. |
| Stable | Wired into the game or relied upon by another stable library. Breaking changes only in a MAJOR release (or a `0.MINOR` release while below 1.0) after the deprecation window. |
| Deprecated | Still works, emits a one-time warning, scheduled for removal. |

All libraries listed in the experimental-systems page start as Experimental.

## Deprecation window

1. Mark the old API with a `## Deprecated since X.Y: use <replacement>.` doc line. The generated API page then
   shows the notice.
2. Keep the old API working and call `push_warning` once per session when it is used.
3. Keep it for at least **two MINOR releases or 90 days, whichever is longer**, then remove it in the next MAJOR release
   (or the next `0.MINOR` while below 1.0).
4. Record the removal in the migration guide of the release that removes it.

Security fixes and data-corruption fixes may skip the window; the changelog and migration guide must say so.

## Data-format compatibility

- Save data: every schema change adds a single-step migration (`save_migrations.gd`: steps are +1, pure, gaps and
  downgrades refused) plus a fixture checked with `verify_roundtrip()`. Older saves must load in all releases
  within the supported range below.
- Asset dictionaries: readers ignore unknown keys; writers always emit the current format. A reader may drop support
  for a format version only through the deprecation window.
- Network: client and server must be built from the same MAJOR.MINOR. PATCH releases keep wire compatibility.
- Replays: a recording is valid for the build that made it. Cross-version replay is not promised.

## Long-term support (LTS)

- An LTS line is designated by the maintainers on a MAJOR.MINOR release; the first candidate is the 1.0 release.
- An LTS line receives bug and security fixes as PATCH releases for **12 months** after the next MAJOR.MINOR ships.
  No new features and no breaking changes.
- At most two LTS lines are supported at once.
- Experimental libraries are excluded from LTS guarantees unless promoted to Stable first.
- The Godot engine fork underneath is versioned separately; an LTS line records the engine commit it was built on.

## Promoting a library from Experimental to Stable

All of the following, recorded in the pull request:

1. Wired into the game (or another stable library) and used for at least one full MINOR cycle.
2. Headless tests cover the documented guarantees, and any listed limitation has a test or an explicit note.
3. API reference page has `##` docs on every public function.
4. No open determinism or data-loss bug.
5. Performance claims, if any, are backed by a `perf_regression.gd` comparison or a `--trace` capture, not by estimate.
