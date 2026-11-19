/**************************************************************************/
/*  test_godot_physics_3d_constraint_slots.cpp                            */
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

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_3d_constraint_slots)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_body_3d.h"
#include "modules/godot_physics_3d/godot_constraint_3d.h"

namespace TestGodotPhysics3DConstraintSlots {

class PairStub : public GodotConstraint3D {
	GodotBody3D *bodies[2] = { nullptr, nullptr };

public:
	virtual bool setup(real_t p_step) override { return false; }
	virtual bool pre_solve(real_t p_step) override { return false; }
	virtual void solve(real_t p_step) override {}

	PairStub(GodotBody3D *p_a, GodotBody3D *p_b) :
			GodotConstraint3D(bodies, 2) {
		bodies[0] = p_a;
		bodies[1] = p_b;
		p_a->add_constraint(this, 0);
		p_b->add_constraint(this, 1);
	}
	~PairStub() {
		bodies[0]->remove_constraint(this, 0);
		bodies[1]->remove_constraint(this, 1);
	}
};

// Every constraint must find itself at the slot it caches, on both bodies.
static void check_slots(const Vector<PairStub *> &p_constraints, const Vector<bool> &p_alive, GodotBody3D *p_shared) {
	uint32_t alive_count = 0;
	for (int i = 0; i < p_constraints.size(); i++) {
		if (!p_alive[i]) {
			continue;
		}
		alive_count++;
		const PairStub *c = p_constraints[i];
		const uint32_t slot = c->get_body_slot(0);
		REQUIRE(slot < p_shared->get_constraint_list().size());
		CHECK(p_shared->get_constraint_list()[slot].first == c);
		CHECK(p_shared->get_constraint_list()[slot].second == 0);
		const GodotBody3D *other = c->get_body_ptr()[1];
		REQUIRE(other->get_constraint_list().size() == 1);
		CHECK(other->get_constraint_list()[c->get_body_slot(1)].first == c);
	}
	CHECK(p_shared->get_constraint_list().size() == alive_count);
}

TEST_CASE("[GodotPhysics3D] Body constraint slots survive removal in any order") {
	const int count = 257;
	GodotBody3D shared;
	LocalVector<GodotBody3D> others;
	others.resize(count);

	Vector<PairStub *> constraints;
	Vector<bool> alive;
	for (int i = 0; i < count; i++) {
		constraints.push_back(memnew(PairStub(&shared, &others[i])));
		alive.push_back(true);
	}
	check_slots(constraints, alive, &shared);

	// 37 is coprime with 257, so this visits every constraint exactly once in a scrambled order.
	for (int i = 0; i < count; i++) {
		const int victim = (i * 37) % count;
		memdelete(constraints[victim]);
		constraints.write[victim] = nullptr;
		alive.write[victim] = false;
		if (i % 16 == 0) {
			check_slots(constraints, alive, &shared);
		}
	}
	check_slots(constraints, alive, &shared);
	CHECK(shared.get_constraint_list().is_empty());
}

TEST_CASE("[GodotPhysics3D] Removing a constraint after its body list was cleared is harmless") {
	GodotBody3D a;
	GodotBody3D b;
	PairStub *constraint = memnew(PairStub(&a, &b));
	PairStub *other = memnew(PairStub(&a, &b));
	a.clear_constraint_list();
	memdelete(constraint);
	CHECK(a.get_constraint_list().is_empty());
	CHECK(b.get_constraint_list().size() == 1);
	memdelete(other);
	CHECK(b.get_constraint_list().is_empty());
}

} // namespace TestGodotPhysics3DConstraintSlots

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
