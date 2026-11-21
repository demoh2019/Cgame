// Eye shading: spherical-cornea refraction with parallax iris, limbal ring, sclera
// scattering-lite, wet specular and a caustic-ish iris highlight.
// Concepts: Jorge Jimenez et al., "Next-Generation Character Rendering" (GDC 2013 /
// SIGGRAPH 2013 talk, techniques only) and the refraction-through-cornea approach used by
// the UE5 Eye shading model (ray refract + plane intersection; no engine code reused).
// Original shader written for this project; no third-party code.
// Mesh contract: unit-ish sphere, eye looks along model -Z, up is +Y. Any scale works
// because positions are normalised in model space.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D iris_texture : source_color, filter_linear_mipmap, repeat_disable, hint_default_white;
uniform bool use_iris_texture = false;
uniform vec4 iris_color : source_color = vec4(0.22, 0.42, 0.28, 1.0);
uniform vec4 sclera_color : source_color = vec4(0.92, 0.89, 0.85, 1.0);
uniform float pupil_size : hint_range(0.0, 1.0) = 0.4;
uniform float iris_radius : hint_range(0.05, 0.6) = 0.3;
uniform float limbus_width : hint_range(0.0, 0.5) = 0.12;
uniform float cornea_ior : hint_range(1.0, 1.6) = 1.336;
uniform float iris_depth : hint_range(0.0, 0.3) = 0.08;
uniform float wetness : hint_range(0.0, 1.0) = 0.8;
uniform float sclera_scatter : hint_range(0.0, 1.0) = 0.35;
uniform float fibre_seed = 0.0;
uniform float fibre_density : hint_range(8.0, 96.0) = 40.0;
uniform float caustic_strength : hint_range(0.0, 2.0) = 0.5;
uniform vec2 caustic_dir = vec2(0.5, 0.6);
uniform float blink_occlusion : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_obj_pos;
varying vec3 v_obj_cam;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec3 p = normalize(v_obj_pos);
	vec3 incident = normalize(v_obj_pos - v_obj_cam);
	float rho = length(p.xy);
	// Cornea region: front hemisphere inside the limbus (with a soft edge).
	float front = smoothstep(0.0, 0.15, -p.z);
	float cornea_mask = front * (1.0 - smoothstep(iris_radius, iris_radius + 0.03, rho));

	// Refract the view ray through the spherical cornea, intersect the iris plane.
	vec3 refr = refract(incident, p, 1.0 / cornea_ior);
	float plane_z = -sqrt(max(1.0 - iris_radius * iris_radius, 0.0)) + iris_depth;
	float t = (plane_z - p.z) / max(refr.z, 0.05);
	vec2 hit = p.xy + refr.xy * t;
	vec2 ic = hit / iris_radius; // iris disc coordinates, |ic| = 1 at the limbus
	float d = length(ic);
	float ang = atan(ic.y, ic.x);

	// Pupil dilation: radius as a fraction of the iris disc.
	float pupil_r = mix(0.12, 0.62, pupil_size);
	float pupil = 1.0 - smoothstep(pupil_r - 0.03, pupil_r + 0.03, d);

	// Iris colour: texture or procedural radial fibres.
	vec3 iris;
	if (use_iris_texture) {
		// Pupil dilation pulls the texture radially so the pattern stays attached to the iris.
		float k = (d - pupil_r) / max(1.0 - pupil_r, 0.01);
		vec2 dir = ic / max(d, 0.001);
		vec2 tuv = dir * mix(0.08, 1.0, clamp(k, 0.0, 1.0)) * 0.5 + 0.5;
		iris = texture(iris_texture, tuv).rgb * iris_color.rgb;
	} else {
		float fib = value_noise(vec2(ang * fibre_density * 0.159155 + fibre_seed * 17.0, d * 3.0 + fibre_seed));
		float fib2 = value_noise(vec2(ang * fibre_density * 0.318 + fibre_seed * 5.0, d * 7.0));
		float fibres = mix(0.55, 1.35, fib * 0.65 + fib2 * 0.35);
		float collarette = exp(-pow((d - (pupil_r + 0.22)) / 0.08, 2.0));
		vec3 warm = mix(iris_color.rgb, vec3(0.55, 0.38, 0.18), 0.55);
		iris = mix(iris_color.rgb, warm, collarette) * fibres;
		iris = mix(iris * 0.7, iris, smoothstep(pupil_r, 0.7, d)); // darker toward the pupil
	}
	// Limbal ring: dark band at the iris edge.
	float limbal = smoothstep(1.0 - limbus_width, 1.0, d);
	iris *= 1.0 - 0.85 * limbal;
	iris = mix(iris, vec3(0.01), pupil);

	// Caustic-ish highlight: bright crescent on the side opposite the key light.
	vec2 cdir = normalize(caustic_dir + vec2(0.0001));
	float crescent = smoothstep(0.2, 1.0, dot(-ic / max(d, 0.001), cdir)) * smoothstep(pupil_r, pupil_r + 0.4, d) * (1.0 - pupil);
	vec3 caustic = iris_color.rgb * crescent * caustic_strength;

	// Sclera: scattering-lite warm bleed toward grazing angles and the lid line.
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - ndv, 2.0);
	vec3 sclera = sclera_color.rgb;
	sclera = mix(sclera, sclera * vec3(1.0, 0.55, 0.5), sclera_scatter * edge);
	sclera *= 1.0 - 0.25 * smoothstep(iris_radius, iris_radius + 0.25, rho) * front;

	vec3 col = mix(sclera, iris, cornea_mask);

	// Eyelid shadow driven by blink_occlusion (0 open, 1 closed).
	float lid_line = mix(1.2, -1.2, blink_occlusion);
	float lid = smoothstep(lid_line - 0.5, lid_line, p.y);
	col *= 1.0 - 0.9 * lid;

	ALBEDO = col;
	EMISSION = caustic * cornea_mask * (1.0 - lid);
	SPECULAR = 0.5;
	ROUGHNESS = mix(mix(0.6, 0.18, wetness), mix(0.2, 0.02, wetness), cornea_mask);
	CLEARCOAT = wetness * cornea_mask;
	CLEARCOAT_ROUGHNESS = 0.03;
	BACKLIGHT = sclera_color.rgb * sclera_scatter * (1.0 - cornea_mask) * 0.5;
}
