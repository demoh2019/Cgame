extends RefCounted
## Layered material generator: code shape, function injection, shader cache, instances, presets, compile check.

const MaterialLayers = preload("res://scripts/client/material_layers.gd")
const MaterialPresets = preload("res://scripts/client/material_presets.gd")


func _count(hay: String, needle: String) -> int:
	return hay.count(needle)


func _stack(rough: float = 0.8, mode: String = "height") -> Dictionary:
	return {"layers": [
		{"name": "base", "albedo": Color(0.4, 0.4, 0.4), "roughness": rough},
		{"name": "top", "albedo": Color(0.1, 0.5, 0.1), "roughness": 0.5, "triplanar": true,
			"blend": {"mode": mode, "channel": "g"}},
	]}


func run(t) -> void:
	MaterialLayers.clear_cache()

	t.current = "generated code"
	var stack := {"layers": [
		{"name": "Rock", "albedo": Color.GRAY},
		{"name": "moss", "albedo": Color.GREEN, "blend": {"mode": "slope"}},
		{"name": "dust", "albedo": Color.WHITE, "blend": {"mode": "noise"}},
		{"name": "stain", "albedo": Color.BLACK, "blend": {"mode": "mask_channel", "channel": "b"}},
		{"name": "gore", "albedo": Color.RED, "blend": {"mode": "vertex_color", "channel": "r"}},
		{"name": "tri", "albedo": "res://nonexistent_albedo.png", "normal": "res://nonexistent_n.png",
			"triplanar": true, "blend": {"mode": "height"}},
	]}
	var code := MaterialLayers.generate_shader_code(stack)
	t.check(code.begins_with("shader_type spatial;"), "starts with shader_type spatial")
	t.check(code.contains("uniform float l0_rock_roughness"), "layer 0 prefixed uniform")
	t.check(code.contains("uniform float l4_gore_blend_amount"), "later layer prefixed uniform")
	t.check(code.contains("smoothstep(l1_moss_slope_min"), "slope blend code")
	t.check(code.contains("1.0 - wn.y"), "slope uses world normal")
	t.check(code.contains("fn_hash_noise(wp * l2_dust_noise_scale)"), "noise blend code")
	t.check(code.contains("texture(l3_stain_mask_tex, UV).b"), "mask channel blend code")
	t.check(code.contains("COLOR.r"), "vertex colour blend code")
	t.check(code.contains("fn_triplanar(l5_tri_albedo_tex"), "triplanar sampling emitted")
	t.check(code.contains("fn_rnm_blend(acc_n"), "RNM normal blend by default")
	t.eq(_count(code, "float fn_height_blend("), 1, "height blend function injected once")
	t.eq(_count(code, "vec4 fn_triplanar("), 1, "triplanar function injected once")
	t.eq(_count(code, "float fn_hash_noise("), 1, "hash noise function injected once")
	t.eq(_count(code, "vec3 fn_rnm_blend("), 1, "RNM function injected once")
	t.eq(_count(code, "fn_udn_blend("), 0, "UDN not emitted for RNM stacks")
	var udn := MaterialLayers.generate_shader_code({"normal_blend": "udn", "functions": ["fn_hash_noise", "fn_udn_blend"],
		"layers": _stack()["layers"]})
	t.check(udn.contains("fn_udn_blend(acc_n"), "UDN blend selectable")
	t.eq(_count(udn, "vec3 fn_udn_blend("), 1, "explicit function request deduped")
	var custom := MaterialLayers.generate_shader_code({"functions": [{"name": "fn_x", "code": "float fn_x(float a) { return a; }"},
		{"name": "fn_x", "code": "float fn_x(float a) { return a; }"}], "layers": _stack()["layers"]})
	t.eq(_count(custom, "float fn_x("), 1, "custom function injected once")

	t.current = "compile check"
	var sh := Shader.new()
	sh.code = code
	var names: Array[String] = []
	for u in sh.get_shader_uniform_list():
		var info: Dictionary = u
		names.append(str(info["name"]))
	for expect in ["l0_rock_albedo", "l0_rock_roughness", "l1_moss_slope_min", "l1_moss_slope_max",
			"l2_dust_noise_threshold", "l3_stain_mask_tex", "l5_tri_albedo_tex", "l5_tri_normal_tex",
			"l5_tri_tri_sharp", "l4_gore_blend_contrast"]:
		t.check(names.has(expect), "compiled shader exposes uniform " + expect)
	t.check(not names.has("l0_rock_slope_min"), "no uniforms for unused modes")
	var sh2 := Shader.new()
	sh2.code = udn
	t.check(sh2.get_shader_uniform_list().size() > 0, "UDN variant compiles")

	t.current = "shader cache"
	MaterialLayers.clear_cache()
	var a := MaterialLayers.build_material(_stack(0.8))
	var b := MaterialLayers.build_material(_stack(0.2))
	t.check(a.shader == b.shader, "parameter-only change reuses the same Shader")
	t.eq(MaterialLayers.cache_size(), 1, "one cached shader")
	t.eq(MaterialLayers.cache_hits, 1, "one cache hit")
	t.near(float(a.get_shader_parameter("l0_base_roughness")), 0.8, 0.0001, "material A keeps its roughness")
	t.near(float(b.get_shader_parameter("l0_base_roughness")), 0.2, 0.0001, "material B has its own roughness")
	var c := MaterialLayers.build_material(_stack(0.8, "noise"))
	t.check(c.shader != a.shader, "structural change yields a different Shader")
	t.eq(MaterialLayers.cache_size(), 2, "two cached shaders")
	t.check(MaterialLayers.structure_key(_stack(0.1)) == MaterialLayers.structure_key(_stack(0.9)), "structure key ignores values")

	t.current = "material instances"
	var inst := MaterialLayers.instance(a, {"top/roughness": 0.05, "l0_base_roughness": 0.33})
	t.check(inst.shader == a.shader, "instance shares the base shader")
	t.near(float(inst.get_shader_parameter("l1_top_roughness")), 0.05, 0.0001, "layer/param override resolved")
	t.near(float(inst.get_shader_parameter("l0_base_roughness")), 0.33, 0.0001, "full-name override applied")
	t.near(float(a.get_shader_parameter("l0_base_roughness")), 0.8, 0.0001, "base material untouched")
	t.check(inst.get_shader_parameter("l1_top_albedo") == Color(0.1, 0.5, 0.1), "unoverridden params inherited")

	t.current = "presets"
	var presets := MaterialPresets.all()
	t.eq(presets.size(), 5, "five presets")
	for k in presets.keys():
		var pname: String = k
		var pstack: Dictionary = presets[pname]
		var mat := MaterialLayers.build_material(pstack)
		t.check(mat is ShaderMaterial, pname + " builds a ShaderMaterial")
		t.check(mat.shader != null and mat.shader.get_code() != "", pname + " has shader code")
		var uniforms := mat.shader.get_shader_uniform_list()
		t.check(uniforms.size() > 10, pname + " compiles with uniforms")
