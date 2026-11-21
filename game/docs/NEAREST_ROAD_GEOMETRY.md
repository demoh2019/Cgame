# Nearest road segment queries (engine ↔ Albion After)

Cgame adds `Geometry2D.get_closest_point_on_segments(point: Vector2, segment_endpoints: PackedVector2Array) -> Dictionary`.
The packed endpoints represent independent segments: `[a0, b0, a1, b1, ...]`. The API returns the closest `point`, Euclidean `distance`, zero-based `segment_index` and normalized `t` for the winning segment. Degenerate segments are points; ties choose the first segment. An empty dictionary signals no valid hit (including empty input, invalid or oversized inputs). The function accepts a maximum of 32,768 segments per call, requires finite coordinates, and scans linearly.

This is a general-purpose geometry primitive similar in purpose (not identical in curve semantics) to Unity Splines' `SplineUtility.GetNearestPoint` and Unreal Engine's closest-location spline queries. It operates on piecewise-linear independent segments, not Bezier splines.

## Integrated into canonical game

`game/scripts/shared/world_roads.gd` already indexes dirt roads into local chunk cells. On Cgame, it pre-packs each cell's valid segments when building the road graph and computes road proximity using the native Geometry2D query. On stock Godot, it retains the existing `coverage_on_segments` calculation. Both branches preserve the identical road grip curve and the original server-authoritative world data. Segments remain partitioned by cell; this is not a global search.

## Verification

- Native unit test: `godot --headless --test --test-case="*nearest point among independent segments*"`.
- Game tests: `godot --headless --path game --script res://tests/run_all.gd` (includes `test_world_roads.gd`). Check scalar/native parity of coverage, terrain road placement and zero-length segments.
- Run gameplay movement and bike grip regressions under native Cgame and stock Godot. Compare outputs, then benchmark before claiming speedup.

The code has no measured speedup until run on the project target hardware. No network protocol or save schema change is required.

References: https://docs.unity.cn/Packages/com.unity.splines%402.5/api/UnityEngine.Splines.SplineUtility.GetNearestPoint.html and https://dev.epicgames.com/documentation/unreal-engine/BlueprintAPI/Spline/FindLocationClosesttoWorldLocati-?lang=en-US
