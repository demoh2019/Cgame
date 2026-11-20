extends RefCounted
## Full-screen colour-vision-deficiency filters (Unity post-processing colour-blind volume, Unreal
## "Color Blind Mode" accessibility setting). The matrices are Machado et al. 2009 at severity 1.0 for
## protanopia, deuteranopia and tritanopia, applied to linear-ish screen colour after the HUD is drawn.

const MATRICES := {
	1: [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)],
	2: [Vector3(0.367322, 0.860646, -0.227968), Vector3(0.280085, 0.672501, 0.047413), Vector3(-0.011820, 0.042940, 0.968881)],
	3: [Vector3(1.255528, -0.076749, -0.178779), Vector3(-0.078411, 0.930809, 0.147602), Vector3(0.004733, 0.691367, 0.303900)],
}

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 row2 = vec3(0.0, 0.0, 1.0);
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(clamp(vec3(dot(row0, c), dot(row1, c), dot(row2, c)), 0.0, 1.0), 1.0);
}
"""


## Matrix rows for a filter mode (0 = identity).
static func rows(mode: int) -> Array:
	if MATRICES.has(mode):
		return MATRICES[mode]
	return [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]


## Applies the 3x3 matrix to a colour (CPU reference used by the tests and by anything that tints UI).
static func transform(color: Color, mode: int) -> Color:
	var m := rows(mode)
	var v := Vector3(color.r, color.g, color.b)
	return Color(clampf(m[0].dot(v), 0.0, 1.0), clampf(m[1].dot(v), 0.0, 1.0), clampf(m[2].dot(v), 0.0, 1.0), color.a)


static func make_material(mode: int) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	configure(material, mode)
	return material


static func configure(material: ShaderMaterial, mode: int) -> void:
	var m := rows(mode)
	material.set_shader_parameter("row0", m[0])
	material.set_shader_parameter("row1", m[1])
	material.set_shader_parameter("row2", m[2])
