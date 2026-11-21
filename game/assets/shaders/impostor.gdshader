shader_type spatial;
// Octant-style impostor (UE5 Impostor Baker / SpeedTree billboard LOD):
// a camera-facing cylindrical quad that picks the baked yaw frame matching
// the view direction in the instance's own space. One draw per field.
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform vec2 quad_size = vec2(1.0); // Square bake extent (x) and vertical center (y).
uniform float alpha_cut = 0.45;

varying flat float frame_index;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	mat3 basis = mat3(MODEL_MATRIX);
	float sx = length(basis[0]);
	float sy = length(basis[1]);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	vec3 fwd = length(to_cam) > 0.0001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec2 local = vec2(UV.x - 0.5, 0.5 - UV.y) * quad_size.x;
	VERTEX = origin + right * local.x * sx + vec3(0.0, 1.0, 0.0) * (local.y + quad_size.y) * sy;
	NORMAL = fwd;
	// View direction expressed in the instance's unscaled local frame.
	vec3 ld = vec3(dot(fwd, basis[0] / sx), 0.0, dot(fwd, basis[2] / max(length(basis[2]), 0.0001)));
	float a = atan(ld.x, ld.z);
	frame_index = mod(round(-a / (TAU / frames)), frames);
}

void fragment() {
	vec2 uv = vec2((frame_index + UV.x) / frames, UV.y);
	vec4 c = texture(atlas, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
