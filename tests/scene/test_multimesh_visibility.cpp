/**************************************************************************/
/*  test_multimesh_visibility.cpp                                         */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_multimesh_visibility)

#include "core/math/random_number_generator.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/multimesh.h"

namespace TestMultiMeshVisibility {

// The renderer's low-level regression additionally needs an RD-backed GPU
// capture: this test exercises the public API with the mock rendering server.
TEST_CASE("[SceneTree][MultiMesh] Seeded native buffer shuffle preserves full instance records") {
	// A foliage tile uploads one packed buffer, then reveals a randomized prefix
	// for screen-space density LOD. Swapping channels instead of full records
	// would mix colors and transforms and produce visible artifacts.
	Ref<MultiMesh> batch;
	batch.instantiate();
	batch->set_transform_format(MultiMesh::TRANSFORM_3D);
	batch->set_use_colors(true);
	batch->set_instance_count(64);
	Vector<float> source;
	source.resize(64 * 16);
	{
		float *w = source.ptrw();
		for (int i = 0; i < source.size(); ++i) {
			w[i] = float(i * 0.25);
		}
	}
	const Vector<float> preserved = source;
	const uint64_t seed = 2026;
	const Vector<float> native = batch->shuffled_instance_buffer(source, seed);
	CHECK(native == batch->shuffled_instance_buffer(source, seed));
	CHECK(source == preserved);
	CHECK(native.size() == source.size());
	CHECK(native != source);

	Ref<RandomNumberGenerator> random;
	random.instantiate();
	random->set_seed(seed);
	Vector<float> expected = source;
	float *w = expected.ptrw();
	for (int i = 63; i > 0; --i) {
		const int other = random->randi_range(0, i);
		const int a = i * 16;
		const int b = other * 16;
		for (int channel = 0; channel < 16; ++channel) {
			const float tmp = w[a + channel];
			w[a + channel] = w[b + channel];
			w[b + channel] = tmp;
		}
	}
	CHECK(native == expected);

	// No accidental edits when input does not match the declared GPU layout.
	Vector<float> short_input;
	short_input.resize(17);
	CHECK(batch->shuffled_instance_buffer(short_input, seed) == short_input);
	// Every packed layout is supported, not just Albion After grass.
	batch->set_instance_count(0);
	batch->set_use_custom_data(true);
	batch->set_instance_count(4);
	Vector<float> extended;
	extended.resize(4 * 20);
	{
		float *ew = extended.ptrw();
		for (int i = 0; i < extended.size(); ++i) {
			ew[i] = float(i);
		}
	}
	const Vector<float> shuffled_extended = batch->shuffled_instance_buffer(extended, 123);
	CHECK(shuffled_extended.size() == extended.size());
	// Each of the four 20-float records must remain intact.
	for (int i = 0; i < 4; ++i) {
		const int original = int(shuffled_extended[i * 20]) / 20;
		CHECK(original >= 0);
		CHECK(original < 4);
		for (int j = 0; j < 20; ++j) {
			CHECK(shuffled_extended[i * 20 + j] == extended[original * 20 + j]);
		}
	}
}

TEST_CASE("[SceneTree][MultiMesh] Reveal hidden instances with -1") {
	Ref<MultiMesh> batch;
	batch.instantiate();
	batch->set_transform_format(MultiMesh::TRANSFORM_3D);
	batch->set_use_custom_data(true);
	batch->set_instance_count(4);
	batch->set_visible_instance_count(1);

	const Transform3D formerly_hidden(Basis(), Vector3(8, 3, -7));
	const Color glow(0.2, 0.5, 0.9, 1.0);
	batch->set_instance_transform(3, formerly_hidden);
	batch->set_instance_custom_data(3, glow);
	CHECK(batch->get_visible_instance_count() == 1);

	batch->set_visible_instance_count(-1);
	CHECK(batch->get_visible_instance_count() == -1);
	CHECK(batch->get_instance_transform(3).is_equal_approx(formerly_hidden));
	CHECK(batch->get_instance_custom_data(3).is_equal_approx(glow));

	batch->set_visible_instance_count(0);
	CHECK(batch->get_visible_instance_count() == 0);
	const Transform3D hidden_again(Basis(), Vector3(-2, 5, 4));
	batch->set_instance_transform(2, hidden_again);
	batch->set_visible_instance_count(-1);
	CHECK(batch->get_visible_instance_count() == -1);
	CHECK(batch->get_instance_transform(2).is_equal_approx(hidden_again));
}

TEST_CASE("[SceneTree][MultiMesh] Explicit capacity remains unchanged after culling") {
	Ref<MultiMesh> batch;
	batch.instantiate();
	batch->set_transform_format(MultiMesh::TRANSFORM_3D);
	batch->set_instance_count(12);
	batch->set_visible_instance_count(3);
	batch->set_visible_instance_count(-1);
	CHECK(batch->get_instance_count() == 12);
	CHECK(batch->get_visible_instance_count() == -1);
	batch->set_visible_instance_count(7);
	CHECK(batch->get_instance_count() == 12);
	CHECK(batch->get_visible_instance_count() == 7);
}

} // namespace TestMultiMeshVisibility
