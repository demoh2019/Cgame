/**************************************************************************/
/*  test_flock_3d.cpp                                                     */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_flock_3d)

#ifndef _3D_DISABLED

#include "scene/3d/flock_3d.h"

namespace TestFlock3D {

TEST_CASE("[SceneTree][Flock3D] Separation pushes overlapping agents apart") {
	LocalVector<Vector3> positions;
	positions.push_back(Vector3());
	positions.push_back(Vector3(0.5, 0, 0));
	LocalVector<Vector3> velocities;
	velocities.push_back(Vector3(0, 0, 1));
	velocities.push_back(Vector3(0, 0, 1));
	const Vector3 f = Flock3D::compute_steering(0, positions, velocities, 2, Vector3(), 8.0f, 1.6f, 0.35f, 0.5f, 2.5f, 0.0f);
	CHECK(f.x < 0.0f);
}

TEST_CASE("[SceneTree][Flock3D] Strays are pulled home and the flock stays bounded") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_instance_count(12);
	Flock3D *flock = memnew(Flock3D);
	flock->set_multimesh(mm);
	flock->set_home_radius(10.0f);
	flock->set_agent_count(12);
	CHECK(flock->get_agent_count() == 12);
	for (int i = 0; i < 600; i++) {
		flock->step(1.0 / 30.0);
	}
	for (int i = 0; i < 12; i++) {
		const Vector3 p = flock->get_agent_position(i);
		CHECK(p.is_finite());
		CHECK(p.length() < 40.0f);
	}
	CHECK(mm->get_visible_instance_count() == 12);
	// Scatter kicks agents away from the threat.
	const Vector3 before = flock->get_agent_position(0);
	flock->scatter_from(before + Vector3(0.1, 0, 0), 20.0f, 5.0f);
	flock->step(1.0 / 30.0);
	CHECK(flock->get_agent_position(0).x < before.x);
	flock->set_agent_count(5000);
	CHECK(flock->get_agent_count() == 1024);
	memdelete(flock);
}

TEST_CASE("[SceneTree][Flock3D] Seeded flock resets reproducibly across quality and scene changes") {
	Flock3D *first = memnew(Flock3D);
	Flock3D *second = memnew(Flock3D);
	const uint64_t seed = UINT64_C(0x8f526e51b7b8a28e);
	first->set_simulation_seed(seed);
	second->set_simulation_seed(seed);
	CHECK(first->get_simulation_seed() == seed);
	CHECK(second->get_simulation_seed() == seed);
	first->set_agent_count(8);
	second->set_agent_count(8);
	for (int i = 0; i < 8; i++) {
		CHECK(first->get_agent_position(i).is_equal_approx(second->get_agent_position(i)));
	}

	// Native Flock3D is reset by NOTIFICATION_READY and quality changes;
	// reusing the same seed must not depend on any previous random draws.
	const Vector3 before = first->get_agent_position(0);
	first->set_agent_count(12);
	first->set_agent_count(8);
	CHECK(first->get_agent_position(0).is_equal_approx(before));
	for (int i = 0; i < 8; i++) {
		CHECK(first->get_agent_position(i).is_equal_approx(second->get_agent_position(i)));
	}

	// A different world seed changes the simulated flock (not just its
	// MultiMesh wing phases or unused GDScript position buffers).
	second->set_simulation_seed(seed + 1);
	CHECK(!first->get_agent_position(0).is_equal_approx(second->get_agent_position(0)));
	second->set_simulation_seed(seed);
	CHECK(first->get_agent_position(0).is_equal_approx(second->get_agent_position(0)));

	memdelete(first);
	memdelete(second);
}

} // namespace TestFlock3D

#endif // _3D_DISABLED
