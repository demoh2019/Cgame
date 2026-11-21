extends RefCounted
## Native SignificanceBudgetPlanner parity and stock-Godot fallback for VFX.
## Never used for gameplay authority, hit validation, audio or networking.

const MAX_DISTANCE := 140.0
const FRAME_BUDGET := [8, 12, 18, 24]
## Resident particle instances include live emitters, not only idle cache.
## Idle cache can shrink gradually after reducing the graphics quality.
const POOL_RESIDENT_TARGET := [2, 4, 8, 12]
const POOL_CHANGES_PER_FRAME := [1, 1, 2, 2]


static func pool_resident_target(quality: int) -> int:
	return POOL_RESIDENT_TARGET[clampi(quality, 0, 3)]


static func pool_changes_per_frame(quality: int) -> int:
	return POOL_CHANGES_PER_FRAME[clampi(quality, 0, 3)]
const CAPS := [
	[1, 4, 5, 4],
	[2, 6, 8, 6],
	[3, 10, 12, 8],
	[4, 12, 16, 12],
]


static func budget_for(quality: int) -> int:
	return FRAME_BUDGET[clampi(quality, 0, 3)]


static func caps_for(quality: int) -> PackedInt32Array:
	return PackedInt32Array(CAPS[clampi(quality, 0, 3)])


static func select_indices(distances: PackedFloat64Array,
		priorities: PackedByteArray, categories: PackedByteArray,
		quality: int, native: Object = null) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var n: int = distances.size()
	if n != priorities.size() or n != categories.size() or n > 16384:
		return empty
	for i in n:
		if not is_finite(distances[i]) or distances[i] < 0.0 \
				or priorities[i] > 3 or categories[i] > 3:
			return empty
	var caps: PackedInt32Array = caps_for(quality)
	var budget: int = budget_for(quality)
	if native != null and native.has_method("select_effects"):
		return native.call("select_effects", distances, priorities, categories,
			caps, budget, MAX_DISTANCE)
	var eligible: Array[int] = []
	for i in n:
		if distances[i] <= MAX_DISTANCE and caps[categories[i]] > 0:
			eligible.append(i)
	eligible.sort_custom(func(a: int, b: int) -> bool:
		if priorities[a] != priorities[b]:
			return priorities[a] > priorities[b]
		if distances[a] != distances[b]:
			return distances[a] < distances[b]
		return a < b)
	var used := PackedInt32Array([0, 0, 0, 0])
	var output := PackedInt32Array()
	for index in eligible:
		if output.size() >= budget:
			break
		var group: int = int(categories[index])
		if used[group] >= caps[group]:
			continue
		used[group] += 1
		output.append(index)
	return output


## Frustum-biased admission: render on-screen VFX first within the same
## urgency tier. Off-screen critical feedback still beats nearby low-priority
## effects; no gameplay authority, event or audio is discarded.
static func select_visible_indices(distances: PackedFloat64Array,
		priorities: PackedByteArray, categories: PackedByteArray,
		visible: PackedByteArray, quality: int,
		native: Object = null) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var n: int = distances.size()
	if n != priorities.size() or n != categories.size() or n != visible.size() or n > 16384:
		return empty
	for i in n:
		if not is_finite(distances[i]) or distances[i] < 0.0 \
				or priorities[i] > 3 or categories[i] > 3 or visible[i] > 1:
			return empty
	var caps: PackedInt32Array = caps_for(quality)
	var budget: int = budget_for(quality)
	if native != null and native.has_method("select_effects_visible"):
		return native.call("select_effects_visible", distances, priorities,
			categories, visible, caps, budget, MAX_DISTANCE)
	var eligible: Array[int] = []
	for i in n:
		if distances[i] <= MAX_DISTANCE and caps[categories[i]] > 0:
			eligible.append(i)
	eligible.sort_custom(func(a: int, b: int) -> bool:
		if priorities[a] != priorities[b]:
			return priorities[a] > priorities[b]
		if visible[a] != visible[b]:
			return visible[a] > visible[b]
		if distances[a] != distances[b]:
			return distances[a] < distances[b]
		return a < b)
	var used := PackedInt32Array([0, 0, 0, 0])
	var output := PackedInt32Array()
	for index in eligible:
		if output.size() >= budget:
			break
		var group: int = int(categories[index])
		if used[group] >= caps[group]:
			continue
		used[group] += 1
		output.append(index)
	return output

## Type-specific cosmetic range (meters): dust, hits, combat, milestones.
## Long-range milestone feedback is preserved even at Performance quality.
const CATEGORY_RANGES := [
	[18.0, 40.0, 75.0, 140.0], # Performance
	[24.0, 50.0, 95.0, 140.0], # Balanced
	[32.0, 65.0, 110.0, 140.0], # High
	[40.0, 80.0, 120.0, 140.0], # Ultra
]


static func ranges_for(quality: int) -> PackedFloat64Array:
	return PackedFloat64Array(CATEGORY_RANGES[clampi(quality, 0, 3)])


## Opt-in per-category Niagara-style range admission for the real burst queue.
## Existing select_visible_indices callers keep their global-range behavior.
## Older native Cgame engines use the exact stock-Godot fallback.
static func select_visible_ranged_indices(distances: PackedFloat64Array,
		priorities: PackedByteArray, categories: PackedByteArray,
		visible: PackedByteArray, quality: int,
		native: Object = null) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var n: int = distances.size()
	if n != priorities.size() or n != categories.size() or n != visible.size() or n > 16384:
		return empty
	for i in n:
		if not is_finite(distances[i]) or distances[i] < 0.0:
			return empty
		if priorities[i] > 3 or categories[i] > 3 or visible[i] > 1:
			return empty
	var caps: PackedInt32Array = caps_for(quality)
	var ranges: PackedFloat64Array = ranges_for(quality)
	var budget: int = budget_for(quality)
	if native != null and native.has_method("select_effects_visible_ranged"):
		return native.call("select_effects_visible_ranged", distances, priorities,
			categories, visible, caps, ranges, budget)
	var eligible: Array[int] = []
	for i in n:
		if distances[i] <= ranges[categories[i]] and caps[categories[i]] > 0:
			eligible.append(i)
	eligible.sort_custom(func(a: int, b: int) -> bool:
		if priorities[a] != priorities[b]:
			return priorities[a] > priorities[b]
		if visible[a] != visible[b]:
			return visible[a] > visible[b]
		if distances[a] != distances[b]:
			return distances[a] < distances[b]
		return a < b)
	var used := PackedInt32Array([0, 0, 0, 0])
	var output := PackedInt32Array()
	for index in eligible:
		if output.size() >= budget:
			break
		var group: int = int(categories[index])
		if used[group] >= caps[group]:
			continue
		used[group] += 1
		output.append(index)
	return output


## Soft per-category reservations for busy combat frames: foot dust is
## expendable, hit feedback and combat bursts keep a minimum share whenever
## eligible. Priority-3 boss/death/level-up events always bypass these minima.
const CATEGORY_MINIMUMS := [
	[0, 1, 1, 0], # Performance
	[0, 1, 2, 0], # Balanced
	[0, 2, 2, 0], # High
	[0, 2, 3, 0], # Ultra
]


static func minimums_for(quality: int) -> PackedInt32Array:
	return PackedInt32Array(CATEGORY_MINIMUMS[clampi(quality, 0, 3)])


## Three-stage Niagara-inspired VFX plan: first all priority-3 events,
## then soft category minimums, then top-significance fill. This *does not*
## exceed the frame total, caps or distance ranges. Stock Godot uses the same
## deterministic selection and older Cgame engines remain compatible.
static func select_visible_fair_indices(distances: PackedFloat64Array,
		priorities: PackedByteArray, categories: PackedByteArray,
		visible: PackedByteArray, quality: int,
		native: Object = null) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var count: int = distances.size()
	if count != priorities.size() or count != categories.size() or \
			count != visible.size() or count > 16384:
		return empty
	var caps: PackedInt32Array = caps_for(quality)
	var ranges: PackedFloat64Array = ranges_for(quality)
	var minimums: PackedInt32Array = minimums_for(quality)
	var budget: int = budget_for(quality)
	var total_minimums: int = 0
	for group in 4:
		if minimums[group] < 0 or minimums[group] > caps[group]:
			return empty
		total_minimums += minimums[group]
	if total_minimums > budget:
		return empty
	for i in count:
		if not is_finite(distances[i]) or distances[i] < 0.0 or \
				priorities[i] > 3 or categories[i] > 3 or visible[i] > 1:
			return empty
	if native != null and native.has_method("select_effects_visible_fair"):
		var planned: PackedInt32Array = native.call("select_effects_visible_fair",
			distances, priorities, categories, visible, caps, ranges, minimums, budget)
		if planned.size() > 0 or count == 0 or budget == 0:
			return planned
		# A zero-length valid plan is legal (all candidates are distant).
		# The fallback repeats the exact planning policy in either case.
	var eligible: Array[int] = []
	for i in count:
		if distances[i] <= ranges[categories[i]] and caps[categories[i]] > 0:
			eligible.append(i)
	eligible.sort_custom(func(a: int, b: int) -> bool:
		if priorities[a] != priorities[b]:
			return priorities[a] > priorities[b]
		if visible[a] != visible[b]:
			return visible[a] > visible[b]
		if distances[a] != distances[b]:
			return distances[a] < distances[b]
		return a < b)
	var used := PackedInt32Array([0, 0, 0, 0])
	var claimed := PackedByteArray()
	claimed.resize(count)
	var result := PackedInt32Array()
	for stage in 3:
		for index in eligible:
			if result.size() >= budget:
				break
			if claimed[index] != 0:
				continue
			var group: int = categories[index]
			if used[group] >= caps[group]:
				continue
			if stage == 0 and priorities[index] != 3:
				continue
			if stage == 1 and used[group] >= minimums[group]:
				continue
			used[group] += 1
			claimed[index] = 1
			result.append(index)
	return result
