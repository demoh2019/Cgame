extends RefCounted
## Per-instance GPU culling for MultiMesh (Cgame engine, Forward+, `MultiMesh.gpu_culling`).
## Without it a MultiMesh is drawn whole whenever its combined AABB is visible, so a 16 m foliage tile
## submits instances behind the camera and past their draw distance. On engine builds without the
## feature this is a no-op and everything is drawn as before.


static func available() -> bool:
	# CGAME_GPU_CULLING=0 turns it off for A/B benchmarks.
	return ClassDB.class_has_method("MultiMesh", "set_gpu_culling") and OS.get_environment("CGAME_GPU_CULLING") != "0"


## Culls each instance against the camera frustum and `max_distance` metres (0 = no limit). From
## `density_start` metres the share of instances kept falls to `min_density` at `max_distance`, and the
## survivors grow so the ground stays covered (density LOD; 1.0 = off). Returns whether the engine supports it.
static func enable(multimesh: MultiMesh, max_distance: float = 0.0, density_start: float = 0.0,
		min_density: float = 1.0) -> bool:
	if multimesh == null or not available():
		return false
	multimesh.set("gpu_culling_distance", maxf(max_distance, 0.0))
	multimesh.set("gpu_culling_density_start", clampf(density_start, 0.0, maxf(max_distance, 0.0)))
	multimesh.set("gpu_culling_min_density", clampf(min_density, 0.0, 1.0))
	multimesh.set("gpu_culling", true)
	return true
