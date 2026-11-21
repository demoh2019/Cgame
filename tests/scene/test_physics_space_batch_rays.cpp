/**************************************************************************/
/*  test_physics_space_batch_rays.cpp                                     */
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
/* the following conditions:                                              */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_space_batch_rays)

#ifndef PHYSICS_3D_DISABLED

#include "servers/physics_3d/direct_states/physics_direct_space_state_3d.h"

namespace TestPhysicsSpaceBatchRays {

// A fake physics space makes ray query semantics deterministic without
// requiring an engine physics tick, a running 3D world or any GPU.
class MockSpace : public PhysicsDirectSpaceState3D {
public:
	int calls = 0;
	bool intersect_ray(const PS3DT::RayParameters &p_parameters, PS3DT::RayResult &r_result) override {
		calls++;
		if (p_parameters.collision_mask != 1 || !p_parameters.collide_with_bodies) {
			return false;
		}
		r_result.position = p_parameters.from.lerp(p_parameters.to, 0.5f);
		r_result.normal = Vector3(0, 1, 0);
		r_result.face_index = -1;
		r_result.shape = 0;
		return true;
	}

	int intersect_point(const PS3DT::PointParameters &, PS3DT::ShapeResult *, int) override { return 0; }
	int intersect_shape(const PS3DT::ShapeParameters &, PS3DT::ShapeResult *, int) override { return 0; }
	bool cast_motion(const PS3DT::ShapeParameters &, real_t &, real_t &, PS3DT::ShapeRestInfo *) override { return false; }
	bool collide_shape(const PS3DT::ShapeParameters &, Vector3 *, int, int &) override { return false; }
	bool rest_info(const PS3DT::ShapeParameters &, PS3DT::ShapeRestInfo *) override { return false; }
	Vector3 get_closest_point_to_object_volume(RID, const Vector3 p_point) const override { return p_point; }
};

TEST_CASE("[SceneTree][PhysicsDirectSpaceState3D] Batch rays preserve order, masks and misses") {
	MockSpace space;
	Array queries;
	Ref<PhysicsRayQueryParameters3D> wall;
	wall.instantiate();
	wall->set_from(Vector3(0, 1, 0));
	wall->set_to(Vector3(10, 1, 0));
	wall->set_collision_mask(1);
	queries.push_back(wall);
	Ref<PhysicsRayQueryParameters3D> non_matching;
	non_matching.instantiate();
	non_matching->set_from(Vector3(0, 5, 0));
	non_matching->set_to(Vector3(5, 5, 0));
	non_matching->set_collision_mask(2);
	queries.push_back(non_matching);
	Ref<PhysicsRayQueryParameters3D> no_bodies;
	no_bodies.instantiate();
	no_bodies->set_from(Vector3(1, 1, 1));
	no_bodies->set_to(Vector3(4, 1, 1));
	no_bodies->set_collision_mask(1);
	no_bodies->set_collide_with_bodies(false);
	queries.push_back(no_bodies);

	const Array batch = space.call(SNAME("intersect_rays"), queries);
	REQUIRE(batch.size() == 3);
	CHECK(space.calls == 3);
	Dictionary first = batch[0];
	Dictionary second = batch[1];
	Dictionary third = batch[2];
	CHECK(!first.is_empty());
	CHECK(second.is_empty());
	CHECK(third.is_empty());
	CHECK(Vector3(first["position"]).is_equal_approx(Vector3(5, 1, 0)));
	CHECK(Vector3(first["normal"]).is_equal_approx(Vector3(0, 1, 0)));
	CHECK((first.has("collider") && first.has("shape") && first.has("rid") && first.has("collider_id") && first.has("face_index")));

	const Dictionary single = space.call(SNAME("intersect_ray"), wall);
	CHECK(Vector3(first["position"]).is_equal_approx(Vector3(single["position"])));
	CHECK(first.keys().size() == single.keys().size());
	CHECK(space.calls == 4);

	Array empty;
	const Array no_queries = space.call(SNAME("intersect_rays"), empty);
	CHECK(no_queries.is_empty());
	CHECK(space.calls == 4);
}

} // namespace TestPhysicsSpaceBatchRays

#endif // PHYSICS_3D_DISABLED
