/**************************************************************************/
/*  test_godot_physics_contact_recycling.cpp                               */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_contact_recycling)

#include "servers/physics_contact_recycling.h"

namespace TestGodotPhysicsContactRecycling {

TEST_CASE("[GodotPhysics] Conservative narrowphase recycling checks") {
	GodotPhysicsContactRecycling cache;

	CHECK_FALSE(cache.can_reuse(1, 1, true, 2, false));
	cache.remember(5, 9);
	CHECK(cache.can_reuse(5, 9, true, 1, false));
	CHECK(cache.can_reuse(5, 9, true, 4, false));
	CHECK_FALSE(cache.can_reuse(5, 9, false, 4, false)); // Separated in the previous frame.
	CHECK_FALSE(cache.can_reuse(5, 9, true, 0, false)); // No cached manifold points.
	CHECK_FALSE(cache.can_reuse(5, 9, true, 2, true)); // CCD must run every frame.
	CHECK_FALSE(cache.can_reuse(6, 9, true, 2, false)); // Body A moved or shape changed.
	CHECK_FALSE(cache.can_reuse(5, 10, true, 2, false)); // Body B moved or shape changed.

	cache.remember(6, 10);
	CHECK(cache.can_reuse(6, 10, true, 2, false));
	CHECK_FALSE(cache.can_reuse(5, 9, true, 2, false));

	// Reserve 0 for an invalid/not-yet-generated key (including wrap around).
	cache.remember(0, 10);
	CHECK_FALSE(cache.can_reuse(0, 10, true, 1, false));
}

} // namespace TestGodotPhysicsContactRecycling

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_object_2d.h"

namespace TestGodotPhysicsContactRecycling {

class Probe2D : public GodotCollisionObject2D {
public:
	Probe2D() :
			GodotCollisionObject2D(TYPE_BODY) {}

	void move(const Transform2D &p_transform) {
		_set_transform(p_transform, false);
	}

	virtual void set_space(GodotSpace2D *) override {}

protected:
	virtual void _shapes_changed() override {}
};

TEST_CASE("[GodotPhysics2D] Geometry cache invalidated by body movement and shape edits") {
	Probe2D body;
	const uint64_t first = body.get_collision_geometry_version();
	CHECK(first != 0);

	body.move(Transform2D());
	CHECK(body.get_collision_geometry_version() == first);

	body.move(Transform2D(real_t(0.2), Vector2(4, -2)));
	const uint64_t moved = body.get_collision_geometry_version();
	CHECK(moved > first);

	body.move(Transform2D(real_t(0.2), Vector2(4, -2)));
	CHECK(body.get_collision_geometry_version() == moved);

	body.set_collision_mask(3);
	CHECK(body.get_collision_geometry_version() > moved);
	const uint64_t filter_changed = body.get_collision_geometry_version();

	GodotCircleShape2D circle;
	circle.add_owner(&body);
	circle.set_data(real_t(1.0));
	CHECK(body.get_collision_geometry_version() > filter_changed);
	const uint64_t shape_changed = body.get_collision_geometry_version();
	circle.set_data(real_t(2.0));
	CHECK(body.get_collision_geometry_version() > shape_changed);
	circle.remove_owner(&body);
}

} // namespace TestGodotPhysicsContactRecycling

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_collision_object_3d.h"

namespace TestGodotPhysicsContactRecycling {

class Probe3D : public GodotCollisionObject3D {
public:
	Probe3D() :
			GodotCollisionObject3D(TYPE_BODY) {}

	void move(const Transform3D &p_transform) {
		_set_transform(p_transform, false);
	}

	virtual void set_space(GodotSpace3D *) override {}

protected:
	virtual void _shapes_changed() override {}
};

TEST_CASE("[GodotPhysics3D] Geometry cache invalidated by body movement and shape edits") {
	Probe3D body;
	const uint64_t first = body.get_collision_geometry_version();
	CHECK(first != 0);

	body.move(Transform3D());
	CHECK(body.get_collision_geometry_version() == first);

	body.move(Transform3D(Basis(Vector3(0, 1, 0), real_t(0.3)), Vector3(3, 4, 5)));
	const uint64_t moved = body.get_collision_geometry_version();
	CHECK(moved > first);

	body.move(Transform3D(Basis(Vector3(0, 1, 0), real_t(0.3)), Vector3(3, 4, 5)));
	CHECK(body.get_collision_geometry_version() == moved);

	body.set_collision_layer(7);
	CHECK(body.get_collision_geometry_version() > moved);
	const uint64_t filter_changed = body.get_collision_geometry_version();

	GodotSphereShape3D sphere;
	sphere.add_owner(&body);
	sphere.set_data(real_t(1.0));
	CHECK(body.get_collision_geometry_version() > filter_changed);
	const uint64_t shape_changed = body.get_collision_geometry_version();
	sphere.set_data(real_t(2.0));
	CHECK(body.get_collision_geometry_version() > shape_changed);
	sphere.remove_owner(&body);
}

} // namespace TestGodotPhysicsContactRecycling

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
