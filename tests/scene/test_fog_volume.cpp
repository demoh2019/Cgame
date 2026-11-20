/**************************************************************************/
/*  test_fog_volume.cpp                                                   */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_fog_volume)

#ifndef _3D_DISABLED

#include "scene/3d/fog_volume.h"
#include "scene/resources/material.h"

namespace TestFogVolume {

TEST_CASE("[SceneTree][FogVolume] Stable world-grid anchoring for animated volumetric fog") {
	// World grid anchoring is invariant to tiny camera motions and preserves
	// vertical height: the moving ground plane is never snapped in Y.
	const Vector3 input(14.4f, 3.2f, -11.3f);
	const Vector3 expected(16.0f, 3.2f, -8.0f);
	CHECK(FogVolume::snap_world_anchor(input, 8.0f) == expected);
	CHECK(FogVolume::snap_world_anchor(Vector3(-14.4f, -2.5f, 11.3f), 8.0f) ==
			Vector3(-16.0f, -2.5f, 8.0f));
	CHECK(FogVolume::snap_world_anchor(expected, 8.0f) == expected);
	CHECK(FogVolume::snap_world_anchor(input, 0.0f) == input);

	FogVolume *volume = memnew(FogVolume);
	CHECK(volume->set_snapped_world_anchor(input, 8.0f));
	CHECK(volume->get_global_position() == expected);
	// No redundant RenderingServer transform upload for the same cell.
	CHECK_FALSE(volume->set_snapped_world_anchor(Vector3(14.6f, 3.2f, -11.1f), 8.0f));
	CHECK(volume->get_global_position() == expected);
	CHECK(volume->set_snapped_world_anchor(Vector3(24.2f, 3.2f, -11.1f), 8.0f));
	CHECK(volume->get_global_position() == Vector3(24.0f, 3.2f, -8.0f));
	// Existing fog volume size/culling bounds remain untouched by snapping.
	CHECK(volume->get_aabb() == AABB(Vector3(-1.0f, -1.0f, -1.0f), Vector3(2.0f, 2.0f, 2.0f)));
	memdelete(volume);
}

TEST_CASE("[SceneTree][FogVolume] Idempotent rendering resource setters") {
	FogVolume *volume = memnew(FogVolume);
	CHECK(volume->get_size() == Vector3(2.0f, 2.0f, 2.0f));
	CHECK(volume->get_shape() == RSE::FOG_VOLUME_SHAPE_BOX);
	CHECK(volume->get_material().is_null());

	SUBCASE("Size is clamped before comparing, and repeated sizes preserve bounds") {
		const Vector3 desired(80.0f, 14.0f, 64.0f);
		volume->set_size(desired);
		const AABB expected(-desired / 2.0f, desired);
		CHECK(volume->get_aabb() == expected);
		volume->set_size(desired);
		CHECK(volume->get_aabb() == expected);
		volume->set_size(Vector3(-4.0f, 14.0f, 64.0f));
		CHECK(volume->get_size() == Vector3(0.0f, 14.0f, 64.0f));
		volume->set_size(Vector3(-8.0f, 14.0f, 64.0f));
		CHECK(volume->get_size() == Vector3(0.0f, 14.0f, 64.0f));
	}

	SUBCASE("Shape changes retain correct local/global AABB") {
		volume->set_shape(RSE::FOG_VOLUME_SHAPE_WORLD);
		volume->set_shape(RSE::FOG_VOLUME_SHAPE_WORLD);
		CHECK(volume->get_aabb() == AABB());
		volume->set_shape(RSE::FOG_VOLUME_SHAPE_BOX);
		volume->set_shape(RSE::FOG_VOLUME_SHAPE_BOX);
		CHECK(volume->get_aabb() == AABB(Vector3(-1.0f, -1.0f, -1.0f), Vector3(2.0f, 2.0f, 2.0f)));
	}

	SUBCASE("Material assignment never drops source references") {
		Ref<StandardMaterial3D> mat;
		mat.instantiate();
		volume->set_material(mat);
		volume->set_material(mat);
		CHECK(volume->get_material() == mat);
		volume->set_material(Ref<Material>());
		volume->set_material(Ref<Material>());
		CHECK(volume->get_material().is_null());
	}

	memdelete(volume);
}

} // namespace TestFogVolume

#endif // _3D_DISABLED
