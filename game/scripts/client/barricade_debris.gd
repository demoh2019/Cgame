extends RefCounted
## Destroyed barricades burst into physical Voronoi debris (Chaos Geometry
## Collection style). Fracture patterns are baked once per LOD piece count
## and reused, so a siege does not re-run hull clipping per wall.

const VoronoiFracture = preload("res://scripts/shared/voronoi_fracture.gd")
const MeshFracture = preload("res://scripts/client/mesh_fracture.gd")

const PANEL := Vector3(1.6, 1.2, 0.3)
const MAX_PIECES := 12 # Cosmetic only: never more bodies than this per wall.
const LIFETIME := 6.0

static var _cache: Dictionary = {} # piece count -> fragments
static var _material: StandardMaterial3D = null


static func pieces_for(distance: float) -> int:
	return mini(MeshFracture.lod_count(distance), MAX_PIECES)


static func fragments(count: int) -> Array:
	if count < 2:
		return []
	if not _cache.has(count):
		if _material == null:
			_material = StandardMaterial3D.new()
			_material.albedo_color = Color(0.5, 0.36, 0.22)
			_material.roughness = 0.9
		var sites: PackedVector3Array = VoronoiFracture.random_sites(PANEL, count, 9001 + count)
		_cache[count] = MeshFracture.build_fragments(VoronoiFracture.fracture_box(PANEL, sites), _material)
	return _cache[count]


## Spawns debris at a broken wall; returns the bodies (empty when far away).
static func spawn(parent: Node3D, at: Vector3, viewer: Vector3, yaw: float = 0.0) -> Array:
	if parent == null or not at.is_finite():
		return []
	var parts: Array = fragments(pieces_for(at.distance_to(viewer)))
	if parts.is_empty():
		return []
	var origin := Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, PANEL.y * 0.5, 0.0))
	# The blow lands on the side facing the viewer, so pieces fly away from them.
	var toward: Vector3 = (viewer - at)
	toward.y = 0.0
	var impact: Vector3 = origin.origin + (toward.normalized() * 0.3 if toward.length() > 0.01 else Vector3.ZERO)
	return MeshFracture.spawn_debris(parent, origin, parts, impact, 4.0, LIFETIME)
