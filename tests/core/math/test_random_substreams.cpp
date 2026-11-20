/**************************************************************************/
/*  test_random_substreams.cpp                                            */
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
/* permit persons to whom the Software is furnished to do so, subject to   */
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

TEST_FORCE_LINK(test_random_substreams)

#include "core/math/random_number_generator.h"

namespace TestRandomSubstreams {

TEST_CASE("[RandomNumberGenerator] Named substreams are deterministic and independent of parent state") {
	Ref<RandomNumberGenerator> parent;
	parent.instantiate();
	parent->set_seed(1337);
	const uint64_t original_state = parent->get_state();

	Ref<RandomNumberGenerator> positions = parent->fork(1);
	Ref<RandomNumberGenerator> velocities = parent->fork(2);
	Ref<RandomNumberGenerator> another_positions = parent->fork(1);

	REQUIRE(positions.is_valid());
	REQUIRE(velocities.is_valid());
	REQUIRE(another_positions.is_valid());
	CHECK(parent->get_state() == original_state);
	CHECK(parent->get_seed() == 1337);
	// Version-one seed mixer golden vectors: cosmetic worlds and saved seeds
	// must not silently change if someone refactors the native implementation.
	CHECK(parent->get_substream_seed(1) == UINT64_C(0x8f526e51b7b8a28e));
	CHECK(parent->get_substream_seed(2) == UINT64_C(0x340c10e1d6410236));
	CHECK(parent->get_substream_seed(3) == UINT64_C(0xf3c91fbd0ac485e5));
	CHECK(positions->get_seed() == parent->get_substream_seed(1));
	CHECK(velocities->get_seed() == parent->get_substream_seed(2));
	CHECK(positions->get_seed() != velocities->get_seed());
	CHECK(positions->get_seed() != parent->get_seed());

	// Each child has an independent PCG state. Drawing from positions cannot
	// affect the velocity stream or the original parent.
	for (int i = 0; i < 64; i++) {
		CHECK(positions->randi() == another_positions->randi());
	}
	const uint64_t velocity_state = velocities->get_state();
	positions->randi();
	CHECK(velocities->get_state() == velocity_state);
	CHECK(parent->get_state() == original_state);

	// Names are derived from the initial seed, not from the consumed state.
	for (int i = 0; i < 15; i++) {
		parent->randi();
	}
	CHECK(parent->get_substream_seed(1) == positions->get_seed());
	Ref<RandomNumberGenerator> rejoined = parent->fork(2);
	CHECK(rejoined->get_seed() == velocities->get_seed());
	for (int i = 0; i < 32; i++) {
		CHECK(rejoined->randi() == velocities->randi());
	}
}

TEST_CASE("[RandomNumberGenerator] Substreams distinguish full-width signed IDs and parent seeds") {
	Ref<RandomNumberGenerator> parent;
	parent.instantiate();
	parent->set_seed(0);
	const uint64_t a = parent->get_substream_seed(1);
	const uint64_t b = parent->get_substream_seed(-1);
	const uint64_t c = parent->get_substream_seed(INT64_C(0x100000001));
	const uint64_t d = parent->get_substream_seed(0);
	CHECK(a != b);
	CHECK(a != c);
	CHECK(a != d);
	CHECK(b != c);
	CHECK(c != d);

	parent->set_seed(UINT64_C(0x100000001));
	CHECK(parent->get_substream_seed(1) != a);
	parent->set_seed(UINT64_C(0x8000000000000001));
	CHECK(parent->get_substream_seed(1) != a);

	Ref<RandomNumberGenerator> child = parent->fork(-23);
	Ref<RandomNumberGenerator> grandchild = child->fork(7);
	CHECK(grandchild->get_seed() == child->get_substream_seed(7));
	CHECK(grandchild->get_seed() != child->get_seed());
}

} // namespace TestRandomSubstreams
