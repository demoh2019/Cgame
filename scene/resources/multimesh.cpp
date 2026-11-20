/**************************************************************************/
/*  multimesh.cpp                                                         */
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

#include "multimesh.h"

#include "core/math/math_funcs.h"

#include "core/math/random_pcg.h"
#include "core/object/class_db.h"
#include "core/variant/array.h"
#include "servers/rendering/rendering_server.h"

#ifndef DISABLE_DEPRECATED
// Kept for compatibility from 3.x to 4.0.

void MultiMesh::_set_transform_array(const Vector<Vector3> &p_array) {
	if (transform_format != TRANSFORM_3D) {
		return;
	}

	const Vector<Vector3> &xforms = p_array;
	int len = xforms.size();
	ERR_FAIL_COND((len / 4) != instance_count);
	if (len == 0) {
		return;
	}

	const Vector3 *r = xforms.ptr();

	for (int i = 0; i < len / 4; i++) {
		Transform3D t;
		t.basis[0] = r[i * 4 + 0];
		t.basis[1] = r[i * 4 + 1];
		t.basis[2] = r[i * 4 + 2];
		t.origin = r[i * 4 + 3];

		set_instance_transform(i, t);
	}
}

Vector<Vector3> MultiMesh::_get_transform_array() const {
	if (transform_format != TRANSFORM_3D) {
		return Vector<Vector3>();
	}

	if (instance_count == 0) {
		return Vector<Vector3>();
	}

	Vector<Vector3> xforms;
	xforms.resize(instance_count * 4);

	Vector3 *w = xforms.ptrw();

	for (int i = 0; i < instance_count; i++) {
		Transform3D t = get_instance_transform(i);
		w[i * 4 + 0] = t.basis[0];
		w[i * 4 + 1] = t.basis[1];
		w[i * 4 + 2] = t.basis[2];
		w[i * 4 + 3] = t.origin;
	}

	return xforms;
}

void MultiMesh::_set_transform_2d_array(const Vector<Vector2> &p_array) {
	if (transform_format != TRANSFORM_2D) {
		return;
	}

	const Vector<Vector2> &xforms = p_array;
	int len = xforms.size();
	ERR_FAIL_COND((len / 3) != instance_count);
	if (len == 0) {
		return;
	}

	const Vector2 *r = xforms.ptr();

	for (int i = 0; i < len / 3; i++) {
		Transform2D t;
		t.columns[0] = r[i * 3 + 0];
		t.columns[1] = r[i * 3 + 1];
		t.columns[2] = r[i * 3 + 2];

		set_instance_transform_2d(i, t);
	}
}

Vector<Vector2> MultiMesh::_get_transform_2d_array() const {
	if (transform_format != TRANSFORM_2D) {
		return Vector<Vector2>();
	}

	if (instance_count == 0) {
		return Vector<Vector2>();
	}

	Vector<Vector2> xforms;
	xforms.resize(instance_count * 3);

	Vector2 *w = xforms.ptrw();

	for (int i = 0; i < instance_count; i++) {
		Transform2D t = get_instance_transform_2d(i);
		w[i * 3 + 0] = t.columns[0];
		w[i * 3 + 1] = t.columns[1];
		w[i * 3 + 2] = t.columns[2];
	}

	return xforms;
}

void MultiMesh::_set_color_array(const Vector<Color> &p_array) {
	const Vector<Color> &colors = p_array;
	int len = colors.size();
	if (len == 0) {
		return;
	}
	ERR_FAIL_COND(len != instance_count);

	const Color *r = colors.ptr();

	for (int i = 0; i < len; i++) {
		set_instance_color(i, r[i]);
	}
}

Vector<Color> MultiMesh::_get_color_array() const {
	if (instance_count == 0 || !use_colors) {
		return Vector<Color>();
	}

	Vector<Color> colors;
	colors.resize(instance_count);

	for (int i = 0; i < instance_count; i++) {
		colors.set(i, get_instance_color(i));
	}

	return colors;
}

void MultiMesh::_set_custom_data_array(const Vector<Color> &p_array) {
	const Vector<Color> &custom_datas = p_array;
	int len = custom_datas.size();
	if (len == 0) {
		return;
	}
	ERR_FAIL_COND(len != instance_count);

	const Color *r = custom_datas.ptr();

	for (int i = 0; i < len; i++) {
		set_instance_custom_data(i, r[i]);
	}
}

Vector<Color> MultiMesh::_get_custom_data_array() const {
	if (instance_count == 0 || !use_custom_data) {
		return Vector<Color>();
	}

	Vector<Color> custom_datas;
	custom_datas.resize(instance_count);

	for (int i = 0; i < instance_count; i++) {
		custom_datas.set(i, get_instance_custom_data(i));
	}

	return custom_datas;
}
#endif // DISABLE_DEPRECATED

void MultiMesh::set_buffer(const Vector<float> &p_buffer) {
	if (instance_count == 0) {
		return;
	}

	uint32_t stride = transform_format == TRANSFORM_2D ? 8 : 12;
	stride += use_colors ? 4 : 0;
	stride += use_custom_data ? 4 : 0;
	ERR_FAIL_COND_MSG(stride * instance_count != p_buffer.size(), "Cannot set a buffer on a Multimesh that is a different size from the Multimesh's existing buffer.");

	RS::get_singleton()->multimesh_set_buffer(multimesh, p_buffer);
}


bool MultiMesh::set_instance_transform_color_buffer(const Array &p_transforms, const Vector<Color> &p_colors) {
	ERR_FAIL_COND_V_MSG(transform_format != TRANSFORM_3D, false, "Full transform/color uploads require a 3D MultiMesh.");
	ERR_FAIL_COND_V_MSG(!use_colors, false, "Enable use_colors for a full transform/color upload.");
	ERR_FAIL_COND_V_MSG(use_custom_data, false, "Transform/color uploads cannot overwrite MultiMeshes with custom instance data.");
	ERR_FAIL_COND_V_MSG(p_transforms.size() != instance_count || p_colors.size() != instance_count, false, "Full transform/color arrays must match instance_count.");

	// Validate the *entire* payload before packing or touching the renderer.
	// This preserves the previous buffer on malformed data, unlike repeated
	// per-instance writes where a later bad slot can leave partial updates.
	for (int i = 0; i < instance_count; i++) {
		ERR_FAIL_COND_V_MSG(p_transforms[i].get_type() != Variant::TRANSFORM3D, false, "Each instance must provide Transform3D.");
		const Transform3D transform = p_transforms[i];
		ERR_FAIL_COND_V_MSG(!transform.is_finite(), false, "Instance transforms must be finite.");
		const Color &color = p_colors[i];
		ERR_FAIL_COND_V_MSG(!Math::is_finite(color.r) || !Math::is_finite(color.g) || !Math::is_finite(color.b) || !Math::is_finite(color.a), false, "Instance colors must be finite.");
	}
	if (instance_count == 0) {
		return true;
	}

	// Reuse the fork's native 3D record packer (12 matrix + 4 RGBA floats)
	// and submit the whole contiguous buffer to RenderingServer just once.
	const Vector<float> packed = pack_transform_buffer(p_transforms, p_colors);
	ERR_FAIL_COND_V_MSG(packed.size() != instance_count * 16, false, "Native packing did not produce a valid MultiMesh buffer.");
	set_buffer(packed);
	return true;
}

Vector<float> MultiMesh::pack_transform_buffer(const Array &p_transforms, const Vector<Color> &p_colors) const {
	// This is a pure CPU operation: set_buffer() performs the single upload.
	ERR_FAIL_COND_V_MSG(transform_format != TRANSFORM_3D, Vector<float>(), "Native transform packing requires a 3D MultiMesh.");
	ERR_FAIL_COND_V_MSG(use_custom_data, Vector<float>(), "Native transform packing does not support custom instance data.");
	ERR_FAIL_COND_V_MSG(p_transforms.size() != instance_count, Vector<float>(), "Transform count must match MultiMesh instance_count.");
	ERR_FAIL_COND_V_MSG(p_colors.size() != (use_colors ? instance_count : 0), Vector<float>(),
			"Color count must match colored instance_count, or be empty for untinted instances.");
	for (int i = 0; i < instance_count; i++) {
		ERR_FAIL_COND_V_MSG(p_transforms[i].get_type() != Variant::TRANSFORM3D, Vector<float>(),
				"Every instance must supply a Transform3D.");
	}

	const int stride = use_colors ? 16 : 12;
	Vector<float> packed;
	packed.resize(instance_count * stride);
	float *w = packed.ptrw();
	for (int i = 0; i < instance_count; i++) {
		const Transform3D t = p_transforms[i];
		const Vector3 x = t.basis.get_column(0);
		const Vector3 y = t.basis.get_column(1);
		const Vector3 z = t.basis.get_column(2);
		const int o = i * stride;
		w[o + 0] = x.x;
		w[o + 1] = y.x;
		w[o + 2] = z.x;
		w[o + 3] = t.origin.x;
		w[o + 4] = x.y;
		w[o + 5] = y.y;
		w[o + 6] = z.y;
		w[o + 7] = t.origin.y;
		w[o + 8] = x.z;
		w[o + 9] = y.z;
		w[o + 10] = z.z;
		w[o + 11] = t.origin.z;
		if (use_colors) {
			const Color &c = p_colors[i];
			w[o + 12] = c.r;
			w[o + 13] = c.g;
			w[o + 14] = c.b;
			w[o + 15] = c.a;
		}
	}
	return packed;
}

AABB MultiMesh::transformed_mesh_bounds(const Array &p_transforms, real_t p_margin) const {
	ERR_FAIL_COND_V_MSG(mesh.is_null() || p_transforms.is_empty(), AABB(),
			"Mesh and at least one transform are required to calculate scenery bounds.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_margin) || p_margin < 0.0, AABB(), "Bounds margin must be finite and nonnegative.");
	for (int i = 0; i < p_transforms.size(); i++) {
		ERR_FAIL_COND_V_MSG(p_transforms[i].get_type() != Variant::TRANSFORM3D, AABB(), "Every instance must supply a Transform3D.");
	}
	const AABB mesh_bounds = mesh->get_aabb();
	const Transform3D first = p_transforms[0];
	AABB result = first.xform(mesh_bounds);
	for (int i = 1; i < p_transforms.size(); i++) {
		const Transform3D t = p_transforms[i];
		result.merge_with(t.xform(mesh_bounds));
	}
	return result.grow(p_margin);
}

Vector<float> MultiMesh::shuffled_instance_buffer(const Vector<float> &p_buffer, uint64_t p_seed) const {
	// MultiMesh buffers contain interleaved transform, color, and custom data.
	// Shuffle records, not floats, so distance-based visible_instance_count
	// produces scattered coverage without corrupting matrix rows or tints.
	const int stride = (transform_format == TRANSFORM_2D ? 8 : 12) +
			(use_colors ? 4 : 0) + (use_custom_data ? 4 : 0);
	if (instance_count <= 1 || p_buffer.size() != instance_count * stride) {
		return p_buffer;
	}
	Vector<float> shuffled = p_buffer;
	float *records = shuffled.ptrw(); // Copy-on-write; do not mutate caller data.
	RandomPCG rng;
	rng.seed(p_seed);
	for (int i = instance_count - 1; i > 0; --i) {
		const int other = rng.random(0, i);
		if (i == other) {
			continue;
		}
		const int a = i * stride;
		const int b = other * stride;
		for (int channel = 0; channel < stride; ++channel) {
			const float saved = records[a + channel];
			records[a + channel] = records[b + channel];
			records[b + channel] = saved;
		}
	}
	return shuffled;
}

Vector<float> MultiMesh::get_buffer() const {
	return RS::get_singleton()->multimesh_get_buffer(multimesh);
}

void MultiMesh::set_buffer_interpolated(const Vector<float> &p_buffer_curr, const Vector<float> &p_buffer_prev) {
	RS::get_singleton()->multimesh_set_buffer_interpolated(multimesh, p_buffer_curr, p_buffer_prev);
}

void MultiMesh::set_mesh(const Ref<Mesh> &p_mesh) {
	if (mesh == p_mesh) {
		return; // Avoid redundant RenderingServer rebinds for unchanged mesh resources.
	}
	mesh = p_mesh;
	if (mesh.is_valid()) {
		RenderingServer::get_singleton()->multimesh_set_mesh(multimesh, mesh->get_rid());
	} else {
		RenderingServer::get_singleton()->multimesh_set_mesh(multimesh, RID());
	}
}

Ref<Mesh> MultiMesh::get_mesh() const {
	return mesh;
}

void MultiMesh::set_instance_count(int p_count) {
	ERR_FAIL_COND(p_count < 0);
	RenderingServer::get_singleton()->multimesh_allocate_data(multimesh, p_count, RSE::MultimeshTransformFormat(transform_format), use_colors, use_custom_data);
	instance_count = p_count;
}

int MultiMesh::get_instance_count() const {
	return instance_count;
}

void MultiMesh::set_visible_instance_count(int p_count) {
	ERR_FAIL_COND(p_count < -1);
	ERR_FAIL_COND(p_count > instance_count);
	// Streaming LOD often resubmits the same visible prefix on consecutive
	// frames. Avoid a no-op RenderingServer dispatch (and backend dirty
	// checks) without suppressing any real draw-range changes.
	if (visible_instance_count == p_count) {
		return;
	}
	RenderingServer::get_singleton()->multimesh_set_visible_instances(multimesh, p_count);
	visible_instance_count = p_count;
}

int MultiMesh::get_visible_instance_count() const {
	return visible_instance_count;
}

void MultiMesh::set_physics_interpolation_quality(PhysicsInterpolationQuality p_quality) {
	ERR_FAIL_COND_MSG(p_quality != INTERP_QUALITY_FAST && p_quality != INTERP_QUALITY_HIGH, "Unsupported MultiMesh physics interpolation quality.");
	if (_physics_interpolation_quality == p_quality) {
		return; // No need to resend unchanged interpolation quality to the renderer.
	}
	_physics_interpolation_quality = p_quality;
	RenderingServer::get_singleton()->multimesh_set_physics_interpolation_quality(multimesh, (RSE::MultimeshPhysicsInterpolationQuality)p_quality);
}

bool MultiMesh::set_instance_transforms_batch(const PackedInt32Array &p_indices, const TypedArray<Transform3D> &p_transforms) {
	ERR_FAIL_COND_V_MSG(transform_format != TRANSFORM_3D, false, "Sparse transform batches require 3D MultiMesh format.");
	ERR_FAIL_COND_V_MSG(p_indices.size() != p_transforms.size(), false, "Indices and transforms must have equal lengths.");
	if (p_indices.is_empty()) {
		return true;
	}

	// Validate the complete request before touching any RenderingServer state.
	PackedInt32Array sorted = p_indices;
	sorted.sort();
	for (int i = 0; i < sorted.size(); i++) {
		ERR_FAIL_INDEX_V_MSG(sorted[i], instance_count, false, "Sparse transform index is out of bounds.");
		if (i > 0) {
			ERR_FAIL_COND_V_MSG(sorted[i] == sorted[i - 1], false, "Sparse transform indices must be unique.");
		}
	}
	for (int i = 0; i < p_transforms.size(); i++) {
		const Transform3D transform = p_transforms[i];
		ERR_FAIL_COND_V_MSG(!transform.is_finite(), false, "Sparse instance transforms must be finite.");
	}

	// One script-to-engine entry point; still K RenderingServer updates.
	for (int i = 0; i < p_indices.size(); i++) {
		const Transform3D transform = p_transforms[i];
		RenderingServer::get_singleton()->multimesh_instance_set_transform(multimesh, p_indices[i], transform);
	}
	return true;
}

void MultiMesh::set_instance_transform(int p_instance, const Transform3D &p_transform) {
	ERR_FAIL_INDEX_MSG(p_instance, instance_count, "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_MSG(transform_format == TRANSFORM_2D, "Can't set Transform3D on a Multimesh configured to use Transform2D. Ensure that you have set the `transform_format` to `TRANSFORM_3D`.");
	RenderingServer::get_singleton()->multimesh_instance_set_transform(multimesh, p_instance, p_transform);
}

void MultiMesh::set_instance_transform_2d(int p_instance, const Transform2D &p_transform) {
	ERR_FAIL_INDEX_MSG(p_instance, instance_count, "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_MSG(transform_format == TRANSFORM_3D, "Can't set Transform2D on a Multimesh configured to use Transform3D. Ensure that you have set the `transform_format` to `TRANSFORM_2D`.");
	RenderingServer::get_singleton()->multimesh_instance_set_transform_2d(multimesh, p_instance, p_transform);
	emit_changed();
}

Transform3D MultiMesh::get_instance_transform(int p_instance) const {
	ERR_FAIL_INDEX_V_MSG(p_instance, instance_count, Transform3D(), "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_V_MSG(transform_format == TRANSFORM_2D, Transform3D(), "Can't get Transform3D on a Multimesh configured to use Transform2D. Ensure that you have set the `transform_format` to `TRANSFORM_3D`.");
	return RenderingServer::get_singleton()->multimesh_instance_get_transform(multimesh, p_instance);
}

Transform2D MultiMesh::get_instance_transform_2d(int p_instance) const {
	ERR_FAIL_INDEX_V_MSG(p_instance, instance_count, Transform2D(), "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_V_MSG(transform_format == TRANSFORM_3D, Transform2D(), "Can't get Transform2D on a Multimesh configured to use Transform3D. Ensure that you have set the `transform_format` to `TRANSFORM_2D`.");
	return RenderingServer::get_singleton()->multimesh_instance_get_transform_2d(multimesh, p_instance);
}

bool MultiMesh::set_instance_colors_batch(const PackedInt32Array &p_indices, const PackedColorArray &p_colors) {
	ERR_FAIL_COND_V_MSG(!use_colors, false, "Enable use_colors before batch-updating instance colors.");
	ERR_FAIL_COND_V_MSG(p_indices.size() != p_colors.size(), false, "Instance color indices and values must have matching lengths.");
	if (p_indices.is_empty()) {
		return true;
	}

	// Validate everything before the first renderer update. Unsorted indices
	// are allowed but duplicates and out-of-range slots would be ambiguous.
	PackedInt32Array sorted = p_indices;
	sorted.sort();
	for (int i = 0; i < sorted.size(); i++) {
		ERR_FAIL_INDEX_V_MSG(sorted[i], instance_count, false, "Instance color batch index is out of bounds.");
		if (i > 0) {
			ERR_FAIL_COND_V_MSG(sorted[i] == sorted[i - 1], false, "Instance color batch indices must be unique.");
		}
	}
	for (int i = 0; i < p_colors.size(); i++) {
		const Color &color = p_colors[i];
		ERR_FAIL_COND_V_MSG(!Math::is_finite(color.r) || !Math::is_finite(color.g) || !Math::is_finite(color.b) || !Math::is_finite(color.a), false, "Instance color components must be finite.");
	}

	// Reduce script calls while retaining per-instance RenderingServer writes.
	// The whole buffer need not be reuploaded for sparse color changes.
	for (int i = 0; i < p_indices.size(); i++) {
		RenderingServer::get_singleton()->multimesh_instance_set_color(multimesh, p_indices[i], p_colors[i]);
	}
	return true;
}

void MultiMesh::set_instance_color(int p_instance, const Color &p_color) {
	ERR_FAIL_INDEX_MSG(p_instance, instance_count, "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_MSG(!use_colors, "Can't set instance color on a Multimesh that isn't using colors. Ensure that you have `use_colors` property of this Multimesh set to `true`.");
	RenderingServer::get_singleton()->multimesh_instance_set_color(multimesh, p_instance, p_color);
}

Color MultiMesh::get_instance_color(int p_instance) const {
	ERR_FAIL_INDEX_V_MSG(p_instance, instance_count, Color(), "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_V_MSG(!use_colors, Color(), "Can't get instance color on a Multimesh that isn't using colors. Ensure that you have `use_colors` property of this Multimesh set to `true`.");
	return RenderingServer::get_singleton()->multimesh_instance_get_color(multimesh, p_instance);
}

void MultiMesh::set_instance_custom_data(int p_instance, const Color &p_custom_data) {
	ERR_FAIL_INDEX_MSG(p_instance, instance_count, "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_MSG(!use_custom_data, "Can't get instance custom data on a Multimesh that isn't using custom data. Ensure that you have `use_custom_data` property of this Multimesh set to `true`.");
	RenderingServer::get_singleton()->multimesh_instance_set_custom_data(multimesh, p_instance, p_custom_data);
}

Color MultiMesh::get_instance_custom_data(int p_instance) const {
	ERR_FAIL_INDEX_V_MSG(p_instance, instance_count, Color(), "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	ERR_FAIL_COND_V_MSG(!use_custom_data, Color(), "Can't get instance custom data on a Multimesh that isn't using custom data. Ensure that you have `use_custom_data` property of this Multimesh set to `true`.");
	return RenderingServer::get_singleton()->multimesh_instance_get_custom_data(multimesh, p_instance);
}

bool MultiMesh::swap_instance_data(int p_first, int p_second) {
	ERR_FAIL_INDEX_V_MSG(p_first, instance_count, false, "First instance index is out of bounds.");
	ERR_FAIL_INDEX_V_MSG(p_second, instance_count, false, "Second instance index is out of bounds.");
	if (p_first == p_second) {
		return true;
	}

	if (transform_format == TRANSFORM_3D) {
		const Transform3D first = get_instance_transform(p_first);
		const Transform3D second = get_instance_transform(p_second);
		set_instance_transform(p_first, second);
		set_instance_transform(p_second, first);
	} else {
		const Transform2D first = get_instance_transform_2d(p_first);
		const Transform2D second = get_instance_transform_2d(p_second);
		set_instance_transform_2d(p_first, second);
		set_instance_transform_2d(p_second, first);
	}

	if (use_colors) {
		const Color first_color = get_instance_color(p_first);
		const Color second_color = get_instance_color(p_second);
		set_instance_color(p_first, second_color);
		set_instance_color(p_second, first_color);
	}

	if (use_custom_data) {
		const Color first_data = get_instance_custom_data(p_first);
		const Color second_data = get_instance_custom_data(p_second);
		set_instance_custom_data(p_first, second_data);
		set_instance_custom_data(p_second, first_data);
	}

	// Swap-removal is a teleport for both slots, not a movement to interpolate.
	reset_instance_physics_interpolation(p_first);
	reset_instance_physics_interpolation(p_second);
	return true;
}

bool MultiMesh::remove_visible_instance(int p_instance) {
	const int active_count = visible_instance_count == -1 ? instance_count : visible_instance_count;
	ERR_FAIL_INDEX_V_MSG(p_instance, active_count, false, "Only a visible instance index can be removed.");

	const int last_visible_index = active_count - 1;
	if (p_instance != last_visible_index && !swap_instance_data(p_instance, last_visible_index)) {
		return false;
	}
	// Keeps the allocated instance_count unchanged and hides the last active slot.
	set_visible_instance_count(last_visible_index);
	return true;
}

int MultiMesh::remove_visible_instances(const PackedInt32Array &p_instances) {
	const int active_count = visible_instance_count == -1 ? instance_count : visible_instance_count;
	ERR_FAIL_COND_V_MSG(p_instances.size() > active_count, -1, "Cannot remove more instances than are visible.");
	if (p_instances.is_empty()) {
		return 0;
	}

	// Validate the complete input BEFORE changing rendering state.
	// Process in descending index order so every index still refers to its
	// original visible slot at the moment it is removed.
	PackedInt32Array sorted = p_instances;
	sorted.sort();
	for (int i = 0; i < sorted.size(); i++) {
		ERR_FAIL_INDEX_V_MSG(sorted[i], active_count, -1, "Only visible instance indices may be removed.");
		if (i > 0) {
			ERR_FAIL_COND_V_MSG(sorted[i] == sorted[i - 1], -1, "Duplicate instance indices are not allowed.");
		}
	}
	for (int i = sorted.size() - 1; i >= 0; i--) {
		if (!remove_visible_instance(sorted[i])) {
			return -1;
		}
	}
	return sorted.size();
}

bool MultiMesh::activate_hidden_instance(int p_hidden_instance) {
	const int active_count = visible_instance_count == -1 ? instance_count : visible_instance_count;
	ERR_FAIL_INDEX_V_MSG(p_hidden_instance, instance_count, false, "Instance index is out of bounds.");
	ERR_FAIL_COND_V_MSG(p_hidden_instance < active_count, false, "Only hidden instances can be activated.");

	if (p_hidden_instance != active_count) {
		if (!swap_instance_data(p_hidden_instance, active_count)) {
			return false;
		}
	} else {
		// Newly visible instances should not interpolate from a stale transform.
		reset_instance_physics_interpolation(active_count);
	}
	// The allocated buffer remains unchanged. A fully visible buffer has no
	// hidden instance to activate; this is caught by the visible-prefix guard.
	set_visible_instance_count(active_count + 1);
	return true;
}

void MultiMesh::reset_instance_physics_interpolation(int p_instance) {
	ERR_FAIL_INDEX_MSG(p_instance, instance_count, "Instance index out of bounds. Instance index must be less than `instance_count` and greater than or equal to zero.");
	RenderingServer::get_singleton()->multimesh_instance_reset_physics_interpolation(multimesh, p_instance);
}

void MultiMesh::reset_instances_physics_interpolation() {
	RenderingServer::get_singleton()->multimesh_instances_reset_physics_interpolation(multimesh);
}

void MultiMesh::set_physics_interpolated(bool p_interpolated) {
	RenderingServer::get_singleton()->multimesh_set_physics_interpolated(multimesh, p_interpolated);
}

void MultiMesh::set_custom_aabb(const AABB &p_custom) {
	custom_aabb = p_custom;
	RS::get_singleton()->multimesh_set_custom_aabb(multimesh, custom_aabb);
	emit_changed();
}

AABB MultiMesh::get_custom_aabb() const {
	return custom_aabb;
}

AABB MultiMesh::get_aabb() const {
	return RenderingServer::get_singleton()->multimesh_get_aabb(multimesh);
}

RID MultiMesh::get_rid() const {
	return multimesh;
}

void MultiMesh::set_use_colors(bool p_enable) {
	ERR_FAIL_COND_MSG(instance_count > 0, "Instance count must be 0 to toggle whether colors are used.");
	use_colors = p_enable;
}

bool MultiMesh::is_using_colors() const {
	return use_colors;
}

void MultiMesh::set_use_custom_data(bool p_enable) {
	ERR_FAIL_COND_MSG(instance_count > 0, "Instance count must be 0 to toggle whether custom data is used.");
	use_custom_data = p_enable;
}

bool MultiMesh::is_using_custom_data() const {
	return use_custom_data;
}

void MultiMesh::set_transform_format(TransformFormat p_transform_format) {
	ERR_FAIL_COND_MSG(instance_count > 0, "Instance count must be 0 to change the transform format.");
	ERR_FAIL_COND_MSG(p_transform_format != TRANSFORM_2D && p_transform_format != TRANSFORM_3D, "Unsupported MultiMesh transform format.");
	transform_format = p_transform_format;
}

MultiMesh::TransformFormat MultiMesh::get_transform_format() const {
	return transform_format;
}

void MultiMesh::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_mesh", "mesh"), &MultiMesh::set_mesh);
	ClassDB::bind_method(D_METHOD("get_mesh"), &MultiMesh::get_mesh);
	ClassDB::bind_method(D_METHOD("set_use_colors", "enable"), &MultiMesh::set_use_colors);
	ClassDB::bind_method(D_METHOD("is_using_colors"), &MultiMesh::is_using_colors);
	ClassDB::bind_method(D_METHOD("set_use_custom_data", "enable"), &MultiMesh::set_use_custom_data);
	ClassDB::bind_method(D_METHOD("is_using_custom_data"), &MultiMesh::is_using_custom_data);
	ClassDB::bind_method(D_METHOD("set_transform_format", "format"), &MultiMesh::set_transform_format);
	ClassDB::bind_method(D_METHOD("get_transform_format"), &MultiMesh::get_transform_format);

	ClassDB::bind_method(D_METHOD("set_instance_count", "count"), &MultiMesh::set_instance_count);
	ClassDB::bind_method(D_METHOD("get_instance_count"), &MultiMesh::get_instance_count);
	ClassDB::bind_method(D_METHOD("set_visible_instance_count", "count"), &MultiMesh::set_visible_instance_count);
	ClassDB::bind_method(D_METHOD("get_visible_instance_count"), &MultiMesh::get_visible_instance_count);
	ClassDB::bind_method(D_METHOD("set_physics_interpolation_quality", "quality"), &MultiMesh::set_physics_interpolation_quality);
	ClassDB::bind_method(D_METHOD("get_physics_interpolation_quality"), &MultiMesh::get_physics_interpolation_quality);
	ClassDB::bind_method(D_METHOD("set_instance_transform", "instance", "transform"), &MultiMesh::set_instance_transform);
	ClassDB::bind_method(D_METHOD("set_instance_transforms_batch", "indices", "transforms"), &MultiMesh::set_instance_transforms_batch);
	ClassDB::bind_method(D_METHOD("set_instance_transform_2d", "instance", "transform"), &MultiMesh::set_instance_transform_2d);
	ClassDB::bind_method(D_METHOD("get_instance_transform", "instance"), &MultiMesh::get_instance_transform);
	ClassDB::bind_method(D_METHOD("get_instance_transform_2d", "instance"), &MultiMesh::get_instance_transform_2d);
	ClassDB::bind_method(D_METHOD("set_instance_color", "instance", "color"), &MultiMesh::set_instance_color);
	ClassDB::bind_method(D_METHOD("set_instance_colors_batch", "indices", "colors"), &MultiMesh::set_instance_colors_batch);
	ClassDB::bind_method(D_METHOD("get_instance_color", "instance"), &MultiMesh::get_instance_color);
	ClassDB::bind_method(D_METHOD("set_instance_custom_data", "instance", "custom_data"), &MultiMesh::set_instance_custom_data);
	ClassDB::bind_method(D_METHOD("get_instance_custom_data", "instance"), &MultiMesh::get_instance_custom_data);
	ClassDB::bind_method(D_METHOD("swap_instance_data", "first", "second"), &MultiMesh::swap_instance_data);
	ClassDB::bind_method(D_METHOD("remove_visible_instance", "instance"), &MultiMesh::remove_visible_instance);
	ClassDB::bind_method(D_METHOD("remove_visible_instances", "instances"), &MultiMesh::remove_visible_instances);
	ClassDB::bind_method(D_METHOD("activate_hidden_instance", "hidden_instance"), &MultiMesh::activate_hidden_instance);
	ClassDB::bind_method(D_METHOD("reset_instance_physics_interpolation", "instance"), &MultiMesh::reset_instance_physics_interpolation);
	ClassDB::bind_method(D_METHOD("reset_instances_physics_interpolation"), &MultiMesh::reset_instances_physics_interpolation);
	ClassDB::bind_method(D_METHOD("set_custom_aabb", "aabb"), &MultiMesh::set_custom_aabb);
	ClassDB::bind_method(D_METHOD("get_custom_aabb"), &MultiMesh::get_custom_aabb);
	ClassDB::bind_method(D_METHOD("get_aabb"), &MultiMesh::get_aabb);

	ClassDB::bind_method(D_METHOD("get_buffer"), &MultiMesh::get_buffer);
	ClassDB::bind_method(D_METHOD("set_instance_transform_color_buffer", "transforms", "colors"), &MultiMesh::set_instance_transform_color_buffer);
	ClassDB::bind_method(D_METHOD("pack_transform_buffer", "transforms", "colors"), &MultiMesh::pack_transform_buffer);
	ClassDB::bind_method(D_METHOD("transformed_mesh_bounds", "transforms", "margin"), &MultiMesh::transformed_mesh_bounds);
	ClassDB::bind_method(D_METHOD("shuffled_instance_buffer", "buffer", "seed"), &MultiMesh::shuffled_instance_buffer);
	ClassDB::bind_method(D_METHOD("set_buffer", "buffer"), &MultiMesh::set_buffer);

	ClassDB::bind_method(D_METHOD("set_buffer_interpolated", "buffer_curr", "buffer_prev"), &MultiMesh::set_buffer_interpolated);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "transform_format", PROPERTY_HINT_ENUM, "2D,3D"), "set_transform_format", "get_transform_format");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_colors"), "set_use_colors", "is_using_colors");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_custom_data"), "set_use_custom_data", "is_using_custom_data");
	ADD_PROPERTY(PropertyInfo(Variant::AABB, "custom_aabb", PROPERTY_HINT_NONE, "suffix:m"), "set_custom_aabb", "get_custom_aabb");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "instance_count", PROPERTY_HINT_RANGE, "0,16384,1,or_greater"), "set_instance_count", "get_instance_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "visible_instance_count", PROPERTY_HINT_RANGE, "-1,16384,1,or_greater"), "set_visible_instance_count", "get_visible_instance_count");
	// Specify all types for explicit ordering in the inspector,
	// but list generic Mesh last to allow extended types to show up at the end.
	// Keep the order in sync with MeshInstance3D's `mesh` property.
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "mesh", PROPERTY_HINT_RESOURCE_TYPE, "BoxMesh,SphereMesh,CapsuleMesh,CylinderMesh,PrismMesh,TorusMesh,PlaneMesh,QuadMesh,TextMesh,RibbonTrailMesh,TubeTrailMesh,PointMesh,ArrayMesh,ImmediateMesh,PlaceholderMesh,Mesh", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT), "set_mesh", "get_mesh");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "buffer", PROPERTY_HINT_NONE), "set_buffer", "get_buffer");

#ifndef DISABLE_DEPRECATED
	// Kept for compatibility from 3.x to 4.0.
	ClassDB::bind_method(D_METHOD("_set_transform_array", "array"), &MultiMesh::_set_transform_array);
	ClassDB::bind_method(D_METHOD("_get_transform_array"), &MultiMesh::_get_transform_array);
	ClassDB::bind_method(D_METHOD("_set_transform_2d_array", "array"), &MultiMesh::_set_transform_2d_array);
	ClassDB::bind_method(D_METHOD("_get_transform_2d_array"), &MultiMesh::_get_transform_2d_array);
	ClassDB::bind_method(D_METHOD("_set_color_array", "array"), &MultiMesh::_set_color_array);
	ClassDB::bind_method(D_METHOD("_get_color_array"), &MultiMesh::_get_color_array);
	ClassDB::bind_method(D_METHOD("_set_custom_data_array", "array"), &MultiMesh::_set_custom_data_array);
	ClassDB::bind_method(D_METHOD("_get_custom_data_array"), &MultiMesh::_get_custom_data_array);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "transform_array", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "_set_transform_array", "_get_transform_array");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR2_ARRAY, "transform_2d_array", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "_set_transform_2d_array", "_get_transform_2d_array");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "color_array", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "_set_color_array", "_get_color_array");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "custom_data_array", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "_set_custom_data_array", "_get_custom_data_array");
#endif

	ADD_GROUP("Physics Interpolation", "physics_interpolation");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "physics_interpolation_quality", PROPERTY_HINT_ENUM, "Fast,High"), "set_physics_interpolation_quality", "get_physics_interpolation_quality");

	BIND_ENUM_CONSTANT(TRANSFORM_2D);
	BIND_ENUM_CONSTANT(TRANSFORM_3D);

	BIND_ENUM_CONSTANT(INTERP_QUALITY_FAST);
	BIND_ENUM_CONSTANT(INTERP_QUALITY_HIGH);
}

MultiMesh::MultiMesh() {
	multimesh = RenderingServer::get_singleton()->multimesh_create();
}

MultiMesh::~MultiMesh() {
	ERR_FAIL_NULL(RenderingServer::get_singleton());
	RenderingServer::get_singleton()->free_rid(multimesh);
}
