/**************************************************************************/
/*  cgame_instance_culling.h                                              */
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

#include "core/math/plane.h"
#include "core/math/projection.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"
#include "servers/rendering/rendering_device.h"

// GPU per-instance frustum + Hi-Z-lite occlusion culling that compacts visible instance indices
// (MultiMesh-style batches). Falls back to an exact CPU implementation of the same kernel when no
// local RenderingDevice exists (headless/dummy renderer); the CPU path is what the tests verify.
// The GPU path is UNVERIFIED until run on real hardware.
//
// Conventions: frustum planes are outward-facing (Camera3D.get_frustum()); a box is outside when
// some plane has dot(n, c) - d - dot(|n|, half) > 0. Hi-Z is a single low-res level of per-texel
// MAX occluder depth: {"view_proj": Projection, "width": int, "height": int, "depth":
// PackedFloat32Array, "bias": float}; depth01 = ndc.z * 0.5 + 0.5, uv = ndc.xy * 0.5 + 0.5, texel
// row 0 at ndc.y = -1. An instance is occluded when its nearest corner depth exceeds the farthest
// depth in every texel its screen rect covers. Boxes crossing the near plane or fully off screen are
// never occlusion-culled. Output order is ascending instance index.
class CgameInstanceCulling : public RefCounted {
	GDCLASS(CgameInstanceCulling, RefCounted);

public:
	static constexpr int LOCAL_SIZE = 64;
	static constexpr int HEADER_BYTES = 16;

	// Plain Hi-Z description for the pure C++ path.
	struct HiZ {
		bool enabled = false;
		Projection view_proj;
		int width = 0;
		int height = 0;
		Vector<float> depth;
		float bias = 0.0f;
	};

private:
	bool force_cpu = false;
	String last_path = "none";

	RenderingDevice *rd = nullptr;
	bool tried_device = false;
	RID shader;
	RID pipeline;
	bool last_gpu_ok = false;

	bool _ensure_pipeline();
	Vector<int32_t> _cull_gpu(const Vector<Vector3> &p_centers, const Vector<Vector3> &p_halves, const Vector<Plane> &p_planes, const HiZ &p_hiz);
	void _try_device();

	static HiZ _parse_hiz(const Dictionary &p_hiz);
	static Vector<Plane> _parse_planes(const Array &p_planes);

protected:
	static void _bind_methods();

public:
	// Pure parts (no engine singletons): used by tests.
	static bool outside_frustum(const Vector3 &p_center, const Vector3 &p_half, const Vector<Plane> &p_planes);
	static bool occluded(const Vector3 &p_center, const Vector3 &p_half, const HiZ &p_hiz);
	static Vector<int32_t> cull_cpu_native(const Vector<Vector3> &p_centers, const Vector<Vector3> &p_halves, const Vector<Plane> &p_planes, const HiZ &p_hiz);
	// Reference brute force: the frustum test written independently of the kernel above.
	static Vector<int32_t> cull_brute_force(const Vector<Vector3> &p_centers, const Vector<Vector3> &p_halves, const Vector<Plane> &p_planes);

	static String get_compute_source();

	void set_force_cpu(bool p_force) { force_cpu = p_force; }
	bool get_force_cpu() const { return force_cpu; }
	String get_last_path() const { return last_path; }

	String generate_compute_source() const { return get_compute_source(); }
	bool device_available();

	// Culls AABBs (Array of AABB) against frustum planes (Array of Plane). Returns visible indices.
	PackedInt32Array cull(const Array &p_aabbs, const Array &p_frustum_planes, const Dictionary &p_hiz = Dictionary());
	// Culls bounding spheres (treated as cubes of half-extent r; conservative).
	PackedInt32Array cull_spheres(const PackedVector3Array &p_centers, const PackedFloat32Array &p_radii, const Array &p_frustum_planes, const Dictionary &p_hiz = Dictionary());
	// Core entry: parallel arrays of box centers and half-extents.
	PackedInt32Array cull_packed(const PackedVector3Array &p_centers, const PackedVector3Array &p_halves, const Array &p_frustum_planes, const Dictionary &p_hiz = Dictionary());
	// Exact reference implementation of the compute kernel.
	PackedInt32Array cull_cpu(const PackedVector3Array &p_centers, const PackedVector3Array &p_halves, const Array &p_frustum_planes, const Dictionary &p_hiz = Dictionary());

	void shutdown();

	CgameInstanceCulling();
	~CgameInstanceCulling();
};
