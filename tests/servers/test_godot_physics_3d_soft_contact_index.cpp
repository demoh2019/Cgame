/**************************************************************************/
/*  test_godot_physics_3d_soft_contact_index.cpp                           */
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

TEST_FORCE_LINK(test_godot_physics_3d_soft_contact_index)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_soft_contact_index_3d.h"

namespace TestGodotPhysics3DSoftContactIndex {

struct Contact {
	int index_B = 0;
};

TEST_CASE("[GodotPhysics3D] Soft-contact index stays unallocated for small patches") {
	GodotSoftContactIndex3D lookup;
	LocalVector<Contact> contacts;
	for (int i = 0; i < 63; ++i) {
		contacts.push_back(Contact{ i * 17 });
		lookup.maybe_build(contacts);
		CHECK_FALSE(lookup.is_active());
	}
	CHECK(lookup.find(0) == -1);
}

TEST_CASE("[GodotPhysics3D] Soft-contact lookup survives inserts, swaps and removal") {
	GodotSoftContactIndex3D lookup;
	LocalVector<Contact> contacts;
	for (int i = 0; i < 100; ++i) {
		contacts.push_back(Contact{ i * 13 });
	}
	lookup.maybe_build(contacts);
	CHECK(lookup.is_active());

	for (int i = 0; i < 100; ++i) {
		CHECK(lookup.find(i * 13) == i);
	}
	CHECK(lookup.find(777777) == -1);

	// New nodes may have sparse or out-of-order IDs.
	contacts.push_back(Contact{ 99991 });
	lookup.appended(99991, contacts.size() - 1);
	CHECK(lookup.find(99991) == 100);

	// The solver compacts contacts by swapping in the last entry.
	const uint32_t removed_at = 20;
	const int removed_node = contacts[removed_at].index_B;
	const int moved_node = contacts[contacts.size() - 1].index_B;
	SWAP(contacts[removed_at], contacts[contacts.size() - 1]);
	contacts.resize(contacts.size() - 1);
	lookup.swap_removed(removed_node, moved_node, removed_at, contacts.size());
	CHECK(lookup.find(removed_node) == -1);
	CHECK(lookup.find(moved_node) == int(removed_at));
	CHECK(lookup.find(0) == 0);

	// Removing the last entry must not rewrite another mapping.
	const int deleted_last = contacts[contacts.size() - 1].index_B;
	lookup.swap_removed(deleted_last, deleted_last, contacts.size() - 1, contacts.size() - 1);
	contacts.resize(contacts.size() - 1);
	CHECK(lookup.find(deleted_last) == -1);
	CHECK(lookup.find(moved_node) == int(removed_at));
}

TEST_CASE("[GodotPhysics3D] Soft-contact index releases memory below sparse threshold") {
	GodotSoftContactIndex3D lookup;
	LocalVector<Contact> contacts;
	for (int i = 0; i < 64; ++i) {
		contacts.push_back(Contact{ i + 1000 });
	}
	lookup.maybe_build(contacts);
	CHECK(lookup.is_active());

	while (contacts.size() >= 16) {
		const int removed_node = contacts[contacts.size() - 1].index_B;
		lookup.swap_removed(removed_node, removed_node, contacts.size() - 1, contacts.size() - 1);
		contacts.resize(contacts.size() - 1);
	}
	CHECK_FALSE(lookup.is_active());
	CHECK(lookup.find(1000) == -1);

	// Activation is repeatable after many contacts return.
	for (int i = 64; i < 120; ++i) {
		contacts.push_back(Contact{ i + 1000 });
	}
	lookup.maybe_build(contacts);
	CHECK(lookup.is_active());
	for (uint32_t i = 0; i < contacts.size(); ++i) {
		CHECK(lookup.find(contacts[i].index_B) == int(i));
	}
}

} // namespace TestGodotPhysics3DSoftContactIndex

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
