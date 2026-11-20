#[compute]

#version 450

#VERSION_DEFINES

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_normal;
layout(r8, set = 1, binding = 0) uniform restrict writeonly image2D dest_roughness;

layout(push_constant, std430) uniform Params {
	ivec2 screen_size;
	float curve;
	uint pad;
}
params;

#define HALF_PI 1.5707963267948966

void main() {
	// Pixel being shaded
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	// Dispatch is rounded up to workgroups. The comparison must include
	// the first pixel outside each dimension, not only pixels beyond it.
	if (any(greaterThanEqual(pos, params.screen_size))) {
		return;
	}

	// The 2x2 normal footprint touches the last row/column for edge pixels.
	// Clamp texel coordinates explicitly: texelFetch ignores sampler wrap and
	// edge reads outside the normal image are undefined on Metal/Vulkan.
	ivec2 last_pixel = params.screen_size - ivec2(1);
	vec3 normal_accum = vec3(0.0);
	float accum = 0.0;
	for (int i = 0; i <= 1; i++) {
		for (int j = 0; j <= 1; j++) {
			ivec2 sample_pos = min(pos + ivec2(i, j), last_pixel);
			normal_accum += normalize(texelFetch(source_normal, sample_pos, 0).xyz * 2.0 - 1.0);
			accum += 1.0;
		}
	}

	normal_accum /= accum;

	float r = length(normal_accum);

	float limit;

	if (r < 1.0) {
		float threshold = 0.4;

		/*
		//Formula from Filament, does not make sense to me.

		float r2 = r * r;
		float kappa = (3.0f * r - r * r2) / (1.0f - r2);
		float variance = 0.25f / kappa;
		limit = sqrt(min(2.0f * variance, threshold * threshold));
		*/
		/*
		//Formula based on probability distribution graph

		float width = acos(max(0.0,r)); // convert to angle (width)
		float roughness = pow(width,1.7)*0.854492; //approximate (crappy) formula to convert to roughness
		limit = min(sqrt(roughness), threshold); //convert to perceptual roughness and apply threshold
		*/

		limit = min(sqrt(pow(acos(max(0.0, r)) / HALF_PI, params.curve)), threshold); //convert to perceptual roughness and apply threshold

		//limit = 0.5;
	} else {
		limit = 0.0;
	}

	imageStore(dest_roughness, pos, vec4(limit));
}
