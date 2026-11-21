extends RefCounted
## Native SignificanceBudgetPlanner parity and stock-Godot fallback for VFX.
## Never used for gameplay authority, hit validation, audio or networking.

const MAX_DISTANCE := 140.0
const FRAME_BUDGET := [8, 12, 18, 24]
## Hard upper bound on particles requested from the pooled cosmetic VFX queue.
const PARTICLE_BUDGET := [96, 160, 256, 384]
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


static func particle_budget_for(quality: int) -> int:
	return PARTICLE_BUDGET[clampi(quality, 0, 3)]


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

## Dual-budget effect admission. This is not an allocation/CPU timing estimate:
## one requested CPUParticles3D particle counts as one unit of visual work.
## Critical effects retain their strict priority; effects that do not fit
## leave space for cheaper lower-priority feedback in the same frame.
static func select_visible_costed_indices(distances: PackedFloat64Array,
		priorities: PackedByteArray, categories: PackedByteArray,
		visible: PackedByteArray, particle_costs: PackedInt32Array,
		quality: int, native: Object = null) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var n: int = distances.size()
	if n != priorities.size() or n != categories.size() 			or n != visible.size() or n != particle_costs.size() or n > 16384:
		return empty
	for i in n:
		if not is_finite(distances[i]) or distances[i] < 0.0 				or priorities[i] > 3 or categories[i] > 3 or visible[i] > 1 				or particle_costs[i] < 1 or particle_costs[i] > 4096:
			return empty
	var caps: PackedInt32Array = caps_for(quality)
	var budget: int = budget_for(quality)
	var particle_budget: int = particle_budget_for(quality)
	if native != null and native.has_method("select_effects_visible_costed"):
		return native.call("select_effects_visible_costed", distances, priorities,
			categories, visible, particle_costs, caps, budget, MAX_DISTANCE,
			particle_budget)
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
		return a < b
	)
	var used := PackedInt32Array([0, 0, 0, 0])
	var remaining: int = particle_budget
	var output := PackedInt32Array()
	for index in eligible:
		if output.size() >= budget or remaining == 0:
			break
		var group: int = int(categories[index])
		if used[group] >= caps[group] or particle_costs[index] > remaining:
			continue
		remaining -= particle_costs[index]
		used[group] += 1
		output.append(index)
	return output
