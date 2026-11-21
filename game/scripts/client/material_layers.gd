extends RefCounted
## Layered material authoring: turns a layer-stack description into Godot 4 spatial shader source.
##
## Stack format:
##   {"normal_blend": "rnm"|"udn", "functions": ["fn_name" | {"name": String, "code": String}],
##    "layers": [{"name", "albedo": Color|texture path, "tint": Color, "normal": texture path,
##                "roughness", "metallic", "normal_strength", "uv_scale", "height", "height_var",
##                "triplanar": bool, "triplanar_sharpness",
##                "blend": {"mode": "height"|"slope"|"noise"|"mask_channel"|"vertex_color",
##                          "amount", "contrast", "min", "max", "invert", "scale", "threshold",
##                          "softness", "channel": "r|g|b|a", "texture": path}}]}
## Layer 0 is the base (its blend is ignored); each later layer is blended over the accumulated result,
## with a height-contest (Unreal "height lerp"/Substance height blend) applied to the blend weight.
##
## Shader Permutation Reduction: only the stack STRUCTURE (layer count/names, texture-vs-color slots,
## blend modes/channels, triplanar flags, functions) changes the generated code. All numeric values are
## uniforms, so parameter-only differences reuse one cached Shader; build_material() / instance() just
## set shader parameters (a Material Instance shares the parent Shader).
##
## Sources / credits (techniques re-implemented from the published math, no third-party code pasted
## except as noted; no GPL/LGPL and no Apache-2.0 code used):
##  - Hash without Sine (hash13 constants): Dave Hoskins, https://www.shadertoy.com/view/4djSRW, MIT.
##  - Reoriented Normal Mapping & UDN blend: Colin Barre-Brisebois and Stephen Hill, "Blending in Detail",
##    https://blog.selfshadow.com/publications/blending-in-detail/ (formulas; reimplemented).
##  - Triplanar mapping: Ben Golus, "Normal Mapping for a Triplanar Shader" (technique; reimplemented).
##  - Height-lerp blend: Bruno Opsenica "Advanced Terrain Texture Splatting" (technique; reimplemented).
##  - Layer-stack/instance model: Unreal Engine Material Layers / Material Functions concept (design only).

const MODE_HEIGHT := "height"
const MODE_SLOPE := "slope"
const MODE_NOISE := "noise"
const MODE_MASK := "mask_channel"
const MODE_VERTEX_COLOR := "vertex_color"

## Material function library: name -> {"deps": Array, "code": String}. Injected once per shader.
const FN_LIBRARY := {
	"fn_hash_noise": {
		"deps": [],
		"code": """float fn_hash13(vec3 p) {
	vec3 p3 = fract(p * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float fn_hash_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = fn_hash13(i);
	float n100 = fn_hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = fn_hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = fn_hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = fn_hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = fn_hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = fn_hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = fn_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
""",
	},
	"fn_height_blend": {
		"deps": [],
		"code": """float fn_height_blend(float h_base, float h_top, float w, float contrast) {
	float depth = 0.5 / max(contrast, 0.5);
	float a = h_base + (1.0 - w);
	float b = h_top + w;
	float m = max(a, b) - depth;
	float wa = max(a - m, 0.0);
	float wb = max(b - m, 0.0);
	return clamp(wb / (wa + wb + 0.00001), 0.0, 1.0);
}
""",
	},
	"fn_triplanar": {
		"deps": [],
		"code": """vec4 fn_triplanar(sampler2D tex, vec3 pos, vec3 nrm, float scale, float sharp) {
	vec3 w = pow(abs(nrm), vec3(sharp));
	w /= (w.x + w.y + w.z + 0.00001);
	vec4 cx = texture(tex, pos.zy * scale);
	vec4 cy = texture(tex, pos.xz * scale);
	vec4 cz = texture(tex, pos.xy * scale);
	return cx * w.x + cy * w.y + cz * w.z;
}
""",
	},
	"fn_rnm_blend": {
		"deps": [],
		"code": """vec3 fn_rnm_blend(vec3 n1, vec3 n2) {
	vec3 t = n1 + vec3(0.0, 0.0, 1.0);
	vec3 u = n2 * vec3(-1.0, -1.0, 1.0);
	return normalize(t * dot(t, u) / max(t.z, 0.0001) - u);
}
""",
	},
	"fn_udn_blend": {
		"deps": [],
		"code": """vec3 fn_udn_blend(vec3 n1, vec3 n2) {
	return normalize(vec3(n1.xy + n2.xy, n1.z));
}
""",
	},
}

static var _cache: Dictionary = {}
static var cache_hits: int = 0
static var cache_builds: int = 0


# --- public API -------------------------------------------------------------------------------

static func function_names() -> Array:
	return FN_LIBRARY.keys()


static func get_function(fn_name: String) -> String:
	if not FN_LIBRARY.has(fn_name):
		return ""
	var entry: Dictionary = FN_LIBRARY[fn_name]
	return str(entry["code"])


static func layer_prefix(stack: Dictionary, index: int) -> String:
	var layers: Array = stack.get("layers", [])
	var layer: Dictionary = layers[index]
	return "l%d_%s_" % [index, _sanitize(str(layer.get("name", "layer")))]


static func generate_shader_code(stack: Dictionary) -> String:
	var layers: Array = stack.get("layers", [])
	var out: Array[String] = []
	out.append("shader_type spatial;")
	out.append("// Generated by material_layers.gd - do not edit; change the stack description instead.")
	out.append("")
	out.append("varying vec3 v_world_pos;")
	out.append("varying vec3 v_world_normal;")
	out.append("")
	for i in layers.size():
		out.append_array(_layer_uniforms(stack, i))
	out.append("")
	# Material functions: each injected exactly once, dependencies first.
	for fn_code in _collect_function_code(stack):
		out.append(fn_code)
	out.append("void vertex() {")
	out.append("\tv_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;")
	out.append("\tv_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);")
	out.append("}")
	out.append("")
	out.append("void fragment() {")
	out.append("\tvec3 wp = v_world_pos;")
	out.append("\tvec3 wn = normalize(v_world_normal);")
	out.append("\tvec3 acc_albedo = vec3(0.5);")
	out.append("\tfloat acc_rough = 0.5;")
	out.append("\tfloat acc_metal = 0.0;")
	out.append("\tfloat acc_h = 0.5;")
	out.append("\tvec3 acc_n = vec3(0.0, 0.0, 1.0);")
	var nb_fn := "fn_udn_blend" if _normal_mode(stack) == "udn" else "fn_rnm_blend"
	for i in layers.size():
		out.append_array(_layer_fragment(stack, i, nb_fn))
	out.append("\tALBEDO = acc_albedo;")
	out.append("\tROUGHNESS = clamp(acc_rough, 0.0, 1.0);")
	out.append("\tMETALLIC = clamp(acc_metal, 0.0, 1.0);")
	out.append("\tNORMAL_MAP = acc_n * 0.5 + 0.5;")
	out.append("}")
	return "\n".join(out) + "\n"


## Structure-only signature: equal for stacks that differ only in numeric/colour/texture VALUES.
static func structure_key(stack: Dictionary) -> String:
	var layers: Array = stack.get("layers", [])
	var parts: Array[String] = ["nb=" + _normal_mode(stack)]
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var blend: Dictionary = layer.get("blend", {})
		var seg := "%s|a=%s|n=%s|m=%s|c=%s|inv=%s|tri=%s" % [
			layer_prefix(stack, i),
			"tex" if _is_tex(layer.get("albedo")) else "col",
			"tex" if _is_tex(layer.get("normal")) else "proc",
			str(blend.get("mode", MODE_HEIGHT)) if i > 0 else "base",
			str(blend.get("channel", "r")),
			str(bool(blend.get("invert", false))),
			str(bool(layer.get("triplanar", false)))]
		parts.append(seg)
	var funcs: Array = stack.get("functions", [])
	for f in funcs:
		if f is Dictionary:
			var fd: Dictionary = f
			parts.append("fn:%s:%s" % [str(fd.get("name", "")), str(fd.get("code", "")).sha1_text()])
		else:
			parts.append("fn:" + str(f))
	return "\n".join(parts).sha1_text()


## Returns the cached Shader for this stack's structure, generating it on first use.
static func get_shader(stack: Dictionary) -> Shader:
	var key := structure_key(stack)
	if _cache.has(key):
		cache_hits += 1
		var cached: Shader = _cache[key]
		return cached
	var shader := Shader.new()
	shader.code = generate_shader_code(stack)
	_cache[key] = shader
	cache_builds += 1
	return shader


static func clear_cache() -> void:
	_cache.clear()
	cache_hits = 0
	cache_builds = 0


static func cache_size() -> int:
	return _cache.size()


## All uniform values of a stack: uniform name -> value (Color/float/Texture2D).
static func collect_params(stack: Dictionary) -> Dictionary:
	var params: Dictionary = {}
	var layers: Array = stack.get("layers", [])
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var p := layer_prefix(stack, i)
		var albedo: Variant = layer.get("albedo", Color(0.5, 0.5, 0.5))
		if _is_tex(albedo):
			params[p + "albedo_tex"] = _load_tex(str(albedo))
			params[p + "albedo"] = layer.get("tint", Color.WHITE)
		else:
			params[p + "albedo"] = albedo if albedo is Color else Color(0.5, 0.5, 0.5)
		if _is_tex(layer.get("normal")):
			params[p + "normal_tex"] = _load_tex(str(layer["normal"]))
		params[p + "roughness"] = float(layer.get("roughness", 0.8))
		params[p + "metallic"] = float(layer.get("metallic", 0.0))
		params[p + "normal_strength"] = float(layer.get("normal_strength", 1.0))
		params[p + "uv_scale"] = float(layer.get("uv_scale", 1.0))
		params[p + "height"] = float(layer.get("height", 0.5))
		params[p + "height_var"] = float(layer.get("height_var", 0.3))
		if bool(layer.get("triplanar", false)):
			params[p + "tri_sharp"] = float(layer.get("triplanar_sharpness", 4.0))
		if i == 0:
			continue
		var blend: Dictionary = layer.get("blend", {})
		var mode := str(blend.get("mode", MODE_HEIGHT))
		params[p + "blend_amount"] = float(blend.get("amount", 0.5 if mode == MODE_HEIGHT else 1.0))
		params[p + "blend_contrast"] = float(blend.get("contrast", 4.0))
		match mode:
			MODE_SLOPE:
				params[p + "slope_min"] = float(blend.get("min", 0.2))
				params[p + "slope_max"] = float(blend.get("max", 0.6))
			MODE_NOISE:
				params[p + "noise_scale"] = float(blend.get("scale", 1.0))
				params[p + "noise_threshold"] = float(blend.get("threshold", 0.5))
				params[p + "noise_softness"] = float(blend.get("softness", 0.1))
			MODE_MASK:
				if _is_tex(blend.get("texture")):
					params[p + "mask_tex"] = _load_tex(str(blend["texture"]))
	return params


static func build_material(stack: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = get_shader(stack)
	var params := collect_params(stack)
	for k in params.keys():
		var key: String = k
		if params[key] != null:
			mat.set_shader_parameter(key, params[key])
	var prefixes: Dictionary = {}
	var layers: Array = stack.get("layers", [])
	for i in layers.size():
		var layer: Dictionary = layers[i]
		prefixes[str(layer.get("name", "layer"))] = layer_prefix(stack, i)
	mat.set_meta("layer_prefixes", prefixes)
	return mat


## Material Instance: shares base's Shader, copies its parameters, applies overrides.
## Override keys are full uniform names or "layer_name/param" (e.g. "mud/roughness").
static func instance(base: ShaderMaterial, overrides: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = base.shader
	if base.shader != null:
		for u in base.shader.get_shader_uniform_list():
			var info: Dictionary = u
			var uname := str(info["name"])
			var v: Variant = base.get_shader_parameter(uname)
			if v != null:
				mat.set_shader_parameter(uname, v)
	var prefixes: Dictionary = {}
	if base.has_meta("layer_prefixes"):
		prefixes = base.get_meta("layer_prefixes")
		mat.set_meta("layer_prefixes", prefixes)
	for k in overrides.keys():
		var key := str(k)
		var value: Variant = overrides[k]
		if key.contains("/"):
			var bits := key.split("/", false, 1)
			if bits.size() == 2 and prefixes.has(bits[0]):
				key = str(prefixes[bits[0]]) + bits[1]
		if value is String and key.ends_with("_tex"):
			value = _load_tex(str(value))
		mat.set_shader_parameter(key, value)
	return mat


# --- generation helpers ----------------------------------------------------------------------

static func _normal_mode(stack: Dictionary) -> String:
	return "udn" if str(stack.get("normal_blend", "rnm")) == "udn" else "rnm"


static func _sanitize(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		var is_ok: bool = (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		out += ch if is_ok else "_"
	return out if out != "" else "layer"


static func _is_tex(v: Variant) -> bool:
	return (v is String or v is StringName) and str(v) != ""


static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	return null


static func _channel(blend: Dictionary) -> String:
	var ch := str(blend.get("channel", "r")).substr(0, 1)
	return ch if ch in ["r", "g", "b", "a"] else "r"


static func _collect_function_code(stack: Dictionary) -> Array[String]:
	var layers: Array = stack.get("layers", [])
	var wanted: Array[String] = ["fn_hash_noise"]
	var use_tri := false
	for i in layers.size():
		var layer: Dictionary = layers[i]
		if bool(layer.get("triplanar", false)) and (_is_tex(layer.get("albedo")) or _is_tex(layer.get("normal"))):
			use_tri = true
	if layers.size() > 1:
		wanted.append("fn_height_blend")
	if use_tri:
		wanted.append("fn_triplanar")
	if layers.size() > 0:
		wanted.append("fn_udn_blend" if _normal_mode(stack) == "udn" else "fn_rnm_blend")
	var custom: Array[Dictionary] = []
	var funcs: Array = stack.get("functions", [])
	for f in funcs:
		if f is Dictionary:
			custom.append(f)
		else:
			wanted.append(str(f))
	var seen: Dictionary = {}
	var out: Array[String] = []
	for fn_name in wanted:
		_add_function(fn_name, seen, out)
	for fd in custom:
		var cname := str(fd.get("name", ""))
		if cname == "" or seen.has(cname):
			continue
		seen[cname] = true
		out.append(str(fd.get("code", "")) + "\n")
	return out


static func _add_function(fn_name: String, seen: Dictionary, out: Array[String]) -> void:
	if seen.has(fn_name) or not FN_LIBRARY.has(fn_name):
		return
	seen[fn_name] = true
	var entry: Dictionary = FN_LIBRARY[fn_name]
	var deps: Array = entry["deps"]
	for d in deps:
		_add_function(str(d), seen, out)
	out.append(str(entry["code"]))


static func _layer_uniforms(stack: Dictionary, i: int) -> Array[String]:
	var layers: Array = stack.get("layers", [])
	var layer: Dictionary = layers[i]
	var p := layer_prefix(stack, i)
	var L: Array[String] = []
	L.append("// layer %d: %s" % [i, str(layer.get("name", "layer"))])
	L.append("uniform vec4 %salbedo : source_color = vec4(1.0);" % p)
	if _is_tex(layer.get("albedo")):
		L.append("uniform sampler2D %salbedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;" % p)
	if _is_tex(layer.get("normal")):
		L.append("uniform sampler2D %snormal_tex : hint_normal, filter_linear_mipmap, repeat_enable;" % p)
	L.append("uniform float %sroughness : hint_range(0.0, 1.0) = 0.8;" % p)
	L.append("uniform float %smetallic : hint_range(0.0, 1.0) = 0.0;" % p)
	L.append("uniform float %snormal_strength : hint_range(0.0, 4.0) = 1.0;" % p)
	L.append("uniform float %suv_scale = 1.0;" % p)
	L.append("uniform float %sheight : hint_range(0.0, 1.0) = 0.5;" % p)
	L.append("uniform float %sheight_var : hint_range(0.0, 1.0) = 0.3;" % p)
	if bool(layer.get("triplanar", false)):
		L.append("uniform float %stri_sharp : hint_range(1.0, 16.0) = 4.0;" % p)
	if i > 0:
		var blend: Dictionary = layer.get("blend", {})
		var mode := str(blend.get("mode", MODE_HEIGHT))
		L.append("uniform float %sblend_amount : hint_range(0.0, 1.0) = 1.0;" % p)
		L.append("uniform float %sblend_contrast : hint_range(0.5, 32.0) = 4.0;" % p)
		match mode:
			MODE_SLOPE:
				L.append("uniform float %sslope_min : hint_range(0.0, 1.0) = 0.2;" % p)
				L.append("uniform float %sslope_max : hint_range(0.0, 1.0) = 0.6;" % p)
			MODE_NOISE:
				L.append("uniform float %snoise_scale = 1.0;" % p)
				L.append("uniform float %snoise_threshold : hint_range(0.0, 1.0) = 0.5;" % p)
				L.append("uniform float %snoise_softness : hint_range(0.0, 1.0) = 0.1;" % p)
			MODE_MASK:
				L.append("uniform sampler2D %smask_tex : hint_default_white, filter_linear_mipmap, repeat_enable;" % p)
	return L


static func _layer_fragment(stack: Dictionary, i: int, nb_fn: String) -> Array[String]:
	var layers: Array = stack.get("layers", [])
	var layer: Dictionary = layers[i]
	var p := layer_prefix(stack, i)
	var tri := bool(layer.get("triplanar", false))
	var L: Array[String] = []
	L.append("\t// layer %d: %s" % [i, str(layer.get("name", "layer"))])
	L.append("\tvec2 %suv = UV * %suv_scale;" % [p, p])
	if _is_tex(layer.get("albedo")):
		var s := "fn_triplanar(%salbedo_tex, wp, wn, %suv_scale, %stri_sharp)" % [p, p, p] if tri \
				else "texture(%salbedo_tex, %suv)" % [p, p]
		L.append("\tvec4 %sc = %s * %salbedo;" % [p, s, p])
	else:
		L.append("\tvec4 %sc = %salbedo;" % [p, p])
	L.append("\tfloat %sh = clamp(%sheight + (fn_hash_noise(wp * %suv_scale * 2.0) - 0.5) * %sheight_var, 0.0, 1.0);" % [p, p, p, p])
	if _is_tex(layer.get("normal")):
		var ns := "fn_triplanar(%snormal_tex, wp, wn, %suv_scale, %stri_sharp).rgb" % [p, p, p] if tri \
				else "texture(%snormal_tex, %suv).rgb" % [p, p]
		L.append("\tvec3 %sn = normalize(%s * 2.0 - 1.0);" % [p, ns])
		L.append("\t%sn = normalize(vec3(%sn.xy * %snormal_strength, %sn.z));" % [p, p, p, p])
	else:
		L.append("\tvec3 %sq = wp * %suv_scale * 4.0;" % [p, p])
		L.append("\tfloat %sn0 = fn_hash_noise(%sq);" % [p, p])
		L.append("\tfloat %snx = fn_hash_noise(%sq + vec3(0.1, 0.0, 0.0));" % [p, p])
		L.append("\tfloat %snz = fn_hash_noise(%sq + vec3(0.0, 0.0, 0.1));" % [p, p])
		L.append("\tvec3 %sn = normalize(vec3((%sn0 - %snx) * %snormal_strength * 10.0, (%sn0 - %snz) * %snormal_strength * 10.0, 1.0));" % [p, p, p, p, p, p, p])
	if i == 0:
		L.append("\tacc_albedo = %sc.rgb;" % p)
		L.append("\tacc_rough = %sroughness;" % p)
		L.append("\tacc_metal = %smetallic;" % p)
		L.append("\tacc_h = %sh;" % p)
		L.append("\tacc_n = %sn;" % p)
		return L
	var blend: Dictionary = layer.get("blend", {})
	var mode := str(blend.get("mode", MODE_HEIGHT))
	var w := ""
	match mode:
		MODE_SLOPE:
			w = "smoothstep(%sslope_min, %sslope_max, 1.0 - wn.y)" % [p, p]
			if bool(blend.get("invert", false)):
				w = "1.0 - " + w
			w = "clamp(%s, 0.0, 1.0) * %sblend_amount" % [w, p]
		MODE_NOISE:
			var soft := "max(%snoise_softness, 0.001)" % p
			w = "smoothstep(%snoise_threshold - %s, %snoise_threshold + %s, fn_hash_noise(wp * %snoise_scale)) * %sblend_amount" % [p, soft, p, soft, p, p]
		MODE_MASK:
			w = "texture(%smask_tex, UV).%s * %sblend_amount" % [p, _channel(blend), p]
		MODE_VERTEX_COLOR:
			w = "COLOR.%s * %sblend_amount" % [_channel(blend), p]
		_:
			w = "%sblend_amount" % p
	L.append("\tfloat %sw = clamp(%s, 0.0, 1.0);" % [p, w])
	L.append("\tfloat %swb = fn_height_blend(acc_h, %sh, %sw, %sblend_contrast);" % [p, p, p, p])
	L.append("\tacc_albedo = mix(acc_albedo, %sc.rgb, %swb);" % [p, p])
	L.append("\tacc_rough = mix(acc_rough, %sroughness, %swb);" % [p, p])
	L.append("\tacc_metal = mix(acc_metal, %smetallic, %swb);" % [p, p])
	L.append("\tacc_h = mix(acc_h, %sh, %swb);" % [p, p])
	L.append("\tacc_n = %s(acc_n, normalize(mix(vec3(0.0, 0.0, 1.0), %sn, %swb)));" % [nb_fn, p, p])
	return L
