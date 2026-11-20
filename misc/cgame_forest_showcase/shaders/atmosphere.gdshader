shader_type sky;
render_mode use_debanding;

uniform vec3 zenith_color : source_color = vec3(0.034, 0.075, 0.19);
uniform vec3 mid_color : source_color = vec3(0.17, 0.24, 0.35);
uniform vec3 horizon_color : source_color = vec3(0.79, 0.45, 0.29);
uniform vec3 ground_color : source_color = vec3(0.16, 0.16, 0.17);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float sun_halo : hint_range(0.0, 3.0) = 1.35;
uniform float aurora_intensity : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 47.17);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(cell);
    float b = hash21(cell + vec2(1.0, 0.0));
    float c = hash21(cell + vec2(0.0, 1.0));
    float d = hash21(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cloud_noise(vec2 uv) {
    float a = value_noise(uv);
    float b = value_noise(uv * 2.09 + 13.1);
    float c = value_noise(uv * 4.2 + 31.3);
    return a * 0.59 + b * 0.29 + c * 0.12;
}

void sky() {
    vec3 view_dir = normalize(EYEDIR);
    float up = max(view_dir.y, 0.0);
    float zenith = smoothstep(0.05, 0.98, up);
    vec3 sky_color = mix(horizon_color, mid_color, smoothstep(0.0, 0.43, up));
    sky_color = mix(sky_color, zenith_color, pow(zenith, 0.78));

    // Use the first actual directional light, avoiding an artificial static sun.
    if (LIGHT0_ENABLED) {
        vec3 sun_dir = normalize(-LIGHT0_DIRECTION);
        float alignment = max(dot(view_dir, sun_dir), 0.0);
        float disc = smoothstep(0.99989, 0.99996, alignment);
        float aura = pow(alignment, 125.0) * 0.43 + pow(alignment, 24.0) * 0.13;
        sky_color += LIGHT0_COLOR * LIGHT0_ENERGY * (disc * 4.5 + aura * sun_halo);
    }

    // Fixed cloud field: no TIME dependency that would force sky radiance updates every frame.
    if (view_dir.y > 0.0) {
        vec2 cloud_uv = view_dir.xz / max(view_dir.y + 0.16, 0.24) * 1.15;
        float density = cloud_noise(cloud_uv + vec2(12.1, -7.3));
        float coverage = smoothstep(0.60 - cloud_coverage * 0.25, 0.78 - cloud_coverage * 0.2, density);
        float fade = smoothstep(0.01, 0.16, view_dir.y);
        sky_color = mix(sky_color, sky_color * 0.67 + vec3(0.67, 0.58, 0.55) * 0.35, coverage * fade * 0.65);
    } else {
        sky_color = mix(horizon_color * 0.65, ground_color, smoothstep(0.0, 0.65, -view_dir.y));
    }

    // Low-cost, time-independent auroral curtains on the north-facing sky.
    // CPU-side weather controller adjusts only the intensity twice per second;
    // removing TIME avoids per-render-frame radiance invalidations.
    if (aurora_intensity > 0.001 && view_dir.y > 0.0) {
        float north = smoothstep(-0.12, 0.64, -view_dir.z);
        float altitude = smoothstep(0.07, 0.23, view_dir.y)
            * (1.0 - smoothstep(0.74, 0.95, view_dir.y));
        float ribbon_motion = sin(view_dir.y * 10.0 + view_dir.x * 8.0) * 0.08
            + sin(view_dir.y * 5.0 - view_dir.x * 7.0) * 0.045;
        float curtain_a = exp(-pow((view_dir.x + 0.30 + ribbon_motion) * 10.0, 2.0));
        float curtain_b = exp(-pow((view_dir.x - 0.19 - ribbon_motion) * 13.0, 2.0));
        float vertical_striation = 0.65 + 0.35 * hash21(
            floor(vec2(view_dir.x * 115.0, view_dir.y * 16.0)));
        vec3 aurora = vec3(0.09, 0.67, 0.46) * curtain_a
            + vec3(0.12, 0.37, 0.83) * curtain_b;
        sky_color += aurora * altitude * north * vertical_striation * aurora_intensity;
    }

    // Godot sky shaders cannot return from sky(): all branches converge here.
    COLOR = max(sky_color, vec3(0.0));
}
