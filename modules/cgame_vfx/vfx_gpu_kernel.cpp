/**************************************************************************/
/*  vfx_gpu_kernel.cpp                                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "vfx_gpu_kernel.h"

#include "core/object/object.h"
#include "servers/rendering/rendering_device.h"
#include "servers/rendering/rendering_server.h"

using namespace VFXSim;

RenderingDevice *VFXGpuKernel::shared_device = nullptr;
int VFXGpuKernel::shared_users = 0;

static const char *GPU_TEMPLATE = R"GLSL(#[compute]
#version 450

// Generated-from-template GPU particle update kernel for the VFX graph GPU backend.
// Double-brace placeholders are substituted by VFXGpuKernel::generate_compute_source().

layout(local_size_x = {{LOCAL_SIZE}}, local_size_y = 1, local_size_z = 1) in;

struct Particle {
	vec4 pos_age; // xyz position, w age
	vec4 vel_life; // xyz velocity, w lifetime
	vec4 col;
	vec4 base_col;
	vec4 size_info; // x size, y base size
};

layout(set = 0, binding = 0, std430) restrict buffer Particles {
	Particle items[];
}
particles;

struct GpuEvent {
	vec4 pos_slot; // xyz position, w event slot (0 = death, n = collide module)
	vec4 vel;
};

layout(set = 0, binding = 1, std430) restrict buffer Events {
	uint count;
	uint capacity;
	uint pad0;
	uint pad1;
	GpuEvent items[];
}
events;

layout(push_constant, std430) uniform Params {
	float dt;
	float time;
	uint count;
	uint pad;
}
params;

const uint MAX_PARTICLES = {{MAX_PARTICLES}}u;
const bool ROUTE_DEATH = {{ROUTE_DEATH}};

void emit_event(uint slot, vec3 p, vec3 v) {
	uint idx = atomicAdd(events.count, 1u);
	if (idx < events.capacity) {
		events.items[idx].pos_slot = vec4(p, float(slot));
		events.items[idx].vel = vec4(v, 0.0);
	}
}

{{HELPERS}}

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= params.count) {
		return;
	}
	Particle pt = particles.items[i];
	vec3 p = pt.pos_age.xyz;
	float age = pt.pos_age.w;
	vec3 v = pt.vel_life.xyz;
	float life = pt.vel_life.w;
	vec4 col = pt.col;
	vec4 base_col = pt.base_col;
	float size = pt.size_info.x;
	float base_size = pt.size_info.y;
	float dt = params.dt;

	age += dt;
	// ---- update modules ----
{{UPDATE_CODE}}
	p += v * dt;
	// ---- post modules (collide / kill) ----
{{POST_CODE}}
	if (ROUTE_DEATH && age >= life) {
		emit_event(0u, p, v);
	}

	particles.items[i].pos_age = vec4(p, age);
	particles.items[i].vel_life = vec4(v, life);
	particles.items[i].col = col;
	particles.items[i].size_info = vec4(size, base_size, 0.0, 0.0);
}
)GLSL";

static const char *CURL_HELPER = R"GLSL(vec3 cn_potential(vec3 q, float f) {
	return vec3(sin(q.y * f + 1.3) * cos(q.z * f + 0.7),
			sin(q.z * f + 2.1) * cos(q.x * f + 4.2),
			sin(q.x * f + 3.3) * cos(q.y * f + 5.1));
}

vec3 cn_curl(vec3 q, float f) {
	const float e = 0.05;
	vec3 ex = vec3(e, 0.0, 0.0);
	vec3 ey = vec3(0.0, e, 0.0);
	vec3 ez = vec3(0.0, 0.0, e);
	vec3 dx = cn_potential(q + ex, f) - cn_potential(q - ex, f);
	vec3 dy = cn_potential(q + ey, f) - cn_potential(q - ey, f);
	vec3 dz = cn_potential(q + ez, f) - cn_potential(q - ez, f);
	return vec3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2.0 * e);
}
)GLSL";

const char *VFXGpuKernel::get_template_source() {
	return GPU_TEMPLATE;
}

static String _f(real_t p_x) {
	return vformat("%.8f", (double)p_x);
}

static String _v3(const Vector3 &p_v) {
	return vformat("vec3(%s, %s, %s)", _f(p_v.x), _f(p_v.y), _f(p_v.z));
}

static String _v4(const Color &p_c) {
	return vformat("vec4(%s, %s, %s, %s)", _f(p_c.r), _f(p_c.g), _f(p_c.b), _f(p_c.a));
}

static String _stop_fn(const String &p_name, const Module &p_module, bool p_color) {
	const int n = p_module.stop_t.size();
	const String rt = p_color ? "vec4" : "float";
	String s = vformat("%s %s(float u) {\n", rt, p_name);
	if (n == 0) {
		return s + vformat("\treturn %s;\n}\n", p_color ? String("vec4(1.0)") : String("1.0"));
	}
	for (int i = 0; i < n; i++) {
		const String off = _f(p_module.stop_t[i]);
		const String val = p_color ? _v4(p_module.stop_c[i]) : _f(p_module.stop_f[i]);
		if (i == 0) {
			s += vformat("\tif (u <= %s) { return %s; }\n", off, val);
		} else {
			const String pval = p_color ? _v4(p_module.stop_c[i - 1]) : _f(p_module.stop_f[i - 1]);
			const String poff = _f(p_module.stop_t[i - 1]);
			s += vformat("\tif (u <= %s) { return mix(%s, %s, (u - %s) / max(%s - %s, 0.00001)); }\n", off, pval, val, poff, off, poff);
		}
	}
	s += vformat("\treturn %s;\n}\n", p_color ? _v4(p_module.stop_c[n - 1]) : _f(p_module.stop_f[n - 1]));
	return s;
}

static String _module_glsl(const Module &m, int p_ordinal, Vector<String> &r_helpers) {
	switch (m.type) {
		case MODULE_GRAVITY:
			return vformat("\t{ v += %s * dt; }\n", _v3(m.v0));
		case MODULE_DRAG:
			return vformat("\t{ v *= exp(-%s * dt); }\n", _f(m.f[0]));
		case MODULE_CURL_NOISE:
			return vformat("\t{ v += cn_curl(p + %s * params.time, %s) * (%s * dt); }\n", _v3(m.v0), _f(m.f[1]), _f(m.f[0]));
		case MODULE_VORTEX: {
			String s = vformat("\t{\n\t\tvec3 r = p - %s;\n\t\tvec3 tg = cross(%s, r);\n\t\tfloat tl = length(tg);\n", _v3(m.v0), _v3(m.v1));
			s += vformat("\t\tif (tl > 0.0001) { v += tg / tl * (%s * dt); }\n", _f(m.f[0]));
			if (m.f[1] != 0.0) {
				s += vformat("\t\tvec3 rr = r - %s * dot(r, %s);\n\t\tfloat rl = length(rr);\n\t\tif (rl > 0.0) { v -= rr / rl * (%s * dt); }\n", _v3(m.v1), _v3(m.v1), _f(m.f[1]));
			}
			return s + "\t}\n";
		}
		case MODULE_ATTRACTOR: {
			String s = vformat("\t{\n\t\tvec3 to = %s - p;\n\t\tfloat dist = length(to);\n", _v3(m.v0));
			s += vformat("\t\tif (!(dist < 0.0001 || (%s > 0.0 && dist > %s))) {\n", _f(m.f[1]), _f(m.f[1]));
			s += vformat("\t\t\tfloat falloff = %s <= 0.0 ? 1.0 : 1.0 - dist / %s;\n", _f(m.f[1]), _f(MAX(m.f[1], (real_t)0.00001)));
			s += vformat("\t\t\tv += to / dist * (%s * falloff * dt);\n\t\t}\n\t}\n", _f(m.f[0]));
			return s;
		}
		case MODULE_COLOR_OVER_LIFE: {
			const String fn = vformat("color_curve_%d", p_ordinal);
			r_helpers.push_back(_stop_fn(fn, m, true));
			return vformat("\t{ float u = clamp(age / max(life, 0.0001), 0.0, 1.0); col = base_col * %s(u); }\n", fn);
		}
		case MODULE_SIZE_OVER_LIFE: {
			if (m.stop_t.is_empty()) {
				return String();
			}
			const String fn = vformat("size_curve_%d", p_ordinal);
			r_helpers.push_back(_stop_fn(fn, m, false));
			return vformat("\t{ float u = clamp(age / max(life, 0.0001), 0.0, 1.0); size = base_size * %s(u); }\n", fn);
		}
		case MODULE_COLLIDE_PLANE: {
			String s = vformat("\t{\n\t\tvec3 n = %s;\n\t\tfloat d = dot(n, p) - %s;\n\t\tfloat vn = dot(n, v);\n", _v3(m.v0), _f(m.f[0]));
			s += "\t\tif (d < 0.0 && vn < 0.0) {\n\t\t\tp -= n * d;\n\t\t\tvec3 nv = n * vn;\n";
			s += vformat("\t\t\tvec3 tv = (v - nv) * (1.0 - %s);\n\t\t\tv = tv - nv * %s;\n", _f(m.f[2]), _f(m.f[1]));
			if (m.gpu_slot >= 0) {
				s += vformat("\t\t\temit_event(%du, p, v);\n", m.gpu_slot);
			}
			return s + "\t\t}\n\t}\n";
		}
		case MODULE_KILL_BELOW_PLANE:
			return vformat("\t{ if (dot(%s, p) - %s < 0.0) { age = life + 1.0; } }\n", _v3(m.v0), _f(m.f[0]));
		default:
			break;
	}
	return String();
}

bool VFXGpuKernel::supports(const Emitter &p_emitter) {
	for (const Module &m : p_emitter.update_mods) {
		if (!is_update_stage_module(m.type)) {
			return false;
		}
	}
	return true;
}

void VFXGpuKernel::plan_slots(Emitter &r_emitter) {
	int slot = 1;
	for (Module &m : r_emitter.post_mods) {
		m.gpu_slot = -1;
		if (m.type == MODULE_COLLIDE_PLANE && !m.events.is_empty()) {
			m.gpu_slot = slot++;
		}
	}
}

String VFXGpuKernel::generate_compute_source(Emitter &r_emitter, bool p_route_death) {
	if (!supports(r_emitter)) {
		return String();
	}
	plan_slots(r_emitter);
	Vector<String> helpers;
	String update_code;
	String post_code;
	bool needs_curl = false;
	int ordinal = 0;
	for (const Module &m : r_emitter.update_mods) {
		if (m.type == MODULE_CURL_NOISE) {
			needs_curl = true;
		}
		update_code += _module_glsl(m, ordinal++, helpers);
	}
	for (const Module &m : r_emitter.post_mods) {
		post_code += _module_glsl(m, ordinal++, helpers);
	}
	String helper_text = needs_curl ? String(CURL_HELPER) : String();
	for (const String &h : helpers) {
		helper_text += "\n" + h;
	}
	String out = GPU_TEMPLATE;
	out = out.replace("{{LOCAL_SIZE}}", itos(LOCAL_SIZE));
	out = out.replace("{{MAX_PARTICLES}}", itos(r_emitter.cap));
	out = out.replace("{{ROUTE_DEATH}}", p_route_death ? "true" : "false");
	out = out.replace("{{HELPERS}}", helper_text);
	out = out.replace("{{UPDATE_CODE}}", update_code);
	out = out.replace("{{POST_CODE}}", post_code);
	return out;
}

bool VFXGpuKernel::open() {
	if (opened) {
		return rd != nullptr;
	}
	opened = true;
#ifdef RD_ENABLED
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr || rs->get_rendering_device() == nullptr) {
		last_error = "No RenderingDevice (headless, dummy or compatibility renderer).";
		return false;
	}
	if (shared_device == nullptr) {
		shared_device = rs->create_local_rendering_device();
	}
#else
	last_error = "Engine built without RD_ENABLED.";
	return false;
#endif
	if (shared_device == nullptr) {
		last_error = "Could not create a local RenderingDevice.";
		return false;
	}
	shared_users++;
	rd = shared_device;
	return true;
}

void VFXGpuKernel::close() {
	if (rd != nullptr) {
		shared_users--;
		rd = nullptr;
		if (shared_users <= 0) {
			memdelete(shared_device);
			shared_device = nullptr;
			shared_users = 0;
		}
	}
	opened = false;
}

void VFXGpuKernel::_free_emitter(Emitter &r_emitter) {
	if (rd != nullptr) {
		RID rids[] = { r_emitter.gpu_uniform_set, r_emitter.gpu_particle_buffer, r_emitter.gpu_event_buffer, r_emitter.gpu_pipeline, r_emitter.gpu_shader };
		for (const RID &rid : rids) {
			if (rid.is_valid()) {
				rd->free_rid(rid);
			}
		}
	}
	r_emitter.gpu_uniform_set = RID();
	r_emitter.gpu_particle_buffer = RID();
	r_emitter.gpu_event_buffer = RID();
	r_emitter.gpu_pipeline = RID();
	r_emitter.gpu_shader = RID();
}

void VFXGpuKernel::release(System &r_system) {
	for (Emitter *em : r_system.emitters) {
		_free_emitter(*em);
		em->gpu = nullptr;
	}
}

bool VFXGpuKernel::_build(Emitter &r_emitter) {
	String source = generate_compute_source(r_emitter);
	if (source.is_empty()) {
		return false;
	}
	source = source.trim_prefix("#[compute]\n");
	String error;
	Vector<uint8_t> spirv = rd->shader_compile_spirv_from_source(RenderingDevice::SHADER_STAGE_COMPUTE, source, RenderingDevice::SHADER_LANGUAGE_GLSL, &error);
	if (spirv.is_empty()) {
		last_error = error;
		return false;
	}
	Vector<RenderingDevice::ShaderStageSPIRVData> stages;
	RenderingDevice::ShaderStageSPIRVData stage;
	stage.shader_stage = RenderingDevice::SHADER_STAGE_COMPUTE;
	stage.spirv = spirv;
	stages.push_back(stage);
	r_emitter.gpu_shader = rd->shader_create_from_spirv(stages);
	if (!r_emitter.gpu_shader.is_valid()) {
		last_error = "shader_create_from_spirv failed";
		return false;
	}
	r_emitter.gpu_pipeline = rd->compute_pipeline_create(r_emitter.gpu_shader);
	r_emitter.gpu_particle_buffer = rd->storage_buffer_create(r_emitter.cap * BYTES_PER_PARTICLE);
	r_emitter.gpu_event_buffer = rd->storage_buffer_create(EVENT_HEADER_BYTES + r_emitter.cap * 2 * EVENT_BYTES);
	RenderingDevice::Uniform u0;
	u0.uniform_type = RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER;
	u0.binding = 0;
	u0.append_id(r_emitter.gpu_particle_buffer);
	RenderingDevice::Uniform u1;
	u1.uniform_type = RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER;
	u1.binding = 1;
	u1.append_id(r_emitter.gpu_event_buffer);
	Vector<RenderingDevice::Uniform> uniforms;
	uniforms.push_back(u0);
	uniforms.push_back(u1);
	r_emitter.gpu_uniform_set = rd->uniform_set_create(uniforms, r_emitter.gpu_shader, 0);
	return r_emitter.gpu_pipeline.is_valid() && r_emitter.gpu_uniform_set.is_valid();
}

bool VFXGpuKernel::step(Emitter &r_emitter, double p_dt) {
	if (rd == nullptr || r_emitter.gpu_failed) {
		return false;
	}
	if (!r_emitter.gpu_pipeline.is_valid()) {
		if (!_build(r_emitter)) {
			r_emitter.gpu_failed = true;
			_free_emitter(r_emitter);
			last_path = "cpu";
			return false;
		}
	}
	const int n = r_emitter.count;
	Vector<float> floats;
	floats.resize(n * FLOATS_PER_PARTICLE);
	float *w = floats.ptrw();
	for (int i = 0; i < n; i++) {
		float *o = w + i * FLOATS_PER_PARTICLE;
		o[0] = r_emitter.pos[i].x;
		o[1] = r_emitter.pos[i].y;
		o[2] = r_emitter.pos[i].z;
		o[3] = r_emitter.age[i];
		o[4] = r_emitter.vel[i].x;
		o[5] = r_emitter.vel[i].y;
		o[6] = r_emitter.vel[i].z;
		o[7] = r_emitter.life[i];
		o[8] = r_emitter.col[i].r;
		o[9] = r_emitter.col[i].g;
		o[10] = r_emitter.col[i].b;
		o[11] = r_emitter.col[i].a;
		o[12] = r_emitter.base_col[i].r;
		o[13] = r_emitter.base_col[i].g;
		o[14] = r_emitter.base_col[i].b;
		o[15] = r_emitter.base_col[i].a;
		o[16] = r_emitter.size[i];
		o[17] = r_emitter.base_size[i];
		o[18] = 0.0f;
		o[19] = 0.0f;
	}
	rd->buffer_update(r_emitter.gpu_particle_buffer, 0, n * BYTES_PER_PARTICLE, floats.ptr());
	uint32_t header[4] = { 0u, (uint32_t)(r_emitter.cap * 2), 0u, 0u };
	rd->buffer_update(r_emitter.gpu_event_buffer, 0, EVENT_HEADER_BYTES, header);

	struct PushConstant {
		float dt;
		float time;
		uint32_t count;
		uint32_t pad;
	} push = { (float)p_dt, (float)r_emitter.time, (uint32_t)n, 0u };

	const uint32_t groups = (uint32_t)((n + LOCAL_SIZE - 1) / LOCAL_SIZE);
	RenderingDevice::ComputeListID list = rd->compute_list_begin();
	rd->compute_list_bind_compute_pipeline(list, r_emitter.gpu_pipeline);
	rd->compute_list_bind_uniform_set(list, r_emitter.gpu_uniform_set, 0);
	rd->compute_list_set_push_constant(list, &push, sizeof(PushConstant));
	rd->compute_list_dispatch(list, groups, 1, 1);
	rd->compute_list_end();
	rd->submit();
	rd->sync();

	const Vector<uint8_t> out_bytes = rd->buffer_get_data(r_emitter.gpu_particle_buffer, 0, n * BYTES_PER_PARTICLE);
	if ((int)out_bytes.size() < n * BYTES_PER_PARTICLE) {
		r_emitter.gpu_failed = true;
		last_path = "cpu";
		return false;
	}
	const float *out = reinterpret_cast<const float *>(out_bytes.ptr());
	for (int i = 0; i < n; i++) {
		const float *o = out + i * FLOATS_PER_PARTICLE;
		r_emitter.pos[i] = Vector3(o[0], o[1], o[2]);
		r_emitter.age[i] = o[3];
		r_emitter.vel[i] = Vector3(o[4], o[5], o[6]);
		r_emitter.col[i] = Color(o[8], o[9], o[10], o[11]);
		r_emitter.size[i] = o[16];
	}

	const Vector<uint8_t> ev_bytes = rd->buffer_get_data(r_emitter.gpu_event_buffer, 0, EVENT_HEADER_BYTES + r_emitter.cap * 2 * EVENT_BYTES);
	if ((int)ev_bytes.size() >= EVENT_HEADER_BYTES) {
		const uint32_t *ev_header = reinterpret_cast<const uint32_t *>(ev_bytes.ptr());
		const int ev_count = MIN((int)ev_header[0], r_emitter.cap * 2);
		const float *ev = reinterpret_cast<const float *>(ev_bytes.ptr() + EVENT_HEADER_BYTES);
		for (int k = 0; k < ev_count; k++) {
			const float *e = ev + k * 8;
			const int slot = (int)e[3];
			if (slot <= 0) {
				continue; // Death events are routed on the CPU after culling.
			}
			for (const Module &m : r_emitter.post_mods) {
				if (m.gpu_slot == slot) {
					r_emitter.route_collision(m, Vector3(e[0], e[1], e[2]), Vector3(e[4], e[5], e[6]));
					break;
				}
			}
		}
	}
	last_path = "gpu";
	return true;
}
