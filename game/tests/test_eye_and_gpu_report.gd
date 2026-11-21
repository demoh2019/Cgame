extends RefCounted
## Eye shader uniforms, eye material factory, GPU resource report.

const EyeMaterial = preload("res://scripts/client/eye_material.gd")
const GpuResourceReport = preload("res://scripts/client/gpu_resource_report.gd")


func run(t) -> void:
	t.current = "eye shader"
	var shader := load("res://assets/shaders/eye.gdshader") as Shader
	t.check(shader != null, "eye shader loads")
	var names: Array[String] = []
	if shader != null:
		for u: Dictionary in shader.get_shader_uniform_list():
			names.append(String(u["name"]))
	for expected in ["iris_texture", "iris_color", "sclera_color", "pupil_size", "iris_radius", "limbus_width",
			"cornea_ior", "iris_depth", "wetness", "sclera_scatter"]:
		t.check(names.has(expected), "uniform %s exposed" % expected)

	t.current = "eye material"
	var a := EyeMaterial.make(Color(0.2, 0.5, 0.3), 42)
	var b := EyeMaterial.make(Color(0.2, 0.5, 0.3), 42)
	var c := EyeMaterial.make(Color(0.2, 0.5, 0.3), 43)
	t.check(a.shader == shader, "material uses eye shader")
	t.eq(a.get_shader_parameter("fibre_seed"), b.get_shader_parameter("fibre_seed"), "same seed is deterministic")
	t.eq(a.get_shader_parameter("iris_color"), b.get_shader_parameter("iris_color"), "same seed same colour")
	t.check(a.get_shader_parameter("fibre_seed") != c.get_shader_parameter("fibre_seed"), "different seed varies")
	var dark := EyeMaterial.set_dilation(a, 0.0)
	var bright := EyeMaterial.set_dilation(a, 1.0)
	t.check(dark > bright, "pupil dilates in the dark")
	t.near(float(a.get_shader_parameter("pupil_size")), bright, 0.0001, "parameter holds last dilation")
	t.check(EyeMaterial.pupil_for_light(0.3) < EyeMaterial.pupil_for_light(0.1), "monotonic with light")
	t.near(EyeMaterial.pupil_for_light(5.0), EyeMaterial.pupil_for_light(1.0), 0.0001, "light clamped")
	t.eq(EyeMaterial.blink_occlusion(1.0, 4.0, 0.2), 0.0, "eye open between blinks")
	t.near(EyeMaterial.blink_occlusion(0.07, 4.0, 0.2), 1.0, 0.0001, "closed at the blink peak")
	t.check(EyeMaterial.blink_occlusion(0.15, 4.0, 0.2) < 1.0, "reopens after the peak")
	t.near(EyeMaterial.apply_blink(a, 0.07, 4.0, 0.2), float(a.get_shader_parameter("blink_occlusion")), 0.0001, "apply_blink sets uniform")

	t.current = "texture bytes"
	t.eq(GpuResourceReport.texture_bytes(64, 64, Image.FORMAT_RGBA8, false), 16384, "RGBA8 64x64")
	t.eq(GpuResourceReport.texture_bytes(4, 4, Image.FORMAT_RGBA8, true), 64 + 16 + 4, "RGBA8 mip chain 4x4")
	t.eq(GpuResourceReport.texture_bytes(256, 256, Image.FORMAT_DXT1, false), 32768, "DXT1 is 4 bpp")
	t.eq(GpuResourceReport.texture_bytes(256, 256, Image.FORMAT_DXT5, false), 65536, "DXT5 is 8 bpp")
	t.eq(GpuResourceReport.texture_bytes(16, 16, Image.FORMAT_RGBAF, false), 4096, "RGBAF 128 bpp")
	t.eq(GpuResourceReport.texture_bytes(2, 2, Image.FORMAT_DXT1, false), 8, "compressed min block 4x4")
	t.eq(GpuResourceReport.texture_bytes(0, 8, Image.FORMAT_L8, false), 0, "empty texture")
	t.eq(GpuResourceReport.texture_bytes(8, 8, Image.FORMAT_L8, false, 6), 384, "layers multiply")

	t.current = "gpu report"
	var root := Node3D.new()
	var box := BoxMesh.new()
	box.resource_name = "box"
	var sphere := SphereMesh.new()
	sphere.resource_name = "sphere"
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	tex.resource_name = "tex32"
	var big_img := Image.create(128, 64, false, Image.FORMAT_RGB8)
	var big_tex := ImageTexture.create_from_image(big_img)
	big_tex.resource_name = "tex128"
	var std := StandardMaterial3D.new()
	std.albedo_texture = tex
	var smat := ShaderMaterial.new()
	smat.shader = shader
	smat.set_shader_parameter("iris_texture", big_tex)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = std
		root.add_child(mi)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = sphere
	mi2.material_override = smat
	root.add_child(mi2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = 10
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)
	var spr := Sprite3D.new()
	spr.texture = tex
	root.add_child(spr)
	var particles := GPUParticles3D.new()
	particles.amount = 8
	particles.draw_pass_1 = sphere
	root.add_child(particles)

	var report := GpuResourceReport.new()
	var snap := report.collect(root)
	var totals: Dictionary = snap["totals"]
	var nodes: Dictionary = snap["nodes"]
	t.eq(int(nodes["MeshInstance3D"]), 4, "mesh instance count")
	t.eq(int(nodes["MultiMeshInstance3D"]), 1, "multimesh count")
	t.eq(int(nodes["Sprite3D"]), 1, "sprite count")
	t.eq(int(nodes["GPUParticles3D"]), 1, "particles count")
	t.eq(int(totals["mesh_count"]), 2, "meshes deduplicated (box + sphere)")
	t.eq(int(totals["texture_count"]), 2, "textures deduplicated")
	t.eq(int(totals["material_count"]), 2, "materials deduplicated")
	t.eq(int(totals["shader_count"]), 1, "one custom shader (BaseMaterial3D is built in)")
	t.check(int(totals["vertices"]) > 0 and int(totals["indices"]) > 0, "vertex and index counts present")
	t.eq(int(totals["texture_bytes"]), 4096 + 24576, "texture bytes summed")
	t.eq(int(totals["instance_bytes"]), 10 * 48 + 8 * 96, "multimesh + particle buffers")
	t.check(int(totals["estimated_bytes"]) > int(totals["texture_bytes"]), "estimate includes meshes")
	t.check((snap["rendering"] as Dictionary).has("video_mem"), "rendering totals present")
	var box_entry := _find(snap["meshes"], "box")
	t.check(int(box_entry["users"]) >= 4, "box users counted")

	var top_tex := report.top(5, "textures")
	t.eq(top_tex.size(), 2, "top returns all when n larger")
	t.eq(String(top_tex[0]["name"]), "tex128", "largest texture first")
	t.eq(report.top(1, "textures").size(), 1, "top limited to n")
	t.eq(report.top(3, "bogus").size(), 0, "unknown kind is empty")
	var mesh_top := report.top(2, "meshes")
	t.check(int(mesh_top[0]["bytes"]) >= int(mesh_top[1]["bytes"]), "meshes sorted descending")
	var mat_top := report.top(2, "materials")
	t.check(int(mat_top[0]["bytes"]) >= int(mat_top[1]["bytes"]), "materials sorted descending")

	t.current = "gpu timeline"
	report.timeline_capacity = 4
	for i in 10:
		report.timeline_push()
	var tl := report.timeline()
	t.eq(tl.size(), 4, "timeline bounded by capacity")
	t.eq(int(tl[0]["seq"]), 6, "oldest retained sample")
	t.eq(int(tl[3]["seq"]), 9, "newest last")
	t.check(report.timeline_peak("estimated_bytes") > 0, "estimate tracked in timeline")

	t.current = "gpu markdown"
	var md := report.to_markdown(3)
	t.check(md.contains("# GPU resource report"), "markdown title")
	t.check(md.contains("## Top textures") and md.contains("tex128"), "top textures section")
	t.check(md.contains("## VRAM timeline"), "timeline section")
	t.check(md.contains("Estimated total"), "totals line")
	t.eq(GpuResourceReport.format_bytes(2048), "2.0 KiB", "format KiB")
	var empty := GpuResourceReport.new()
	t.eq(empty.collect(null)["meshes"].size(), 0, "null root is empty")

	root.free()


func _find(entries: Array, name: String) -> Dictionary:
	for e: Dictionary in entries:
		if String(e["name"]) == name:
			return e
	return {}
