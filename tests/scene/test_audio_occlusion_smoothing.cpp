/**************************************************************************/
/*  test_audio_occlusion_smoothing.cpp                                    */
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

TEST_FORCE_LINK(test_audio_occlusion_smoothing)

#ifndef _3D_DISABLED

#include "scene/3d/audio_stream_player_3d.h"
#include "servers/audio/audio_server.h"

#include <limits>

namespace TestAudioOcclusionSmoothing {

TEST_CASE("[SceneTree][AudioStreamPlayer3D] Obstruction attack and release are time consistent") {
	if (AudioServer::get_singleton() == nullptr) {
		// AudioStreamPlayer3D connects to AudioServer signals in its constructor.
		MESSAGE("Skipped: no AudioServer in this test harness.");
		return;
	}
	AudioStreamPlayer3D *source = memnew(AudioStreamPlayer3D);
	CHECK(source->get_obstruction_amount() == 0.0f);

	// The first full attack time constant moves about 63% toward blockage.
	const float attack = source->advance_obstruction_amount(1.0f, 0.08f);
	CHECK(attack > 0.63f);
	CHECK(attack < 0.64f);
	CHECK(source->get_obstruction_amount() == attack);
	const float no_time = source->advance_obstruction_amount(1.0f, 0.0f);
	CHECK(no_time == attack);

	// The release time constant is longer: the opening sounds fade back
	// instead of abruptly snapping their high frequencies to full volume.
	source->set_obstruction_amount(1.0f);
	const float release = source->advance_obstruction_amount(0.0f, 0.08f);
	CHECK(release > 0.69f);
	CHECK(release < 0.70f);

	// Repeated physics steps and one larger step give near-identical results.
	source->set_obstruction_amount(0.0f);
	for (int i = 0; i < 12; i++) {
		source->advance_obstruction_amount(1.0f, 1.0f / 60.0f);
	}
	const float sliced = source->get_obstruction_amount();
	source->set_obstruction_amount(0.0f);
	const float whole = source->advance_obstruction_amount(1.0f, 0.2f);
	CHECK(Math::abs(sliced - whole) < 0.002f);

	source->set_obstruction_amount(0.0f);
	CHECK(source->advance_obstruction_amount(2.0f, 0.12f) <= 1.0f);
	source->set_obstruction_amount(1.0f);
	CHECK(source->advance_obstruction_amount(-5.0f, 0.12f) >= 0.0f);

	// Invalid inputs must never poison the real-time audio mixer.
	const float before = source->get_obstruction_amount();
	CHECK(source->advance_obstruction_amount(std::numeric_limits<float>::quiet_NaN(), 0.1f) == before);
	CHECK(source->advance_obstruction_amount(0.0f, -0.1f) == before);
	CHECK(source->advance_obstruction_amount(0.0f, 0.1f, 0.0f) == before);
	CHECK(source->advance_obstruction_amount(0.0f, 0.1f, 0.08f, -0.2f) == before);

	source->set_obstruction_amount(0.0f);
	source->advance_obstruction_amount(1.0f, 10.0f);
	CHECK(source->get_obstruction_amount() == 1.0f);
	memdelete(source);
}

} // namespace TestAudioOcclusionSmoothing

#endif // _3D_DISABLED
