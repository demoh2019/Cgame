extends RefCounted
## GPU mipmapping and BC compression of terrain RVT pages (terrain_rvt.gd).
##
## Per page, entirely on the GPU:
##  1. the baked albedo (sRGB) and data (normal xz, roughness) viewports seed a 7-level RGBA16F pyramid,
##     colour linearised so mips average light, not gamma;
##  2. 2x2 box downsampling builds mips 1..6 (256 -> 4 texels);
##  3. one thread per 4x4 block encodes BC3 (sRGB albedo + roughness alpha) and BC5 (normal x, z) into
##     storage buffers, all mips in one dispatch;
##  4. RenderingDevice.texture_update_from_buffer (Cgame engine) copies the blocks into the compressed
##     arrays: Metal cannot view a BC texture as uncompressed, so the copy goes through a buffer.
## 256x256 RGBA8 x2 (512 KB) becomes ~170 KB per page with a full mip chain.

const TEXELS := 256
const MIPS := 7 # 256 .. 4: the smallest a 4x4 BC block allows.
const BLOCK_BYTES := 16

const _COMMON := """
#version 450
vec3 srgb_decode(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
vec3 srgb_encode(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}
"""

const _INIT := """
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D baked_albedo;
layout(set = 0, binding = 1) uniform sampler2D baked_data;
layout(set = 0, binding = 2, rgba16f) uniform restrict writeonly image2D out_a;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D out_b;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(p, imageSize(out_a)))) {
		return;
	}
	vec3 albedo = srgb_decode(texelFetch(baked_albedo, p, 0).rgb);
	vec4 data = texelFetch(baked_data, p, 0);
	imageStore(out_a, p, vec4(albedo, data.b));
	imageStore(out_b, p, vec4(data.r, data.g, 0.0, 1.0));
}
"""

const _DOWNSAMPLE := """
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D src_a;
layout(set = 0, binding = 1, rgba16f) uniform restrict readonly image2D src_b;
layout(set = 0, binding = 2, rgba16f) uniform restrict writeonly image2D dst_a;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D dst_b;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(p, imageSize(dst_a)))) {
		return;
	}
	ivec2 s = p * 2;
	vec4 a = imageLoad(src_a, s) + imageLoad(src_a, s + ivec2(1, 0)) + imageLoad(src_a, s + ivec2(0, 1)) + imageLoad(src_a, s + ivec2(1, 1));
	vec4 b = imageLoad(src_b, s) + imageLoad(src_b, s + ivec2(1, 0)) + imageLoad(src_b, s + ivec2(0, 1)) + imageLoad(src_b, s + ivec2(1, 1));
	imageStore(dst_a, p, a * 0.25);
	imageStore(dst_b, p, b * 0.25);
}
"""

# Block encoders: bounding-box endpoints (inset, axis-aligned to the colour covariance) and nearest
# palette entry per texel. Simple and fast; quality is ample for distance terrain.
const _ENCODE := """
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D pyramid_a;
layout(set = 0, binding = 1) uniform sampler2D pyramid_b;
layout(set = 0, binding = 2, std430) restrict writeonly buffer OutA {
	uvec4 blocks[];
} out_a;
layout(set = 0, binding = 3, std430) restrict writeonly buffer OutB {
	uvec4 blocks[];
} out_b;
layout(push_constant, std430) uniform Params {
	uint total_blocks;
	uint mips;
	uint top_blocks_per_row;
	uint pad;
} params;

void put_bits(inout uvec2 words, uint position, uint value) {
	if (position + 3u <= 32u) {
		words.x |= value << position;
	} else if (position >= 32u) {
		words.y |= value << (position - 32u);
	} else {
		words.x |= value << position;
		words.y |= value >> (32u - position);
	}
}

// BC4: 8-value mode (a0 > a1); palette 0 = a0, 1 = a1, 2..7 = (6a0 + a1) / 7 .. (a0 + 6a1) / 7.
uvec2 encode_bc4(float v[16]) {
	float lo = v[0];
	float hi = v[0];
	for (int i = 1; i < 16; i++) {
		lo = min(lo, v[i]);
		hi = max(hi, v[i]);
	}
	uint a0 = uint(round(clamp(hi, 0.0, 1.0) * 255.0));
	uint a1 = uint(round(clamp(lo, 0.0, 1.0) * 255.0));
	uvec2 words = uvec2(a0 | (a1 << 8u), 0u);
	if (a0 <= a1) {
		return words; // Flat block: every index 0 = a0.
	}
	float f0 = float(a0) / 255.0;
	float f1 = float(a1) / 255.0;
	for (int i = 0; i < 16; i++) {
		uint s = uint(clamp(round((v[i] - f1) / (f0 - f1) * 7.0), 0.0, 7.0));
		uint index = s == 7u ? 0u : (s == 0u ? 1u : 8u - s);
		put_bits(words, 16u + uint(i) * 3u, index);
	}
	return words;
}

uint pack_565(vec3 c) {
	uvec3 q = uvec3(round(clamp(c, 0.0, 1.0) * vec3(31.0, 63.0, 31.0)));
	return (q.r << 11u) | (q.g << 5u) | q.b;
}

vec3 unpack_565(uint c) {
	return vec3(float((c >> 11u) & 31u) / 31.0, float((c >> 5u) & 63u) / 63.0, float(c & 31u) / 31.0);
}

// BC1 colour block as used inside BC3 (always four colours): 0 = c0, 1 = c1, 2 = 2/3 c0 + 1/3 c1, 3 = 1/3 c0 + 2/3 c1.
uvec2 encode_bc1(vec3 c[16]) {
	vec3 lo = c[0];
	vec3 hi = c[0];
	vec3 mean = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		lo = min(lo, c[i]);
		hi = max(hi, c[i]);
		mean += c[i];
	}
	mean /= 16.0;
	vec3 inset = (hi - lo) / 16.0;
	lo += inset;
	hi -= inset;
	vec3 range = hi - lo;
	int ref = range.r >= range.g && range.r >= range.b ? 0 : (range.g >= range.b ? 1 : 2);
	vec3 cov = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		vec3 d = c[i] - mean;
		cov += d * d[ref];
	}
	vec3 e0 = hi;
	vec3 e1 = lo;
	for (int k = 0; k < 3; k++) {
		if (cov[k] < 0.0) {
			e0[k] = lo[k];
			e1[k] = hi[k];
		}
	}
	uint q0 = pack_565(e0);
	uint q1 = pack_565(e1);
	vec3 d0 = unpack_565(q0);
	vec3 d1 = unpack_565(q1);
	vec3 axis = d0 - d1;
	float len2 = dot(axis, axis);
	uint indices = 0u;
	for (int i = 0; i < 16; i++) {
		float t = len2 > 1e-8 ? clamp(dot(c[i] - d1, axis) / len2, 0.0, 1.0) : 1.0;
		uint s = uint(round(t * 3.0));
		uint index = s == 3u ? 0u : (s == 0u ? 1u : (s == 2u ? 2u : 3u));
		indices |= index << (uint(i) * 2u);
	}
	return uvec2(q0 | (q1 << 16u), indices);
}

void main() {
	uint g = gl_GlobalInvocationID.x;
	if (g >= params.total_blocks) {
		return;
	}
	uint mip = 0u;
	uint base = 0u;
	uint per_row = params.top_blocks_per_row;
	for (; mip + 1u < params.mips; mip++) {
		uint count = per_row * per_row;
		if (g < base + count) {
			break;
		}
		base += count;
		per_row = max(per_row >> 1u, 1u);
	}
	uint local = g - base;
	ivec2 origin = ivec2(int(local % per_row) * 4, int(local / per_row) * 4);
	vec3 colour[16];
	float roughness[16];
	float nx[16];
	float nz[16];
	for (int i = 0; i < 16; i++) {
		ivec2 t = origin + ivec2(i & 3, i >> 2);
		vec4 a = texelFetch(pyramid_a, t, int(mip));
		vec4 b = texelFetch(pyramid_b, t, int(mip));
		colour[i] = srgb_encode(clamp(a.rgb, vec3(0.0), vec3(1.0)));
		roughness[i] = a.a;
		nx[i] = b.r;
		nz[i] = b.g;
	}
	uvec2 alpha = encode_bc4(roughness);
	uvec2 rgb = encode_bc1(colour);
	out_a.blocks[g] = uvec4(alpha, rgb);
	out_b.blocks[g] = uvec4(encode_bc4(nx), encode_bc4(nz));
}
"""

var _rd: RenderingDevice
var _shaders: Array[RID] = [] # init, downsample, encode
var _pipelines: Array[RID] = []
var _sampler: RID
var _block_offsets: Array[int] = [] # first block of each mip
var _total_blocks := 0
var error := ""


## Whether this device can sample BC3/BC5 arrays filled by copies, and compile the shaders.
func setup(rd: RenderingDevice) -> bool:
	_rd = rd
	var usage: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	for format in [RenderingDevice.DATA_FORMAT_BC3_UNORM_BLOCK, RenderingDevice.DATA_FORMAT_BC5_UNORM_BLOCK]:
		if not _rd.texture_is_format_supported_for_usage(format, usage):
			error = "BC format %d not supported" % format
			return false
	if not _rd.has_method("texture_update_from_buffer"):
		error = "engine build lacks RenderingDevice.texture_update_from_buffer"
		return false
	for body in [_INIT, _DOWNSAMPLE, _ENCODE]:
		var source := RDShaderSource.new()
		source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		source.source_compute = _COMMON + body
		var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(source)
		if spirv == null or spirv.compile_error_compute != "":
			error = "RVT compressor shader: " + (spirv.compile_error_compute if spirv != null else "no SPIR-V")
			return false
		var shader: RID = _rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():
			error = "RVT compressor shader could not be created"
			return false
		_shaders.append(shader)
		_pipelines.append(_rd.compute_pipeline_create(shader))
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(sampler_state)
	var layout: Dictionary = block_layout()
	_block_offsets = layout["offsets"]
	_total_blocks = int(layout["total"])
	return true


## First 4x4 block of each mip in the encoder's output buffers, and the block count (one thread each).
static func block_layout() -> Dictionary:
	var offsets: Array[int] = []
	var total := 0
	var per_row: int = TEXELS / 4
	for mip in MIPS:
		offsets.append(total)
		total += per_row * per_row
		per_row = maxi(per_row / 2, 1)
	return {"offsets": offsets, "total": total}


## A compressed page array: BC3 (albedo + roughness) or BC5 (normal), every mip.
func create_array(bc5: bool, layers: int) -> RID:
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_BC5_UNORM_BLOCK if bc5 else RenderingDevice.DATA_FORMAT_BC3_UNORM_BLOCK
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.width = TEXELS
	format.height = TEXELS
	format.array_layers = layers
	format.mipmaps = MIPS
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return _rd.texture_create(format, RDTextureView.new())


## Per-bake-rig GPU scratch: two pyramids with per-mip storage views, two block buffers, uniform sets.
func create_scratch() -> Dictionary:
	var scratch := {"pyramids": [], "slices": [], "buffers": [], "sets": {}}
	for p in 2:
		var format := RDTextureFormat.new()
		format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		format.width = TEXELS
		format.height = TEXELS
		format.mipmaps = MIPS
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var tex: RID = _rd.texture_create(format, RDTextureView.new())
		scratch["pyramids"].append(tex)
		var slices: Array[RID] = []
		for mip in MIPS:
			slices.append(_rd.texture_create_shared_from_slice(RDTextureView.new(), tex, 0, mip, 1,
				RenderingDevice.TEXTURE_SLICE_2D))
		scratch["slices"].append(slices)
		scratch["buffers"].append(_rd.storage_buffer_create(_total_blocks * BLOCK_BYTES))
	return scratch


func _image(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


func _sampled(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sampler)
	u.add_id(rid)
	return u


func _storage(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u


func _uniform_set(scratch: Dictionary, key: String, uniforms: Array[RDUniform], shader_index: int) -> RID:
	var sets: Dictionary = scratch["sets"]
	var existing: RID = sets.get(key, RID())
	if existing.is_valid() and _rd.uniform_set_is_valid(existing):
		return existing
	var created: RID = _rd.uniform_set_create(uniforms, _shaders[shader_index], 0)
	sets[key] = created
	return created


## Encodes one baked page into `layer` of the two compressed arrays. Call outside any draw/compute list.
func encode(scratch: Dictionary, baked_albedo: RID, baked_data: RID, albedo_array: RID, data_array: RID,
		layer: int) -> bool:
	var slices: Array = scratch["slices"]
	var buffers: Array = scratch["buffers"]
	# The baked viewport textures can be recreated by the renderer; key their set by RID.
	var init_set: RID = _uniform_set(scratch, "init:%d:%d" % [baked_albedo.get_id(), baked_data.get_id()],
		[_sampled(0, baked_albedo), _sampled(1, baked_data), _image(2, slices[0][0]), _image(3, slices[1][0])], 0)
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[0])
	_rd.compute_list_bind_uniform_set(list, init_set, 0)
	_rd.compute_list_dispatch(list, TEXELS / 8, TEXELS / 8, 1)
	for mip in range(1, MIPS):
		_rd.compute_list_add_barrier(list)
		var down_set: RID = _uniform_set(scratch, "down:%d" % mip, [_image(0, slices[0][mip - 1]), _image(1, slices[1][mip - 1]),
			_image(2, slices[0][mip]), _image(3, slices[1][mip])], 1)
		var size: int = TEXELS >> mip
		_rd.compute_list_bind_compute_pipeline(list, _pipelines[1])
		_rd.compute_list_bind_uniform_set(list, down_set, 0)
		_rd.compute_list_dispatch(list, maxi((size + 7) / 8, 1), maxi((size + 7) / 8, 1), 1)
	_rd.compute_list_add_barrier(list)
	var encode_set: RID = _uniform_set(scratch, "encode", [_sampled(0, scratch["pyramids"][0]), _sampled(1, scratch["pyramids"][1]),
		_storage(2, buffers[0]), _storage(3, buffers[1])], 2)
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[2])
	_rd.compute_list_bind_uniform_set(list, encode_set, 0)
	var push := PackedByteArray()
	push.resize(16)
	push.encode_u32(0, _total_blocks)
	push.encode_u32(4, MIPS)
	push.encode_u32(8, TEXELS / 4)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, (_total_blocks + 63) / 64, 1, 1)
	_rd.compute_list_end()
	for mip in MIPS:
		var offset: int = _block_offsets[mip] * BLOCK_BYTES
		var per_row: int = maxi((TEXELS >> mip) / 4, 1)
		if _rd.call("texture_update_from_buffer", buffers[0], offset, per_row * BLOCK_BYTES, albedo_array, layer, mip) != OK:
			return false
		if _rd.call("texture_update_from_buffer", buffers[1], offset, per_row * BLOCK_BYTES, data_array, layer, mip) != OK:
			return false
	return true


func free_scratch(scratch: Dictionary) -> void:
	for slices in scratch.get("slices", []):
		for rid in slices:
			if rid.is_valid():
				_rd.free_rid(rid)
	for rid in scratch.get("pyramids", []) + scratch.get("buffers", []):
		if rid.is_valid():
			_rd.free_rid(rid)


func free_all() -> void:
	for rid in _pipelines + _shaders:
		if rid.is_valid():
			_rd.free_rid(rid)
	if _sampler.is_valid():
		_rd.free_rid(_sampler)
	_pipelines.clear()
	_shaders.clear()
