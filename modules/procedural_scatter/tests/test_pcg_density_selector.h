/**************************************************************************/
/*  test_pcg_density_selector.h                                           */
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

#include "../pcg_density_selector.h"

#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGDensitySelector {

TEST_CASE("[PCGDensitySelector] linear remap and clamping") {
	Ref<PCGDensitySelector> selector;
	selector.instantiate();
	const PackedFloat32Array inputs = { 0.0f, 0.25f, 0.5f, 0.75f, 1.0f };
	const PackedFloat32Array original = inputs;
	const PackedFloat32Array out = selector->remap_densities(inputs, 0.0, 1.0, 0.2, 0.8);
	REQUIRE(out.size() == 5);
	for (int i = 0; i < 5; ++i) {
		CHECK(Math::is_equal_approx(out[i], float(0.2 + double(i) * 0.15)));
	}
	CHECK(inputs == original);
	const PackedFloat32Array inverse = selector->remap_densities(inputs, 0.0, 1.0, 1.0, 0.0);
	REQUIRE(inverse.size() == 5);
	CHECK(inverse[0] == 1.0f);
	CHECK(inverse[4] == 0.0f);

	const PackedFloat32Array clamped = selector->remap_densities(inputs, 0.25, 0.75, 0.4, 0.6, true);
	const PackedFloat32Array extrapolated = selector->remap_densities(inputs, 0.25, 0.75, 0.4, 0.6, false);
	REQUIRE(clamped.size() == 5);
	REQUIRE(extrapolated.size() == 5);
	CHECK(Math::is_equal_approx(clamped[0], 0.4f));
	CHECK(Math::is_equal_approx(extrapolated[0], 0.3f));
	CHECK(Math::is_equal_approx(clamped[4], 0.6f));
	CHECK(Math::is_equal_approx(extrapolated[4], 0.7f));
}

TEST_CASE("[PCGDensitySelector] stable IDs and seed yield independent per-point decisions") {
	Ref<PCGDensitySelector> selector;
	selector.instantiate();
	const PackedFloat32Array densities = { 0.0f, 1.0f, 0.5f, 0.5f, 0.5f, 0.5f };
	const PackedInt64Array ids = { 1, 2, 3, 4, 5, 6 };
	const PackedInt32Array out = selector->select_indices(densities, ids, 7123);
	CHECK(out.size() >= 1);
	CHECK(out[0] == 1); // Zero density excluded, one always accepted.
	CHECK(selector->select_indices(densities, ids, 7123) == out);
	const PackedFloat32Array shuffled_densities = { 0.5f, 0.5f, 1.0f, 0.0f, 0.5f, 0.5f };
	const PackedInt64Array shuffled_ids = { 6, 4, 2, 1, 3, 5 };
	const PackedInt32Array shuffled = selector->select_indices(shuffled_densities, shuffled_ids, 7123);
	for (int i = 0; i < ids.size(); ++i) {
		bool a = false;
		bool b = false;
		for (int j = 0; j < out.size(); ++j) {
			a |= ids[out[j]] == ids[i];
		}
		for (int j = 0; j < shuffled.size(); ++j) {
			b |= shuffled_ids[shuffled[j]] == ids[i];
		}
		CHECK(a == b);
	}
	const PackedFloat32Array ones = { 1.0f, 1.0f, 1.0f, 1.0f };
	const PackedInt64Array more_ids = { 6, 3, 17, 102 };
	const PackedInt32Array capped = selector->select_indices(ones, more_ids, 7, 2);
	REQUIRE(capped.size() == 2);
	CHECK(capped[0] == 0);
	CHECK(capped[1] == 1);
	CHECK(selector->select_indices(ones, more_ids, 7, 4).size() == 4);
}

TEST_CASE("[PCGDensitySelector] reject invalid inputs atomically") {
	Ref<PCGDensitySelector> selector;
	selector.instantiate();
	const PackedFloat32Array values = { 0.3f, 0.75f };
	const PackedInt64Array ids = { 7, 10 };
	CHECK(selector->select_indices(values, { 7 }, 1).is_empty());
	CHECK(selector->select_indices(values, ids, -1).is_empty());
	CHECK(selector->select_indices(values, ids, 1, 0).is_empty());
	CHECK(selector->select_indices(values, ids, 1, 4097).is_empty());
	CHECK(selector->select_indices(values, { 7, -1 }, 0).is_empty());
	CHECK(selector->select_indices(values, { 7, 2147483648ll }, 0).is_empty());
	CHECK(selector->select_indices({ 0.3f, Math::NaN }, ids).is_empty());
	CHECK(selector->select_indices({ 0.3f, 1.1f }, ids).is_empty());
	CHECK(selector->remap_densities({ 0.3f, float(Math::INF) }).is_empty());
	CHECK(selector->remap_densities(values, 0.5, 0.5).is_empty());
	CHECK(selector->remap_densities(values, 0.8, 0.2).is_empty());
	CHECK(selector->remap_densities(values, 0, 1, 0, Math::NaN).is_empty());
	CHECK(selector->remap_densities(values, 0, 1, -0.1, 1).is_empty());
	PackedFloat32Array huge;
	PackedInt64Array huge_ids;
	huge.resize(16385);
	huge_ids.resize(16385);
	CHECK(selector->select_indices(huge, huge_ids).is_empty());
	CHECK(selector->remap_densities(huge).is_empty());
}

} // namespace TestPCGDensitySelector
