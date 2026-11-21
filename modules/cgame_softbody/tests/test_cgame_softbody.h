/**************************************************************************/
/*  test_cgame_softbody.h                                                 */
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

#include "../cgame_hair_strands.h"
#include "../cgame_xpbd_cloth.h"
#include "../cgame_xpbd_rope.h"
#include "../cloth_instance_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "scene/resources/mesh.h"
#include "tests/test_macros.h"

namespace TestCgameSoftbody {

static bool all_finite(const Vector<Vector3> &p_points) {
	for (int i = 0; i < p_points.size(); i++) {
		if (!Math::is_finite(p_points[i].x) || !Math::is_finite(p_points[i].y) || !Math::is_finite(p_points[i].z)) {
			return false;
		}
	}
	return true;
}

static Vector3 attach_target() {
	return Vector3(1, 2, 3);
}

TEST_CASE("[CgameSoftbody][Cloth] Grid topology") {
	Ref<CgameXPBDCloth> cloth;
	cloth.instantiate();
	cloth->setup_grid(4, 3, 0.1, Transform3D());
	CHECK(cloth->columns() == 5);
	CHECK(cloth->row_count() == 4);
	CHECK(cloth->particle_count() == 20);
	// Stretch: 4 * 4 horizontal + 5 * 3 vertical.
	CHECK(cloth->stretch_constraint_count() == 31);
	CHECK(cloth->triangles().size() == 4 * 3 * 2 * 3);
	CHECK(cloth->index_of(2, 1) == 7);
}

TEST_CASE("[CgameSoftbody][Cloth] Pinned cloth stays finite and bounded") {
	Ref<CgameXPBDCloth> cloth;
	cloth.instantiate();
	cloth->setup_grid(10, 10, 0.1, Transform3D());
	for (int i = 0; i <= 10; i++) {
		cloth->pin(cloth->index_of(i, 0), cloth->positions()[cloth->index_of(i, 0)]);
	}
	for (int f = 0; f < 120; f++) {
		cloth->step(1.0 / 60.0, 8);
	}
	CHECK(all_finite(cloth->positions()));
	CHECK(cloth->max_stretch_error() < 0.25);
	// Pinned top row did not move, free bottom row hangs below it.
	CHECK(cloth->positions()[cloth->index_of(5, 0)].y == doctest::Approx(0.0));
	CHECK(cloth->positions()[cloth->index_of(5, 10)].y < -0.5);
	CHECK(cloth->is_pinned(cloth->index_of(3, 0)));
	cloth->unpin(cloth->index_of(3, 0));
	CHECK_FALSE(cloth->is_pinned(cloth->index_of(3, 0)));
}

TEST_CASE("[CgameSoftbody][Cloth] Sphere collision keeps particles outside") {
	Ref<CgameXPBDCloth> cloth;
	cloth.instantiate();
	// Rotate 90 degrees about X so the cloth lies flat in the XZ plane at y = 0.5.
	Transform3D origin(Basis(Vector3(1, 0, 0), Math::PI / 2.0), Vector3(-0.5, 0.5, 0.5));
	cloth->setup_grid(10, 10, 0.1, origin);
	const Vector3 center(0, 0.2, 0);
	const real_t radius = 0.3;
	cloth->add_sphere(center, radius);
	cloth->add_plane(Vector3(0, 1, 0), -5.0);
	for (int f = 0; f < 90; f++) {
		cloth->step(1.0 / 60.0, 8);
	}
	CHECK(all_finite(cloth->positions()));
	const Vector<Vector3> p = cloth->positions();
	real_t min_dist = Math::INF;
	for (int i = 0; i < p.size(); i++) {
		min_dist = MIN(min_dist, p[i].distance_to(center));
	}
	CHECK(min_dist >= radius - 0.02);
	// The cloth drapes over the sphere instead of falling through.
	CHECK(p[cloth->index_of(5, 5)].y > 0.2);
}

TEST_CASE("[CgameSoftbody][Cloth] Tearing removes overstretched constraints") {
	Ref<CgameXPBDCloth> cloth;
	cloth.instantiate();
	cloth->setup_grid(8, 8, 0.1, Transform3D());
	cloth->set_tear_threshold(1.05);
	const int before_constraints = cloth->constraint_count();
	const int before_triangles = cloth->triangles().size();
	cloth->pin(cloth->index_of(0, 0), Vector3(0, 0, 0));
	cloth->pin(cloth->index_of(8, 0), Vector3(0.8, 0, 0));
	// Yank one top corner far away; the neighbouring edges stretch past the threshold.
	cloth->pin(cloth->index_of(0, 0), Vector3(-6, 3, 0));
	cloth->step(1.0 / 60.0, 8);
	CHECK(cloth->get_torn_count() > 0);
	CHECK(cloth->constraint_count() < before_constraints);
	CHECK(cloth->triangles().size() < before_triangles);
}

TEST_CASE("[CgameSoftbody][Cloth] Self collision and mesh build") {
	Ref<CgameXPBDCloth> cloth;
	cloth.instantiate();
	cloth->setup_grid(6, 6, 0.1, Transform3D());
	cloth->set_self_collision_enabled(true);
	for (int f = 0; f < 30; f++) {
		cloth->step(1.0 / 60.0, 4);
	}
	CHECK(all_finite(cloth->positions()));
	Ref<ArrayMesh> mesh = cloth->build_mesh();
	REQUIRE(mesh.is_valid());
	CHECK(mesh->get_surface_count() == 1);
	CHECK(cloth->normals().size() == cloth->particle_count());
}

TEST_CASE("[CgameSoftbody][Cloth] Callable attachment follows its target") {
	Ref<CgameXPBDCloth> cloth;
	cloth.instantiate();
	cloth->setup_grid(4, 4, 0.1, Transform3D());
	Callable fn = callable_mp_static(attach_target);
	cloth->attach(0, fn);
	cloth->step(1.0 / 60.0, 4);
	CHECK(cloth->positions()[0].is_equal_approx(Vector3(1, 2, 3)));
	cloth->drive(4, Vector3(0.5, 0.5, 0.5));
	cloth->step(1.0 / 60.0, 4);
	CHECK(cloth->positions()[4].is_equal_approx(Vector3(0.5, 0.5, 0.5)));
}

TEST_CASE("[CgameSoftbody][ClothInstance3D] Defaults") {
	ClothInstance3D *node = memnew(ClothInstance3D);
	CHECK(node->get_substeps() == 8);
	CHECK(node->is_simulating());
	CHECK(node->get_cloth().is_null());
	Ref<CgameXPBDCloth> cloth;
	cloth.instantiate();
	cloth->setup_grid(2, 2, 0.1, Transform3D());
	node->set_cloth(cloth);
	CHECK(node->get_cloth() == cloth);
	node->attach_particle_to_bone(0, "Head", Vector3(0, 0.1, 0));
	CHECK(node->get_bone_attachments().size() == 1);
	node->clear_bone_attachments();
	CHECK(node->get_bone_attachments().size() == 0);
	memdelete(node);
}

TEST_CASE("[CgameSoftbody][Rope] Length is preserved while hanging") {
	Ref<CgameXPBDRope> rope;
	rope.instantiate();
	rope->setup(Vector3(0, 0, 0), Vector3(2, 0, 0), 20);
	CHECK(rope->particle_count() == 21);
	CHECK(rope->segment_count() == 20);
	CHECK(rope->rest_length() == doctest::Approx(2.0));
	rope->pin(0, Vector3(0, 0, 0));
	for (int f = 0; f < 120; f++) {
		rope->step(1.0 / 60.0, 8);
	}
	CHECK(all_finite(rope->positions()));
	CHECK(rope->length() == doctest::Approx(2.0).epsilon(0.05));
	// Hangs down from the pinned end.
	CHECK(rope->positions()[20].y < -1.5);
}

TEST_CASE("[CgameSoftbody][Rope] Sphere collision and segment distance") {
	Ref<CgameXPBDRope> rope;
	rope.instantiate();
	rope->setup(Vector3(-1, 1, 0), Vector3(1, 1, 0), 20);
	rope->pin(0, Vector3(-1, 1, 0));
	rope->pin(20, Vector3(1, 1, 0));
	const Vector3 center(0, 0.8, 0);
	rope->add_sphere(center, 0.3);
	for (int f = 0; f < 120; f++) {
		rope->step(1.0 / 60.0, 8);
	}
	const Vector<Vector3> p = rope->positions();
	real_t min_dist = Math::INF;
	for (int i = 0; i < p.size(); i++) {
		min_dist = MIN(min_dist, p[i].distance_to(center));
	}
	CHECK(min_dist >= 0.3 - 0.02);

	const Vector2 st = CgameXPBDRope::closest_params(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0.5, 1, -1), Vector3(0.5, 1, 1));
	CHECK(st.x == doctest::Approx(0.5));
	CHECK(st.y == doctest::Approx(0.5));
}

TEST_CASE("[CgameSoftbody][Rope] Crossing number counts projected crossings") {
	Ref<CgameXPBDRope> rope;
	rope.instantiate();
	Vector<Vector3> pts;
	// A figure-eight in the XY plane crosses itself once.
	pts.push_back(Vector3(-1, -1, 0));
	pts.push_back(Vector3(1, 1, 0));
	pts.push_back(Vector3(1, 1.5, 0));
	pts.push_back(Vector3(-1, 1.5, 0));
	pts.push_back(Vector3(-1, 1, 0));
	pts.push_back(Vector3(1, -1, 0));
	rope->setup_points(pts);
	CHECK(rope->crossing_number() == 1);
	CHECK(rope->knot_count() == 0);
}

TEST_CASE("[CgameSoftbody][Hair] Segment lengths stay constant") {
	Ref<CgameHairStrands> hair;
	hair.instantiate();
	Vector<Vector3> roots;
	Vector<Vector3> normals;
	for (int i = 0; i < 4; i++) {
		roots.push_back(Vector3(real_t(i) * 0.02, 0, 0));
		normals.push_back(Vector3(0, -1, 0));
	}
	hair->grow_guides(roots, normals, 6, 0.3);
	CHECK(hair->get_guide_count() == 4);
	CHECK(hair->get_points_per_guide() == 7);
	CHECK(hair->get_seg_len() == doctest::Approx(0.05));

	Transform3D head;
	hair->reset(head);
	for (int f = 0; f < 60; f++) {
		// Shake the head sideways.
		head.origin = Vector3(Math::sin(real_t(f) * 0.3) * 0.2, 0, 0);
		hair->step(1.0 / 60.0, head);
	}
	const Vector<Vector3> pos = hair->get_pos();
	CHECK(all_finite(pos));
	for (int g = 0; g < hair->get_guide_count(); g++) {
		for (int i = 1; i < hair->get_points_per_guide(); i++) {
			const int k = g * hair->get_points_per_guide() + i;
			CHECK(pos[k].distance_to(pos[k - 1]) == doctest::Approx(0.05).epsilon(0.15));
		}
	}
	// Roots follow the head.
	CHECK(pos[0].is_equal_approx(head.xform(hair->get_rest()[0])));
}

TEST_CASE("[CgameSoftbody][Hair] Capsule collision pushes strands out") {
	Ref<CgameHairStrands> hair;
	hair.instantiate();
	Vector<Vector3> roots;
	Vector<Vector3> normals;
	roots.push_back(Vector3(0.1, 0, 0));
	normals.push_back(Vector3(-1, 0, 0)); // Grows straight through the head.
	hair->grow_guides(roots, normals, 4, 0.08);
	hair->add_capsule(Vector3(0, -0.05, 0), Vector3(0, 0.05, 0), 0.1);
	const Transform3D head(Basis(), Vector3(1, 2, 3));
	hair->reset(head);
	for (int f = 0; f < 30; f++) {
		hair->step(1.0 / 60.0, head);
	}
	const Vector<Vector3> pos = hair->get_pos();
	const real_t min_allowed = 0.1 + hair->get_collision_margin() - 0.0001;
	for (int i = 1; i < hair->get_points_per_guide(); i++) {
		const Vector3 local = head.affine_inverse().xform(pos[i]);
		const real_t axis_t = CLAMP(local.y, -0.05, 0.05);
		CHECK(local.distance_to(Vector3(0, axis_t, 0)) >= min_allowed);
	}
}

TEST_CASE("[CgameSoftbody][Hair] LOD, strands and ribbon mesh") {
	Ref<CgameHairStrands> hair;
	hair.instantiate();
	Vector<Vector3> roots;
	Vector<Vector3> normals;
	for (int i = 0; i < 3; i++) {
		roots.push_back(Vector3(real_t(i) * 0.05, 0, 0));
		normals.push_back(Vector3(0, -1, 0));
	}
	hair->grow_guides(roots, normals, 5, 0.25);
	hair->reset(Transform3D());

	CHECK(hair->lod_strand_count(0.0) == 0);
	int last = 0;
	for (int i = 1; i <= 20; i++) {
		const int c = hair->lod_strand_count(real_t(i) / 20.0);
		CHECK(c >= last);
		CHECK(c <= hair->get_max_per_guide());
		last = c;
	}

	const TypedArray<PackedVector3Array> strands = hair->render_strands(3, 42);
	CHECK(strands.size() == 9);
	const Vector<Vector3> first = strands[0];
	CHECK(first.size() == 6);
	// Strand 0 of guide 0 is the guide itself.
	CHECK(first[3].is_equal_approx(hair->guide_points(0)[3]));
	// Deterministic for the same seed.
	const TypedArray<PackedVector3Array> again = hair->render_strands(3, 42);
	CHECK(Vector<Vector3>(strands[4]) == Vector<Vector3>(again[4]));

	Ref<ArrayMesh> ribbon = hair->build_ribbon_mesh(3, 42, 0.002);
	REQUIRE(ribbon.is_valid());
	CHECK(ribbon->get_surface_count() == 1);
	CHECK(ribbon->surface_get_array_len(0) == 9 * 6 * 2);
	Ref<ArrayMesh> from_strands = hair->build_mesh(strands, 0.002);
	CHECK(from_strands->surface_get_array_len(0) == ribbon->surface_get_array_len(0));
}

} // namespace TestCgameSoftbody
