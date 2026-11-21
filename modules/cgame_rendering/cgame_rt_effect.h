/**************************************************************************/
/*  cgame_rt_effect.h                                                     */
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

#pragma once

#include "core/math/projection.h"
#include "core/os/mutex.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "scene/resources/compositor.h"
#include "servers/rendering/rendering_device.h"

class Mesh;
class RenderData;
class RenderSceneData;
class RenderSceneBuffersRD;

// Render-thread half of the hardware ray-traced shadows / ambient occlusion (native
// CompositorEffect). Owns all GPU state: per-mesh-surface BLAS (budgeted builds, LRU eviction), one
// TLAS rebuilt whenever a new instance snapshot arrives, and the compute passes rt_shadows, rt_ao
// (GL_EXT_ray_query against the TLAS, using the scene depth buffer and normals reconstructed from
// it) and rt_denoise (spatial + temporal filter, composite onto the opaque colour buffer). Runs at
// POST_OPAQUE, so transparent surfaces are drawn after the effect.
//
// Silent fallback: if the device has no SUPPORTS_RAY_QUERY, a shader fails to compile, or any
// resource creation fails, the effect disables itself and the raster path is untouched.
//
// A scene driver (mesh scan, nearest-N selection, geometry extraction budget) feeds it through
// submit(); the static helpers below implement the driver-side pure logic.
class CgameRTEffect : public CompositorEffect {
	GDCLASS(CgameRTEffect, CompositorEffect);

public:
	static constexpr int PARAMS_SIZE = 256;
	static constexpr int MAX_BLAS = 512;
	// Frames without use before a BLAS may be evicted when over MAX_BLAS.
	static constexpr int EVICT_AGE = 120;
	// Surfaces above this triangle count are skipped (too costly to extract/build).
	static constexpr int MAX_TRIANGLES_PER_SURFACE = 120000;

	struct Config {
		bool shadows = true;
		bool ao = true;
		int ao_rays = 1;
		int max_instances = 256;
		int blas_builds_per_frame = 2;
		float shadow_tmax = 80.0f;
		float ao_tmax = 1.75f;
		float shadow_strength = 1.0f;
		float ao_strength = 0.85f;
		float temporal_blend = 0.9f;
	};

	struct Instance {
		int64_t key = 0;
		Transform3D transform;
	};

	struct Geometry {
		Vector<uint8_t> vertices;
		Vector<uint8_t> indices;
		int vertex_count = 0;
		int index_count = 0;
	};

private:
	struct BlasEntry {
		RID blas;
		RID vbuf;
		RID ibuf;
		bool built = false;
		int64_t last_used = 0;
	};

	// Shared between the main and the render thread.
	Mutex mutex;
	Config config;
	LocalVector<Instance> pending_instances;
	HashMap<int64_t, Geometry> pending_geometry;
	bool have_snapshot = false;
	Vector3 sun_dir = Vector3(0, 1, 0);
	float sun_radius = 0.0047f;
	Vector<int64_t> evicted;

	// Render-thread state.
	RenderingDevice *rd = nullptr;
	bool failed = false;
	bool active = false;
	HashMap<String, RID> shaders;
	HashMap<String, RID> pipelines;
	RID nearest_sampler;
	RID linear_sampler;
	RID params_buffer;
	RID tlas;
	int tlas_capacity = 0;
	int tlas_instance_count = 0;
	HashMap<int64_t, BlasEntry> blas_entries;
	List<int64_t> build_queue;
	LocalVector<Instance> instances;
	bool instances_dirty = false;
	int64_t frame = 0;
	bool hist_flip = false;
	Projection prev_view_proj;
	bool have_prev = false;
	Vector<RID> texture_signature;

	void _native_render_callback(int p_callback_type, const RenderData *p_render_data);
	void _setup();
	void _fail(const String &p_reason);
	void _ingest();
	void _create_blas(int64_t p_key, const Geometry &p_geometry);
	void _build_budgeted(const Config &p_config);
	void _free_blas(int64_t p_key);
	void _rebuild_tlas(const Config &p_config);
	RID _make_texture(RenderSceneBuffersRD *p_buffers, const StringName &p_name, int p_format, const Size2i &p_size);
	void _dispatch(const String &p_pass, const LocalVector<RenderingDevice::Uniform> &p_uniforms, int p_groups_x, int p_groups_y);
	void _trace_and_composite(RenderSceneBuffersRD *p_buffers, RenderSceneData *p_scene_data);

	static void _free_on_render_thread(const Array &p_rids);

protected:
	static void _bind_methods();

public:
	// ---- Pure helpers (no GPU): used by tests and by the scene driver. ----
	static bool is_supported(RenderingDevice *p_rd);
	// Quality tiers 0 (off) .. 3. Rays are 1 per pixel for shadows, `ao_rays` for AO.
	static Dictionary settings(int p_level, const String &p_rendering_method = "forward_plus");
	static int group_count(int p_pixels, int p_group_size = 8);
	// Number of BLAS builds to start this frame (`queued` waiting, `budget` allowed).
	static int builds_this_frame(int p_queued, int p_budget);
	static int budget_take(int p_pending, int p_per_frame);
	// Keys to evict: unused for EVICT_AGE frames, oldest first, only while `count` exceeds `limit`.
	static Vector<int64_t> eviction_candidates_native(const HashMap<int64_t, int64_t> &p_last_used, int64_t p_frame, int p_count, int p_limit);
	static Array eviction_candidates(const Dictionary &p_last_used, int p_frame, int p_count, int p_limit);
	// std140 layout of RtParams (256 bytes).
	static Vector<uint8_t> pack_params_native(const Projection &p_inv_proj, const Transform3D &p_cam_to_world, const Projection &p_prev_view_proj, const Vector3 &p_sun_dir, float p_sun_radius, const Size2i &p_size, int p_frame, int p_ao_rays, const Config &p_config);
	static PackedByteArray pack_params(const Projection &p_inv_proj, const Transform3D &p_cam_to_world, const Projection &p_prev_view_proj, const Vector3 &p_sun_dir, float p_sun_radius, const Size2i &p_size, int p_frame, int p_ao_rays, const Dictionary &p_config);
	static Config config_from_dictionary(const Dictionary &p_config);
	static String shader_path(const String &p_pass_name);
	// Source of a pass with the #[compute] header removed and the common include inlined.
	static String prepare_source(const String &p_pass_source, const String &p_common_source);
	static String get_pass_source(const String &p_pass_name);
	static String get_common_source();

	// ---- Driver-side helpers. ----
	static Dictionary extract_triangles(const Ref<Mesh> &p_mesh, int p_surface);
	static PackedByteArray pack_positions(const PackedVector3Array &p_vertices);
	static PackedByteArray pack_indices(const PackedInt32Array &p_indices);
	static int64_t blas_key(const Ref<Mesh> &p_mesh, int p_surface);
	// The nearest `max_count` candidates ({position, radius, ...}) within `max_distance` of `origin`.
	static TypedArray<Dictionary> select_nearest(const TypedArray<Dictionary> &p_candidates, const Vector3 &p_origin, float p_max_distance, int p_max_count);

	// ---- Main-thread API. ----
	void configure(const Dictionary &p_config);
	// instances: [{key: int, transform: Transform3D}]; geometry: {key: {vertices: PackedByteArray,
	// indices: PackedByteArray, vertex_count: int, index_count: int}} for meshes the render thread
	// has not seen.
	void submit(const Array &p_instances, const Dictionary &p_geometry, const Vector3 &p_sun_dir, float p_sun_radius);
	// BLAS keys the render thread dropped; the caller must re-submit their geometry.
	Array take_evicted_keys();
	bool is_active() const { return active; }
	bool has_failed() const { return failed; }

	CgameRTEffect();
	~CgameRTEffect();
};
