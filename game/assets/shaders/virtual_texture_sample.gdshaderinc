// Sparse virtual texture sampling helpers (original code; concepts from Sean Barrett's
// "Sparse Virtual Textures" talk and the UE Runtime Virtual Texture indirection design).
//
// Indirection texture (from virtual_texture.gd indirection_image()): one texel per mip0
// virtual page, RGBA8, filter nearest, no mipmaps. r,g = physical slot xy, b = resident mip.
// Atlas: physical_atlas(), slots of (page_size + 2 * border) pixels, filter linear.

// Pixel size of the whole virtual texture mapped to uv 0..1.
// Mip level the GPU would pick for this uv (use for feedback requests).
float vt_mip_level(vec2 uv, vec2 virtual_size_pixels, float top_mip) {
	vec2 dx = dFdx(uv * virtual_size_pixels);
	vec2 dy = dFdy(uv * virtual_size_pixels);
	float d = max(dot(dx, dx), dot(dy, dy));
	return clamp(0.5 * log2(max(d, 1e-8)), 0.0, top_mip);
}

vec4 vt_sample(sampler2D indirection, sampler2D atlas, vec2 uv, vec2 virtual_size_pages, vec2 atlas_pages, float page_size, float border) {
	vec2 st = clamp(uv, vec2(0.0), vec2(0.999999));
	ivec2 page = ivec2(floor(st * virtual_size_pages));
	vec4 ind = texelFetch(indirection, page, 0) * 255.0;
	vec2 slot = floor(ind.rg + 0.5);
	float mip = floor(ind.b + 0.5);
	// Position inside the resident page, in 0..1 (pages at that mip are larger on screen).
	vec2 in_page = fract(st * virtual_size_pages / exp2(mip));
	float slot_px = page_size + 2.0 * border;
	vec2 atlas_px = slot * slot_px + vec2(border) + in_page * page_size;
	return texture(atlas, atlas_px / (atlas_pages * slot_px));
}

// Feedback output: write to a low-res feedback target; read back and decode into
// pack_page() keys. rgb = page x, page y, mip (each 0..255 as 8-bit), a = 1.
vec4 vt_feedback(vec2 uv, vec2 virtual_size_pages, vec2 virtual_size_pixels, float top_mip) {
	float mip = floor(vt_mip_level(uv, virtual_size_pixels, top_mip));
	vec2 pages = max(floor(virtual_size_pages / exp2(mip)), vec2(1.0));
	vec2 p = floor(clamp(uv, vec2(0.0), vec2(0.999999)) * pages);
	return vec4(p.x / 255.0, p.y / 255.0, mip / 255.0, 1.0);
}
