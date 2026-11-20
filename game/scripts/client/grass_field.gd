extends RefCounted
## A carpet of short grass over a whole chunk: thousands of procedural clumps (a few tapered blades each, no textures, no
## alpha cut-outs) in one MultiMesh, so it costs one draw call. Every clump has its own tint, the wind bends the tips,
## and near the edge of the view the blades sink into the ground instead of popping. Client-only: nothing blocks anyone.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Defs = preload("res://scripts/shared/defs.gd")

const SPACING := 0.55 # Metres between tuft candidates (jittered): dense enough that the soil barely shows.
const CLUMP_CELL := 3.2 # Size of the patches (Voronoi cells) that share a height and a shade.
const TILE := 16.0 # Each chunk is cut into tiles of this size, so the camera only draws the tiles it sees.
const FADE_START := 44.0 # Horizontal distance from the camera where the blades begin to sink, and where they are gone.
const FADE_END := 60.0
# Geometry LOD reduces GPU vertex work without changing tuft placement or the close-up silhouette.
# Hysteresis prevents distracting geometry switches when the camera moves near a boundary.
const LOD_BLADES := [18, 9, 4]
const LOD_SWITCH_DISTANCE := [24.0, 42.0]
const LOD_HYSTERESIS := 3.0
# Distance-dependent density is independent of mesh LOD to avoid abrupt gaps.
# A randomized buffer order ensures visible_instance_count removes plants
# across the whole tile instead of erasing its last rows.
const DENSITY_FIRST_START := 18.0
const DENSITY_FIRST_END := 34.0
const DENSITY_SECOND_START := 35.0
const DENSITY_SECOND_END := 55.0
const DENSITY_FIRST_DROP := 0.28
const DENSITY_SECOND_DROP := 0.32

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;
#include "res://assets/shaders/cloud_shadow.gdshaderinc"
#include "res://assets/shaders/vegetation_wind_space.gdshaderinc"
#include "res://assets/shaders/plant_interaction.gdshaderinc"
#include "res://assets/shaders/foliage_spectral_optics.gdshaderinc"
global uniform float aa_weather_wetness;
global uniform float aa_weather_rain;
global uniform vec3 aa_vegetation_wind;
// One renderer-wide intensity controls thin-blade backlighting for all grass tiles.
global uniform float aa_grass_transmission;
global uniform float aa_leaf_optics_quality;
// Quality-gated geometric-normal tilt, computed at the vertex without textures.
global uniform float aa_grass_normal_wind;
uniform float fade_start = 44.0;
uniform float fade_end = 60.0;
varying float tipness;
varying float shade;
varying float sheen;
varying float grass_light_fade;
varying vec3 tint;
varying vec2 ground_xz;
varying vec3 aa_world_grass_normal;
void vertex() {
	tipness = UV.y;
	shade = UV.x; // Each blade has its own brightness.
	tint = COLOR.rgb; // The MultiMesh instance colour (the Compatibility renderer does not pass custom data here).
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	ground_xz = root.xz;
	float shrink = 1.0 - smoothstep(fade_start, fade_end, length(root.xz - CAMERA_POSITION_WORLD.xz));
	grass_light_fade = shrink;
	VERTEX.y *= shrink;
	// Blades already sunk into the ground should not evaluate several wind trigonometric
	// waves per vertex. This matters because MultiMesh tiles are still alive in the
	// culling margin outside the shader fade range.
	sheen = 0.0;
	aa_world_grass_normal = vec3(0.0, 1.0, 0.0);
	if (shrink > 0.001) {
		float wind_power = clamp(aa_vegetation_wind.z, 0.0, 1.0);
		// Windless weather must not evaluate 3 wave functions per grass vertex.
		if (wind_power > 0.001) {
			// Wind: steady ripples with larger gusts, strongest at the tips.
			float k = UV.y * UV.y;
			vec2 wind_dir = aa_vegetation_wind.xy;
			vec2 crosswind = vec2(-wind_dir.y, wind_dir.x);
			float wave = TIME * (1.0 + wind_power * 0.6)
				+ dot(root.xz, wind_dir * 0.31 + crosswind * 0.08);
			float gust = sin(TIME * 0.7
				+ dot(root.xz, wind_dir * 0.045 + crosswind * 0.02)) * 0.5 + 0.5;
			gust *= gust;
			float storm_wind = 1.0 + clamp(aa_weather_rain, 0.0, 1.0) * 0.2;
			vec2 motion = wind_dir * (sin(wave) * 0.035 + gust * 0.11)
				+ crosswind * (cos(wave * 0.8) * 0.03 + gust * 0.05);
			vec2 world_bend = motion * k * shrink * storm_wind * wind_power;
			vec2 local_bend = aa_wind_world_to_local_xz(world_bend, MODEL_MATRIX);
			VERTEX.x += local_bend.x;
			VERTEX.z += local_bend.y;
			// Thin blades follow the bent world-space normal for subtle moving
			// sun highlights. Low presets leave the old upright normal unchanged.
			if (aa_grass_normal_wind > 0.001) {
				vec2 normal_slope = world_bend * (1.0 + UV.y) * aa_grass_normal_wind;
				aa_world_grass_normal = normalize(vec3(
					-normal_slope.x, 1.0, -normal_slope.y));
			}
			sheen = gust;
		}
		// Walkers press the blades down and aside; no cost while nothing is near (strength 0).
		vec2 pressed = aa_plant_displacement(root.xz, UV.y * UV.y * shrink, TIME);
		if (dot(pressed, pressed) > 0.00001) {
			vec2 pressed_local = aa_wind_world_to_local_xz(pressed, MODEL_MATRIX);
			VERTEX.x += pressed_local.x;
			VERTEX.z += pressed_local.y;
			VERTEX.y -= length(pressed) * 0.45;
		}
	}
	// Lit like the ground it grows from, so the carpet and the soil read as one surface.
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	// The root is the colour of the ground under it; the blade gets lighter and warmer toward the sunlit tip.
	vec3 tip = tint * 1.32 + vec3(0.04, 0.045, 0.0);
	vec3 color = mix(tint * 1.02, tip, smoothstep(0.0, 1.0, tipness));
	color *= mix(0.86, 1.1, shade);
	color *= mix(0.85, 1.0, smoothstep(0.0, 0.25, tipness)); // A little contact shade at the very bottom.
	color += vec3(0.04, 0.05, 0.015) * sheen * tipness;
	// A richer wet-grass palette at no additional texture sampling cost.
	float wet_grass = clamp(aa_weather_wetness, 0.0, 1.0);
	ALBEDO = apply_cloud_shadow(color * (1.0 - wet_grass * 0.16), ground_xz, TIME);
	// Approximate light transmission through thin grass, analogous to two-sided
	// foliage shading. BACKLIGHT uses actual scene lights rather than emission.
	// No extra texture reads, noise octaves, material copies or transparent pass.
	BACKLIGHT = vec3(0.0);
	if (aa_grass_transmission > 0.001 && grass_light_fade > 0.001) {
		float leaf_tip_mask = smoothstep(0.18, 0.92, tipness);
		// Thin tips transmit more sun than opaque roots. No new blade meshes,
		// textures, light passes or opaque/transparent pipeline changes.
		vec3 spectral = vec3(1.0);
		if (aa_leaf_optics_quality > 0.001) {
			float thickness = mix(1.28, 0.58, leaf_tip_mask);
			spectral = aa_foliage_spectral_filter(color, thickness,
				aa_leaf_optics_quality);
		}
		BACKLIGHT = color * leaf_tip_mask * spectral * aa_grass_transmission
			* grass_light_fade * (1.0 - wet_grass * 0.16);
	}
	ROUGHNESS = 0.85;
	// Always lit from above, whichever side of the blade we see: with two-sided blades the engine would otherwise flip
	// the normal of every back face downward and half the meadow would turn black.
	NORMAL = normalize((VIEW_MATRIX * vec4(aa_world_grass_normal, 0.0)).xyz);
}
"""

static var _meshes: Dictionary = {} # Blade count -> shared ArrayMesh; all tiles reuse three GPU meshes.
static var _material: ShaderMaterial

# Grass colour per biome (fresh, then dry); the lushness noise moves between them.
const BIOME_GRASS := {
	"forest": [Color(0.24, 0.37, 0.14), Color(0.31, 0.37, 0.16)],
	"plains": [Color(0.26, 0.4, 0.15), Color(0.42, 0.44, 0.21)],
	"swamp": [Color(0.22, 0.34, 0.14), Color(0.3, 0.36, 0.16)],
	"beach": [Color(0.42, 0.45, 0.25), Color(0.52, 0.5, 0.3)],
	"mountain": [Color(0.31, 0.39, 0.2), Color(0.39, 0.42, 0.24)],
}
# How much of the ground each biome covers.
const BIOME_DENSITY := {"forest": 0.95, "plains": 1.0, "swamp": 0.95, "beach": 0.25, "mountain": 0.6}


## 0..1: how lush the ground is here. Smooth noise from fixed hashes, so every client grows the same meadows.
static func lushness(x: float, z: float) -> float:
	var broad: float = _value_noise(x * 0.018, z * 0.018)
	var fine: float = _value_noise(x * 0.07 + 19.0, z * 0.07 - 7.0)
	return clampf(broad * 0.7 + fine * 0.3, 0.0, 1.0)


## The grass patches (Voronoi cells of jittered centres) around a chunk, precomputed once: per cell its centre, a height
## roll and a shade. Real grass grows in patches that share a height and a colour; random heights per tuft look messy
## (Ghost of Tsushima's grass talk).
class Clumps:
	var first: Vector2i
	var width: int
	var centers := PackedVector2Array()
	var rolls := PackedFloat32Array()
	var hues := PackedFloat32Array()

	func _init(origin: Vector2, size: float) -> void:
		first = Vector2i(floori(origin.x / CLUMP_CELL) - 1, floori(origin.y / CLUMP_CELL) - 1)
		width = int(size / CLUMP_CELL) + 4
		for j in width:
			for i in width:
				var cell := first + Vector2i(i, j)
				var jitter := Vector2(float(WorldGen.mix(cell.x, cell.y, 61, 2) % 1000), float(WorldGen.mix(cell.x, cell.y, 62, 2) % 1000)) / 1000.0
				centers.append((Vector2(cell) + jitter) * CLUMP_CELL)
				rolls.append(float(WorldGen.mix(cell.x, cell.y, 63, 2) % 1000) / 1000.0)
				hues.append(float(WorldGen.mix(cell.x, cell.y, 64, 2) % 1000) / 1000.0)

	## Index of the patch that holds a point.
	func at(x: float, z: float) -> int:
		var ci: int = floori(x / CLUMP_CELL) - first.x
		var cj: int = floori(z / CLUMP_CELL) - first.y
		var best := INF
		var found := 0
		for dj in range(-1, 2):
			var row: int = clampi(cj + dj, 0, width - 1) * width
			for di in range(-1, 2):
				var index: int = row + clampi(ci + di, 0, width - 1)
				var d: float = centers[index].distance_squared_to(Vector2(x, z))
				if d < best:
					best = d
					found = index
		return found


static func _value_noise(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - float(ix)
	var fz := z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a: float = float(WorldGen.mix(ix, iz, 41, 1) % 1000) / 1000.0
	var b: float = float(WorldGen.mix(ix + 1, iz, 41, 1) % 1000) / 1000.0
	var c: float = float(WorldGen.mix(ix, iz + 1, 41, 1) % 1000) / 1000.0
	var d: float = float(WorldGen.mix(ix + 1, iz + 1, 41, 1) % 1000) / 1000.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## One tuft: eighteen thin, curved blades leaning outwards. UV.y runs from root (0) to tip (1).
static func clump_mesh(blades: int = 18) -> ArrayMesh:
	blades = maxi(blades, 1)
	if _meshes.has(blades):
		return _meshes[blades]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for blade in blades:
		var angle := rng.randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var root := out * rng.randf_range(0.0, 0.34)
		var brightness := rng.randf()
		var height := rng.randf_range(0.18, 0.42)
		var lean := rng.randf_range(0.05, 0.17)
		var width := rng.randf_range(0.022, 0.034)
		var start := vertices.size()
		# Root pair, middle pair, tip: the blade bends further out near the top.
		var mid := root + out * lean * 0.35 + Vector3.UP * height * 0.55
		var tip := root + out * lean + Vector3.UP * height
		# Thin blades with narrow tips; many of them, so the clump reads as soft fuzz from above.
		for point in [[root - side * width, 0.0], [root + side * width, 0.0], [mid - side * width * 0.85, 0.55],
				[mid + side * width * 0.85, 0.55], [tip - side * width * 0.25, 1.0], [tip + side * width * 0.25, 1.0]]:
			vertices.append(point[0])
			uvs.append(Vector2(brightness, point[1]))
			normals.append(Vector3.UP)
		indices.append_array([start, start + 1, start + 2, start + 1, start + 3, start + 2, start + 2, start + 3, start + 4, start + 3, start + 5, start + 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[blades] = result
	return result


## Choose one of three blade counts using distance from a tile to the camera.
## A 3 m dead zone avoids oscillating between mesh variants when the view moves.
## Approximate on-screen tuft size using the camera's vertical focal length.
## 720p at 38 degrees is the original art-tuned reference. Clamp extreme
## resolutions to avoid making 4K rendering multiply grass cost without bound.
## Compatible with GL Compatibility and Forward+; no GPU query is needed.
static func screen_lod_scale(view_height: float, vertical_fov_degrees: float) -> float:
	if not is_finite(view_height) or not is_finite(vertical_fov_degrees):
		return 1.0
	if view_height <= 0.0 or vertical_fov_degrees <= 0.0 or vertical_fov_degrees >= 170.0:
		return 1.0
	var reference_focal: float = 720.0 / tan(deg_to_rad(38.0) * 0.5)
	var focal: float = view_height / tan(deg_to_rad(vertical_fov_degrees) * 0.5)
	return clampf(focal / reference_focal, 0.65, 1.6)


## Convert native Camera3D pixels-per-meter into a stable grass LOD
## distance. A 60% projection / 40% horizontal blend preserves the original
## ground-carpet placement while fixing over-detail on zoomed-out cliffs and
## under-detail on elevated terrain. Only values within the 720p reference
## range may extend quality; extra resolution is capped to avoid GPU spikes.
## This pure helper also works with a future orthographic camera.
static func projected_lod_distance(horizontal_distance: float,
		pixels_per_meter: float, focal_ratio: float) -> float:
	if not is_finite(horizontal_distance) or horizontal_distance < 0.0:
		return horizontal_distance
	if not is_finite(pixels_per_meter) or pixels_per_meter <= 0.0:
		return horizontal_distance
	if not is_finite(focal_ratio) or focal_ratio <= 0.0:
		return horizontal_distance
	var capped_ratio: float = clampf(focal_ratio, 0.65, 1.15)
	var effective_density: float = pixels_per_meter * capped_ratio / focal_ratio
	var reference_focal: float = 360.0 / tan(deg_to_rad(38.0) * 0.5)
	var projected_distance: float = reference_focal / maxf(effective_density, 0.001)
	return lerpf(horizontal_distance, projected_distance, 0.6)


## Scaling distances is equivalent to selecting LOD by projected screen
## coverage for the fixed-size grass blades. Preset fade range controls how
## long foliage should stay dense; screen resolution/FOV controls sharpness.
static func lod_for_distance(distance: float, previous: int = 0, range_scale: float = 1.0) -> int:
	var tier: int = clampi(previous, 0, LOD_BLADES.size() - 1)
	if not is_finite(distance) or distance < 0.0:
		return tier
	var scale: float = range_scale if is_finite(range_scale) and range_scale > 0.0 else 1.0
	while tier < LOD_BLADES.size() - 1 and distance >= (LOD_SWITCH_DISTANCE[tier] + LOD_HYSTERESIS) * scale:
		tier += 1
	while tier > 0 and distance <= (LOD_SWITCH_DISTANCE[tier - 1] - LOD_HYSTERESIS) * scale:
		tier -= 1
	return tier


## Avoid walking every tile when a stationary camera has not changed its
## pixel budget or when grass generation has made no progress. Changes smaller
## than 25 cm cannot materially affect 16-metre tile distance LOD thresholds.
static func needs_lod_refresh(previous_eye: Vector2, previous_scale: float,
		previous_tile_count: int, eye: Vector2, range_scale: float,
		tile_count: int) -> bool:
	if previous_tile_count != tile_count or previous_scale < 0.0:
		return true
	if not is_finite(range_scale) or not is_finite(previous_scale):
		return true
	return absf(previous_scale - range_scale) > 0.002 or previous_eye.distance_squared_to(eye) >= 0.0625


## The MultiMesh renderer draws only a prefix of each tuft buffer.
## Smooth ranges let distant grass thin gradually without any mesh rebuild.
## It never changes the number of gameplay entities or collision objects.
static func visible_count_for_distance(total: int, distance: float, range_scale: float = 1.0) -> int:
	if total <= 0:
		return 0
	if not is_finite(distance) or distance < 0.0:
		return total
	var scale: float = range_scale if is_finite(range_scale) and range_scale > 0.0 else 1.0
	var reference_distance: float = distance / scale
	var fraction: float = 1.0
	fraction -= DENSITY_FIRST_DROP * smoothstep(
		DENSITY_FIRST_START, DENSITY_FIRST_END, reference_distance)
	fraction -= DENSITY_SECOND_DROP * smoothstep(
		DENSITY_SECOND_START, DENSITY_SECOND_END, reference_distance)
	return clampi(ceili(float(total) * fraction), 1, total)


## Fisher-Yates is done once during each tile's budgeted construction.
## Crucial: move all 16 floats (12 transform + 4 tint) together; otherwise
## fractional visible_instance_count would delete whole spatial rows.
static func shuffle_instances(buffer: PackedFloat32Array, total: int, seed: int) -> void:
	if total < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(total - 1, 0, -1):
		var other: int = rng.randi_range(0, i)
		if other == i:
			continue
		var a: int = i * 16
		var b: int = other * 16
		for field in 16:
			var saved: float = buffer[a + field]
			buffer[a + field] = buffer[b + field]
			buffer[b + field] = saved


static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("fade_start", FADE_START)
		_material.set_shader_parameter("fade_end", FADE_END)
	return _material


## Everything one chunk's grass is grown from. The tiles are built one at a time (see ChunkView), so a chunk coming into
## view costs a few milliseconds per frame instead of a hitch.
## `heights`: samples × samples raw heights over the chunk; `biomes`: texels × texels biome names; `road`: the chunk's
## 1 m road mask (empty when no road crosses it); `patches`: paved sites as x, z, radius, layer.
class Source:
	var origin: Vector2
	var heights: PackedFloat32Array
	var samples: int
	var biomes: PackedStringArray
	var texels: int
	var road: PackedByteArray
	var patches: PackedVector4Array
	var clumps: Clumps

	func _init(p_origin: Vector2, p_heights: PackedFloat32Array, p_samples: int, p_biomes: PackedStringArray, p_texels: int,
			p_road: PackedByteArray, p_patches: PackedVector4Array) -> void:
		origin = p_origin
		heights = p_heights
		samples = p_samples
		biomes = p_biomes
		texels = p_texels
		road = p_road
		patches = p_patches
		clumps = Clumps.new(origin, Defs.CHUNK_SIZE)


static func tile_count() -> int:
	var side: int = int(Defs.CHUNK_SIZE / TILE)
	return side * side


## The grass of one 16 m tile of a chunk (one MultiMesh, one draw call), or null when nothing grows there.
static func build_tile(source: Source, tile: int) -> MultiMeshInstance3D:
	var size: float = Defs.CHUNK_SIZE
	var origin: Vector2 = source.origin
	var heights: PackedFloat32Array = source.heights
	var samples: int = source.samples
	var texels: int = source.texels
	var clumps: Clumps = source.clumps
	var tiles_per_side: int = int(size / TILE)
	var tile_x: float = float(tile % tiles_per_side) * TILE
	var tile_z: float = float(tile / tiles_per_side) * TILE
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.mix(int(origin.x), int(origin.y), 977, tile)
	var steps: int = int(TILE / SPACING)
	var height_step: float = size / float(samples - 1)
	var buffer := PackedFloat32Array()
	buffer.resize(steps * steps * 16) # 12 floats of transform + 4 of colour per tuft.
	var count := 0
	var low := INF
	var high := -INF
	for j in steps:
		for i in steps:
			var lx: float = tile_x + (float(i) + rng.randf()) * SPACING
			var lz: float = tile_z + (float(j) + rng.randf()) * SPACING
			var wx: float = origin.x + lx
			var wz: float = origin.y + lz
			if Vector2(wx, wz).length() < 21.0:
				continue # The hub plaza.
			# Old tracks are overgrown too, only thinner, so they still read as a way through.
			var on_road: bool = not source.road.is_empty() and source.road[mini(int(lz), int(size) - 1) * int(size) + mini(int(lx), int(size) - 1)] > 40
			if on_road and rng.randf() > 0.12:
				continue
			# Height: bilinear between the chunk's samples.
			var hx: float = lx / height_step
			var hz: float = lz / height_step
			var ix: int = mini(int(hx), samples - 2)
			var iz: int = mini(int(hz), samples - 2)
			var fx: float = hx - float(ix)
			var fz: float = hz - float(iz)
			var h00: float = heights[iz * samples + ix]
			var h10: float = heights[iz * samples + ix + 1]
			var h01: float = heights[(iz + 1) * samples + ix]
			var h11: float = heights[(iz + 1) * samples + ix + 1]
			var h: float = lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
			if h < Defs.WATER_LEVEL + 0.35 or h > 86.0:
				continue
			# Steep ground (cliffs) stays bare rock.
			if absf(h10 - h00) > 1.6 or absf(h01 - h00) > 1.6:
				continue
			var biome: String = source.biomes[mini(int(lz / size * float(texels - 1) + 0.5), texels - 1) * texels + mini(int(lx / size * float(texels - 1) + 0.5), texels - 1)]
			if h > 45.0:
				biome = "mountain"
			var lush: float = lushness(wx, wz)
			var keep: float = float(BIOME_DENSITY.get(biome, 0.8)) * lerpf(0.7, 1.0, lush)
			for patch in source.patches:
				if patch.z > 0.0 and Vector2(wx - patch.x, wz - patch.y).length() < patch.z * 0.8:
					keep *= 0.55 # Through the cracks of old pavement.
					break
			if rng.randf() > keep:
				continue
			var colors: Array = BIOME_GRASS.get(biome, BIOME_GRASS["plains"])
			var tint: Color = (colors[0] as Color).lerp(colors[1], clampf(1.0 - lush * 1.4 + rng.randf() * 0.3, 0.0, 1.0))
			tint = tint * rng.randf_range(0.94, 1.06)
			# The patch decides the height: short lawn, knee-high meadow, or tall grass up to the waist where it is lush.
			var clump: int = clumps.at(wx, wz)
			var roll: float = clumps.rolls[clump]
			var scale: float
			if roll < 0.18 + lush * 0.3:
				scale = rng.randf_range(2.6, 3.6)
			elif roll < 0.62:
				scale = rng.randf_range(1.3, 2.0)
			else:
				scale = rng.randf_range(0.55, 0.95)
			# Lower toward the patch edge, so tall patches have soft borders.
			var to_center: Vector2 = Vector2(wx, wz) - clumps.centers[clump]
			scale *= lerpf(1.0, 0.7, clampf(to_center.length() / (CLUMP_CELL * 0.8), 0.0, 1.0))
			tint = tint.lerp(tint * Color(1.08, 1.1, 0.92), clumps.hues[clump] * 0.6)
			# Taller, not wider: only the height follows the size, so tall tufts stay made of thin blades.
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.9, 1.15), scale, rng.randf_range(0.9, 1.15)))
			var at: int = count * 16
			buffer[at] = basis.x.x
			buffer[at + 1] = basis.y.x
			buffer[at + 2] = basis.z.x
			buffer[at + 3] = lx
			buffer[at + 4] = basis.x.y
			buffer[at + 5] = basis.y.y
			buffer[at + 6] = basis.z.y
			buffer[at + 7] = h - 0.04
			buffer[at + 8] = basis.x.z
			buffer[at + 9] = basis.y.z
			buffer[at + 10] = basis.z.z
			buffer[at + 11] = lz
			buffer[at + 12] = tint.r
			buffer[at + 13] = tint.g
			buffer[at + 14] = tint.b
			buffer[at + 15] = 1.0
			count += 1
			low = minf(low, h)
			high = maxf(high, h)
	if count == 0:
		return null
	buffer.resize(count * 16)
	# Randomize spatial order once. As draw count drops with distance, every
	# prefix remains scattered across the same tile, without rectangular gaps.
	shuffle_instances(buffer, count, WorldGen.mix(int(origin.x), int(origin.y), 981, tile))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = clump_mesh()
	multimesh.instance_count = count
	multimesh.buffer = buffer
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drawn only while the tile's centre is near the camera; the shader has sunk the blades by then.
	instance.visibility_range_end = FADE_END + 22.0
	instance.custom_aabb = AABB(Vector3(tile_x, low - 0.2, tile_z), Vector3(TILE, high - low + 1.4, TILE))
	return instance
