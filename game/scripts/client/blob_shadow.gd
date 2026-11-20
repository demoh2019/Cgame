extends RefCounted
## Soft round "blob" contact shadows under characters for when real sun shadows
## are off (Performance tier) - the Diablo II / WoW Classic fallback that keeps
## characters grounded instead of floating. One shared mesh and material.

const GROUP := "aa_blob_shadows"
const NODE_NAME := &"BlobShadow"

static var _mesh: PlaneMesh


static func shared_mesh() -> PlaneMesh:
	if _mesh != null:
		return _mesh
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = -1
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2(1.3, 1.3)
	_mesh.material = m
	return _mesh


## Blob shadows show only while the real directional shadows are disabled.
static func wanted(sun_shadows_enabled: bool) -> bool:
	return not sun_shadows_enabled


static func make(visible: bool) -> MeshInstance3D:
	var blob := MeshInstance3D.new()
	blob.name = NODE_NAME
	blob.mesh = shared_mesh()
	blob.position.y = 0.04
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.visible = visible
	blob.add_to_group(GROUP)
	return blob
