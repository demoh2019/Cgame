/**************************************************************************/
/*  test_physics_island_storage.cpp                                       */
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

TEST_FORCE_LINK(test_physics_island_storage)

#include "servers/physics_island_storage.h"

namespace TestPhysicsIslandStorage {

struct Tracked {
	static inline uint32_t destructed = 0;
	uint32_t value = 0;
	~Tracked() {
		++destructed;
	}
};

TEST_CASE("[Physics] Island scratch memory is reclaimed incrementally after quiet frames") {
	Tracked::destructed = 0;
	LocalVector<LocalVector<Tracked>> islands;
	constexpr uint32_t PEAK = 4096;
	constexpr uint32_t MIN_RETAINED = 128;
	constexpr uint32_t CHUNK = 1024;
	islands.resize(PEAK);
	for (uint32_t i = 0; i < PEAK; ++i) {
		islands[i].resize(1);
		islands[i][0].value = i;
	}
	uint8_t quiet_steps = 0;

	// Retain buffers through 15 idle steps, avoiding allocation churn when
	// a large island count reappears on alternating or bursty frames.
	for (int i = 0; i < 15; ++i) {
		godot_physics_reclaim_idle_island_storage(islands, 8, quiet_steps);
		CHECK(islands.size() == PEAK);
		CHECK(Tracked::destructed == 0);
	}
	CHECK(quiet_steps == 15);

	// Release at most 1024 nested islands in a single physics tick.
	godot_physics_reclaim_idle_island_storage(islands, 8, quiet_steps);
	CHECK(islands.size() == PEAK - CHUNK);
	CHECK(Tracked::destructed == CHUNK);
	CHECK(quiet_steps == 16);
	CHECK(islands[7][0].value == 7);

	godot_physics_reclaim_idle_island_storage(islands, 8, quiet_steps);
	CHECK(islands.size() == PEAK - 2 * CHUNK);
	CHECK(Tracked::destructed == 2 * CHUNK);
	godot_physics_reclaim_idle_island_storage(islands, 8, quiet_steps);
	CHECK(islands.size() == PEAK - 3 * CHUNK);
	CHECK(Tracked::destructed == 3 * CHUNK);
	godot_physics_reclaim_idle_island_storage(islands, 8, quiet_steps);
	CHECK(islands.size() == MIN_RETAINED);
	CHECK(Tracked::destructed == PEAK - MIN_RETAINED);
	CHECK(islands.get_capacity() <= MIN_RETAINED);

	// Re-growth and reusing the survivor prefix must remain correct.
	for (uint32_t i = 0; i < MIN_RETAINED; ++i) {
		CHECK(islands[i][0].value == i);
	}
	islands.resize(300);
	islands[299].resize(1);
	islands[299][0].value = 299;
	godot_physics_reclaim_idle_island_storage(islands, 300, quiet_steps);
	CHECK(quiet_steps == 0);
	CHECK(islands.size() == 300);
	CHECK(islands[299][0].value == 299);
}

TEST_CASE("[Physics] Island scratch reclamation cancels when activity returns") {
	LocalVector<LocalVector<int>> islands;
	islands.resize(1024);
	uint8_t quiet_steps = 0;
	for (int i = 0; i < 15; ++i) {
		godot_physics_reclaim_idle_island_storage(islands, 0, quiet_steps);
	}
	CHECK(islands.size() == 1024);
	CHECK(quiet_steps == 15);

	// Any frame that uses a substantial share of the cached islands
	// restarts the quiet countdown.
	godot_physics_reclaim_idle_island_storage(islands, 400, quiet_steps);
	CHECK(quiet_steps == 0);
	for (int i = 0; i < 15; ++i) {
		godot_physics_reclaim_idle_island_storage(islands, 0, quiet_steps);
	}
	CHECK(islands.size() == 1024);
	godot_physics_reclaim_idle_island_storage(islands, 0, quiet_steps);
	CHECK(islands.size() == 128);

	// Common tiny scenes retain their small scratch buffers indefinitely.
	LocalVector<LocalVector<int>> small;
	small.resize(512);
	quiet_steps = 0;
	for (int i = 0; i < 100; ++i) {
		godot_physics_reclaim_idle_island_storage(small, 0, quiet_steps);
	}
	CHECK(small.size() == 512);
	CHECK(quiet_steps == 0);
}

} // namespace TestPhysicsIslandStorage
