# Camera- and quality-invalidated directional shadow caster LOD

## Goal
Keep near-player detailed tree, bush and built-structure shadows without
repeatedly walking *all* streamed MultiMesh groups when the isometric
camera stands still. The existing CPU shadow-caster pass still runs at
most every 0.5 seconds. At that point, a cheap decision gates the
entire batch traversal, bounds transforms and AABB distance checks.

The cache is keyed by:
- camera ground-plane position (refresh after 1.5 m, smaller than the
  existing 5 m cast/uncast hysteresis);
- a global revision incremented only when the graphics shadow radii
  actually change;
- number of registered shadow-caster batches in the current chunk.

A freshly streamed chunk always gets an initial scan. Changes from
Balanced to High/Ultra or Performance invalidate the cache even if the
camera has not moved. After Performance disables all casters, even
large camera movements cannot cause redundant scans until quality or
chunk membership changes. This preserves the old behavior of zero
shadows on low-end hardware.

The exact renderer-facing shadow distances, roles, world-space bounds,
thresholds and actual `MultiMeshInstance3D.cast_shadow` toggles remain
unchanged. No gameplay/entity IDs, collisions, network protocols,
textures, shadow-map passes, or imported models are touched.

## Engine influence
Unreal virtual shadow maps emphasize caching shadow work and Unity
HDRP budgets expensive shadow casters. This is an equivalent *local CPU
policy*, not a port of either engine's GPU virtual shadow-map system.

## Verification
`game/tests/test_shadow_refresh_cache.gd` covers first scan, static
camera, sub-threshold pans, fast travel, profile downgrades/upgrades,
streaming changes, and real-bounds shadow decisions. It is registered
in `game/tests/run_all.gd`.

Profile P50/P95 CPU frame time and actual GPU shadow draws in a dense
forest with a stationary camera, then while panning. These tests are
structural; no FPS improvement is claimed without engine measurements.
