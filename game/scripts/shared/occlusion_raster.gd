extends RefCounted
## Software occlusion culling: low-res depth rasteriser plus a max-depth Hi-Z pyramid.
##
## Concepts (not code) follow:
##  - Intel "Masked Software Occlusion Culling" (Hasselgren et al., HPG 2016; the reference
##    library is Apache-2.0, https://github.com/GameTechDev/MaskedOcclusionCulling). This file is
##    an independent GDScript implementation: occluders are rasterised into a tiny conservative
##    depth buffer and occludees are tested by their screen-space bounding rectangle and nearest depth.
##  - Hi-Z culling from the "GPU-driven rendering pipelines" talks (Haar & Aaltonen, SIGGRAPH 2015):
##    a max-depth mip chain lets one test touch only a few texels whatever the box size.
## No third-party source was copied.
##
## Depth is view distance (clip-space w), so it is linear and independent of the engine's
## reversed-Z / GL / D3D clip conventions. Perspective projections only. Larger = farther;
## empty texels hold INF (nothing occludes). All results are conservative: when unsure, visible.
##
## Usage per frame: begin(view_proj, w, h) -> rasterize_occluder(...)* -> is_visible / test_many.

const NEAR_W := 0.05  ## clip-space w below which geometry is clipped (occluders) or assumed visible (occludees)
const DEPTH_BIAS := 0.01  ## relative push of occluder depth away from the camera (partial pixel coverage)

var width: int = 0
var height: int = 0
var view_proj: Projection = Projection.IDENTITY

## Statistics, reset by begin().
var tested: int = 0
var culled: int = 0
var occluder_triangles: int = 0
var pixels_written: int = 0

var _depth: PackedFloat32Array = PackedFloat32Array()
var _levels: Array[PackedFloat32Array] = []
var _level_w: PackedInt32Array = PackedInt32Array()
var _level_h: PackedInt32Array = PackedInt32Array()
var _hiz_dirty: bool = true
var _prev_depth: PackedFloat32Array = PackedFloat32Array()
var _prev_w: int = 0
var _prev_h: int = 0
var _has_prev: bool = false


func begin(p_view_proj: Projection, p_width: int = 256, p_height: int = 128) -> void:
	if _depth.size() > 0:
		_prev_depth = _depth
		_prev_w = width
		_prev_h = height
		_has_prev = true
	view_proj = p_view_proj
	width = maxi(1, p_width)
	height = maxi(1, p_height)
	_depth = PackedFloat32Array()
	_depth.resize(width * height)
	_depth.fill(INF)
	_hiz_dirty = true
	tested = 0
	culled = 0
	occluder_triangles = 0
	pixels_written = 0


## Rasterises triangles (world space, 3 vertices each, double sided) into the depth buffer.
func rasterize_occluder(triangles: PackedVector3Array) -> void:
	var tri_count: int = triangles.size() / 3
	for i in tri_count:
		var poly: Array[Vector4] = [
			view_proj * Vector4(triangles[i * 3].x, triangles[i * 3].y, triangles[i * 3].z, 1.0),
			view_proj * Vector4(triangles[i * 3 + 1].x, triangles[i * 3 + 1].y, triangles[i * 3 + 1].z, 1.0),
			view_proj * Vector4(triangles[i * 3 + 2].x, triangles[i * 3 + 2].y, triangles[i * 3 + 2].z, 1.0),
		]
		poly = _clip_near(poly)
		if poly.size() < 3:
			continue
		occluder_triangles += 1
		var pts: PackedVector3Array = PackedVector3Array()
		for v in poly:
			pts.append(_to_screen(v))
		for k in range(1, pts.size() - 1):
			_raster_tri(pts[0], pts[k], pts[k + 1])
	_hiz_dirty = true


## Optional: seed the current buffer with last frame's depth reprojected through its matrix.
## Call after begin() and before rasterize_occluder(). Approximate (disocclusions can leak stale
## occluders), so depth is pushed 5% farther and only finite single texels are splatted.
func temporal_reproject(prev_view_proj: Projection) -> void:
	if not _has_prev or _prev_depth.size() != _prev_w * _prev_h:
		return
	var inv: Projection = prev_view_proj.inverse()
	for y in _prev_h:
		for x in _prev_w:
			var d: float = _prev_depth[y * _prev_w + x]
			if d == INF:
				continue
			# Unproject: ndc xy at this texel, w = d. Clip = (ndc.xy * d, z unknown, d); recover z via the
			# projection's linear relation by solving with the inverse on a point along the pixel ray.
			var ndc_x: float = (float(x) + 0.5) / float(_prev_w) * 2.0 - 1.0
			var ndc_y: float = 1.0 - (float(y) + 0.5) / float(_prev_h) * 2.0
			var world: Vector3 = _unproject_at_w(inv, prev_view_proj, ndc_x, ndc_y, d)
			var clip: Vector4 = view_proj * Vector4(world.x, world.y, world.z, 1.0)
			if clip.w <= NEAR_W:
				continue
			var s: Vector3 = _to_screen(clip)
			var px: int = int(floor(s.x))
			var py: int = int(floor(s.y))
			if px < 0 or py < 0 or px >= width or py >= height:
				continue
			var nd: float = clip.w * 1.05
			if nd < _depth[py * width + px]:
				_depth[py * width + px] = nd
	_hiz_dirty = true


## Builds the max-depth mip pyramid. Called lazily by the tests when stale.
func build_hiz() -> void:
	_levels.clear()
	_level_w = PackedInt32Array()
	_level_h = PackedInt32Array()
	_levels.append(_depth)
	_level_w.append(width)
	_level_h.append(height)
	var cw: int = width
	var ch: int = height
	while cw > 1 or ch > 1:
		var nw: int = (cw + 1) >> 1
		var nh: int = (ch + 1) >> 1
		var src: PackedFloat32Array = _levels[_levels.size() - 1]
		var dst: PackedFloat32Array = PackedFloat32Array()
		dst.resize(nw * nh)
		for y in nh:
			var y0: int = y * 2
			var y1: int = mini(y0 + 1, ch - 1)
			for x in nw:
				var x0: int = x * 2
				var x1: int = mini(x0 + 1, cw - 1)
				dst[y * nw + x] = maxf(maxf(src[y0 * cw + x0], src[y0 * cw + x1]), maxf(src[y1 * cw + x0], src[y1 * cw + x1]))
		_levels.append(dst)
		_level_w.append(nw)
		_level_h.append(nh)
		cw = nw
		ch = nh
	_hiz_dirty = false


func hiz_level_count() -> int:
	if _hiz_dirty:
		build_hiz()
	return _levels.size()


func hiz_size(level: int) -> Vector2i:
	if _hiz_dirty:
		build_hiz()
	return Vector2i(_level_w[level], _level_h[level])


func hiz_get(level: int, x: int, y: int) -> float:
	if _hiz_dirty:
		build_hiz()
	return _levels[level][y * _level_w[level] + x]


## True when the box may be visible (not provably hidden). Counts into tested/culled.
func is_visible(aabb: AABB) -> bool:
	tested += 1
	var visible: bool = _test(aabb)
	if not visible:
		culled += 1
	return visible


## Batch test (GPU-instance-culling style): one byte per AABB, 1 = visible, 0 = occluded.
func test_many(aabbs: Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(aabbs.size())
	if _hiz_dirty:
		build_hiz()
	for i in aabbs.size():
		var bb: AABB = aabbs[i]
		out[i] = 1 if is_visible(bb) else 0
	return out


func _test(aabb: AABB) -> bool:
	if _hiz_dirty:
		build_hiz()
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	var nearest: float = INF
	var p: Vector3 = aabb.position
	var e: Vector3 = aabb.size
	for c in 8:
		var corner: Vector3 = Vector3(
			p.x + (e.x if (c & 1) != 0 else 0.0),
			p.y + (e.y if (c & 2) != 0 else 0.0),
			p.z + (e.z if (c & 4) != 0 else 0.0))
		var clip: Vector4 = view_proj * Vector4(corner.x, corner.y, corner.z, 1.0)
		if clip.w <= NEAR_W:
			return true  # crossing or behind the near plane: cannot bound the rect, stay conservative
		var s: Vector3 = _to_screen(clip)
		min_x = minf(min_x, s.x)
		max_x = maxf(max_x, s.x)
		min_y = minf(min_y, s.y)
		max_y = maxf(max_y, s.y)
		nearest = minf(nearest, clip.w)
	# Fully off-screen is a frustum-culling matter, not occlusion.
	if max_x < 0.0 or max_y < 0.0 or min_x > float(width) or min_y > float(height):
		return true
	# Expand by one pixel: occluder coverage is sampled at pixel centres.
	var x0: int = clampi(int(floor(min_x)) - 1, 0, width - 1)
	var x1: int = clampi(int(floor(max_x)) + 1, 0, width - 1)
	var y0: int = clampi(int(floor(min_y)) - 1, 0, height - 1)
	var y1: int = clampi(int(floor(max_y)) + 1, 0, height - 1)
	var size: int = maxi(x1 - x0 + 1, y1 - y0 + 1)
	var level: int = clampi(ceili(log(float(size)) / log(2.0)) - 1, 0, _levels.size() - 1)
	var lw: int = _level_w[level]
	var lh: int = _level_h[level]
	var tx0: int = clampi(x0 >> level, 0, lw - 1)
	var tx1: int = clampi(x1 >> level, 0, lw - 1)
	var ty0: int = clampi(y0 >> level, 0, lh - 1)
	var ty1: int = clampi(y1 >> level, 0, lh - 1)
	var buf: PackedFloat32Array = _levels[level]
	var far_most: float = 0.0
	for ty in range(ty0, ty1 + 1):
		for tx in range(tx0, tx1 + 1):
			far_most = maxf(far_most, buf[ty * lw + tx])
	# Occluded only when even the box's nearest point is behind the farthest occluder in the region.
	return not (nearest > far_most)


func _to_screen(clip: Vector4) -> Vector3:
	var inv_w: float = 1.0 / clip.w
	return Vector3(
		(clip.x * inv_w * 0.5 + 0.5) * float(width),
		(0.5 - clip.y * inv_w * 0.5) * float(height),
		inv_w)


## Sutherland-Hodgman against the plane w = NEAR_W.
func _clip_near(poly: Array[Vector4]) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var n: int = poly.size()
	for i in n:
		var a: Vector4 = poly[i]
		var b: Vector4 = poly[(i + 1) % n]
		var da: float = a.w - NEAR_W
		var db: float = b.w - NEAR_W
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			var t: float = da / (da - db)
			out.append(a.lerp(b, t))
	return out


## Edge-function rasteriser. Vertices are (screen x, screen y, 1/w). Pixel centres only; keeps nearest.
func _raster_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var area: float = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if absf(area) < 1e-9:
		return
	var inv_area: float = 1.0 / area
	var x_min: int = maxi(0, int(floor(minf(a.x, minf(b.x, c.x)))))
	var x_max: int = mini(width - 1, int(ceil(maxf(a.x, maxf(b.x, c.x)))))
	var y_min: int = maxi(0, int(floor(minf(a.y, minf(b.y, c.y)))))
	var y_max: int = mini(height - 1, int(ceil(maxf(a.y, maxf(b.y, c.y)))))
	for y in range(y_min, y_max + 1):
		var py: float = float(y) + 0.5
		for x in range(x_min, x_max + 1):
			var px: float = float(x) + 0.5
			var wa: float = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) * inv_area
			var wb: float = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) * inv_area
			var wc: float = 1.0 - wa - wb
			if wa < 0.0 or wb < 0.0 or wc < 0.0:
				continue
			var inv_w: float = wa * a.z + wb * b.z + wc * c.z
			if inv_w <= 0.0:
				continue
			var depth: float = (1.0 / inv_w) * (1.0 + DEPTH_BIAS)
			var idx: int = y * width + x
			if depth < _depth[idx]:
				if _depth[idx] == INF:
					pixels_written += 1
				_depth[idx] = depth


## World position whose clip w equals `w` along the pixel ray (ndc_x, ndc_y) of `vp` (inverse = `inv`).
func _unproject_at_w(inv: Projection, vp: Projection, ndc_x: float, ndc_y: float, w: float) -> Vector3:
	# Two points on the ray (clip z = 0 and z = w in the same w), then pick the one whose w matches.
	var p0: Vector4 = inv * Vector4(ndc_x, ndc_y, 0.0, 1.0)
	var p1: Vector4 = inv * Vector4(ndc_x, ndc_y, 0.5, 1.0)
	var a: Vector3 = Vector3(p0.x, p0.y, p0.z) / p0.w
	var b: Vector3 = Vector3(p1.x, p1.y, p1.z) / p1.w
	var wa: float = (vp * Vector4(a.x, a.y, a.z, 1.0)).w
	var wb: float = (vp * Vector4(b.x, b.y, b.z, 1.0)).w
	if absf(wb - wa) < 1e-6:
		return a
	return a.lerp(b, (w - wa) / (wb - wa))
