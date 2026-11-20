extends RefCounted
## Only rescan real cast-shadow batches after camera movement, new chunks or
## quality-profile changes. No new textures/passes or GPU allocations.
const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "single revision for each distinct GPU shadow budget"
	var balanced := VisualProfiles.settings(1)
	ShadowBudget.configure(balanced)
	var base_revision: int = ShadowBudget.revision()
	ShadowBudget.configure(balanced)
	t.eq(ShadowBudget.revision(), base_revision,
		"repeated unchanged quality does not trigger chunk-wide work")
	var high := VisualProfiles.settings(2)
	ShadowBudget.configure(high)
	t.eq(ShadowBudget.revision(), base_revision + 1,
		"new quality forces exactly one invalidation")
	ShadowBudget.configure(high)
	t.eq(ShadowBudget.revision(), base_revision + 1,
		"repeating the same profile does not invalidate twice")
	var ultra := VisualProfiles.settings(3)
	ShadowBudget.configure(ultra)
	t.eq(ShadowBudget.revision(), base_revision + 2,
		"switching to Ultra invalidates all cached shadow budgets")
	ShadowBudget.configure(balanced)
	t.eq(ShadowBudget.revision(), base_revision + 3,
		"switching back also invalidates existing chunks")

	t.current = "stationary camera and small motions skip expensive batch scans"
	var origin := Vector2(30.0, -40.0)
	var rev := ShadowBudget.revision()
	t.check(ShadowBudget.needs_refresh(Vector2.INF, -1, -1, origin, 8),
		"new chunks are initialized immediately")
	t.check(not ShadowBudget.needs_refresh(origin, rev, 8, origin, 8),
		"stationary camera requires no repeated AABB or caster traversal")
	t.check(not ShadowBudget.needs_refresh(origin, rev, 8, origin + Vector2(1.0, 0.0), 8),
		"sub-threshold pan avoids needless shadow work")
	t.check(not ShadowBudget.needs_refresh(origin, rev, 8, origin + Vector2(-0.5, -0.5), 8),
		"small diagonal movement stays within the hysteresis safety envelope")
	t.check(ShadowBudget.needs_refresh(origin, rev, 8, origin + Vector2(1.5, 0.0), 8),
		"full movement threshold refreshes shadow culling")
	t.check(ShadowBudget.needs_refresh(origin, rev, 8, origin + Vector2(1.1, 1.2), 8),
		"diagonal movement distance refreshes shadow culling")
	t.check(ShadowBudget.needs_refresh(origin, rev, 8, origin, 9),
		"new stream batches invalidate cached caster count")
	t.check(ShadowBudget.needs_refresh(origin, rev - 1, 8, origin, 8),
		"new graphics preset invalidates a stationary camera")
	t.check(not ShadowBudget.needs_refresh(origin, rev, 8, Vector2.INF, 8),
		"invalid camera position never triggers invalid AABB queries")
	t.check(not ShadowBudget.needs_refresh(origin, rev, 0, origin, 0),
		"empty chunks perform no shadow work")
	t.check(ShadowBudget.CAMERA_REFRESH_METERS < ShadowBudget.HYSTERESIS,
		"camera refresh is well within caster hysteresis width")

	t.current = "Performance remains asleep after it disables all shadow casters"
	var low := VisualProfiles.settings(0)
	ShadowBudget.configure(low)
	var low_rev: int = ShadowBudget.revision()
	t.check(ShadowBudget.needs_refresh(origin, rev, 8, origin, 8),
		"downgrading to Performance first clears previously active casters")
	t.check(not ShadowBudget.needs_refresh(origin, low_rev, 8,
		origin + Vector2(1000.0, 0.0), 8),
		"Performance skips even large-motion rescans after clearing shadows")
	ShadowBudget.configure(high)
	t.check(ShadowBudget.needs_refresh(origin, low_rev, 8, origin, 8),
		"upgrading from Performance turns shadows back on without camera motion")

	t.current = "existing real caster bounds and HLOD limits stay untouched"
	var bounds := AABB(Vector3(2.0, -3.0, 3.0), Vector3(10.0, 8.0, 5.0))
	var eye := Vector3(13.0, 120.0, 5.0)
	t.near(ShadowBudget.distance_to_bounds_xz(eye, bounds), 1.0, 0.0001,
		"render culling still uses the actual nearest 3D batch edge")
	t.check(ShadowBudget.should_cast("tree", 32.0, false),
		"High keeps real nearby trees in directional shadow maps")
	t.check(not ShadowBudget.should_cast("tree", 200.0, true),
		"distant forest still stops burning expensive GPU shadow raster work")
	var source: String = (ChunkView as Script).source_code
	t.check(source.contains("ShadowBudget.needs_refresh("),
		"live streamed world calls the early-out before iterating caster nodes")
	t.check(source.find("ShadowBudget.needs_refresh(") < source.find("for entry in _shadow_casters:"),
		"fast path is before any MultiMesh traversal")
	t.check(source.contains("_shadow_last_revision = ShadowBudget.revision()"),
		"chunk caches the new quality revision after a real scan")
	t.check(source.contains("_shadow_last_count = _shadow_casters.size()"),
		"newly streamed caster batches invalidate even with stationary camera")
	ShadowBudget.configure(balanced)
