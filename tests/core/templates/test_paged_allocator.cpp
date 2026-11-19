/**************************************************************************/
/*  test_paged_allocator.cpp                                              */
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
/* OR OTHER DEALINGS IN THE SOFTWARE.                                     */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_paged_allocator)

#include "core/templates/paged_allocator.h"

#include <vector>

namespace TestPagedAllocator {

struct TrackedPageItem {
	inline static int live = 0;
	uint32_t value = 0;

	explicit TrackedPageItem(uint32_t p_value) :
			value(p_value) {
		live++;
	}
	~TrackedPageItem() {
		live--;
	}
};

TEST_CASE("[PagedAllocator] Metadata growth and nontrivial page recycling") {
	TrackedPageItem::live = 0;
	PagedAllocator<TrackedPageItem, false, 4> pool(4);
	std::vector<TrackedPageItem *> pointers;
	pointers.reserve(517);

	for (uint32_t i = 0; i < 517; i++) {
		pointers.push_back(pool.alloc(i + 7000));
		CHECK(pointers.back()->value == i + 7000);
	}
	CHECK(TrackedPageItem::live == 517);

	// Recycling in a different order exercises all free-list page slots.
	for (size_t i = 1; i < pointers.size(); i += 2) {
		pool.free(pointers[i]);
	}
	for (size_t i = 0; i < pointers.size(); i += 2) {
		pool.free(pointers[i]);
	}
	CHECK(TrackedPageItem::live == 0);
	pointers.clear();

	for (uint32_t i = 0; i < 517; i++) {
		pointers.push_back(pool.alloc(i * 3));
		CHECK(pointers.back()->value == i * 3);
	}
	for (size_t i = pointers.size(); i > 0; i--) {
		pool.free(pointers[i - 1]);
	}
	CHECK(TrackedPageItem::live == 0);
	pool.reset();
}

TEST_CASE("[PagedAllocator] Thread-safe pool metadata growth and reuse") {
	PagedAllocator<uint32_t, true, 2> pool(2);
	std::vector<uint32_t *> values;
	values.reserve(261);

	for (uint32_t i = 0; i < 261; i++) {
		values.push_back(pool.alloc(i ^ 0xdead));
	}
	for (uint32_t i = 0; i < 261; i++) {
		CHECK(*values[i] == (i ^ 0xdead));
	}
	for (uint32_t i = 0; i < 261; i += 2) {
		pool.free(values[i]);
	}
	for (uint32_t i = 1; i < 261; i += 2) {
		CHECK(*values[i] == (i ^ 0xdead));
		pool.free(values[i]);
	}
	values.clear();
	for (uint32_t i = 0; i < 261; i++) {
		values.push_back(pool.alloc(i + 100));
	}
	for (uint32_t i = 0; i < 261; i++) {
		CHECK(*values[i] == i + 100);
		pool.free(values[i]);
	}
	pool.reset();
}

TEST_CASE("[PagedAllocator] Reset and reconfigure clear metadata capacity") {
	PagedAllocator<uint64_t, false, 2> pool(2);
	std::vector<uint64_t *> values;
	for (uint32_t i = 0; i < 70; i++) {
		values.push_back(pool.alloc(uint64_t(i) << 30));
	}
	for (uint32_t i = 0; i < 70; i++) {
		CHECK(*values[i] == (uint64_t(i) << 30));
		pool.free(values[i]);
	}
	values.clear();
	pool.reset();
	pool.configure(8);
	for (uint32_t i = 0; i < 103; i++) {
		values.push_back(pool.alloc(uint64_t(i) + 1100));
	}
	for (uint32_t i = 0; i < 103; i++) {
		CHECK(*values[i] == uint64_t(i) + 1100);
		pool.free(values[i]);
	}
	pool.reset();
}

} // namespace TestPagedAllocator
