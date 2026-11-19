/**************************************************************************/
/*  test_audio_stream_interactive.cpp                                     */
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

TEST_FORCE_LINK(test_audio_stream_interactive)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_INTERACTIVE_MUSIC_ENABLED

#include "modules/interactive_music/audio_stream_interactive.h"

namespace TestAudioStreamInteractive {

static void add_transition(const Ref<AudioStreamInteractive> &p_stream, int p_from, int p_to, float p_fade_beats = 1.0f) {
	p_stream->add_transition(p_from, p_to,
			AudioStreamInteractive::TRANSITION_FROM_TIME_NEXT_BEAT,
			AudioStreamInteractive::TRANSITION_TO_TIME_START,
			AudioStreamInteractive::FADE_AUTOMATIC,
			p_fade_beats);
}

static Dictionary serialized_transitions(const Ref<AudioStreamInteractive> &p_stream) {
	return p_stream->get("_transitions");
}

TEST_CASE("[AudioStreamInteractive] Serialize transitions after removing clips") {
	Ref<AudioStreamInteractive> stream;
	stream.instantiate();
	stream->set_clip_count(4);
	add_transition(stream, 0, 1);
	add_transition(stream, 2, 3);
	add_transition(stream, 3, 0);
	add_transition(stream, 0, 3);
	add_transition(stream, 1, 1);

	Dictionary before = serialized_transitions(stream);
	CHECK(before.size() == 5);
	CHECK(before.has(Vector2i(2, 3)));
	CHECK(before.has(Vector2i(3, 0)));
	CHECK(before.has(Vector2i(0, 3)));

	stream->set_clip_count(2);
	Dictionary after = serialized_transitions(stream);
	CHECK(after.size() == 2);
	CHECK(after.has(Vector2i(0, 1)));
	CHECK(after.has(Vector2i(1, 1)));
	CHECK_FALSE(after.has(Vector2i(2, 3)));
	CHECK_FALSE(after.has(Vector2i(3, 0)));
	CHECK_FALSE(after.has(Vector2i(0, 3)));
}

TEST_CASE("[AudioStreamInteractive] Preserve removed transitions in memory for undo") {
	Ref<AudioStreamInteractive> stream;
	stream.instantiate();
	stream->set_clip_count(3);
	add_transition(stream, 0, 2, 3.25f);
	add_transition(stream, 1, 1);

	stream->set_clip_count(2);
	CHECK_FALSE(serialized_transitions(stream).has(Vector2i(0, 2)));
	CHECK(stream->has_transition(0, 2));
	CHECK(stream->get_transition_fade_beats(0, 2) == doctest::Approx(3.25f));
	CHECK(stream->get_transition_list().size() == 4);

	stream->set_clip_count(3);
	Dictionary restored = serialized_transitions(stream);
	CHECK(restored.size() == 2);
	CHECK(restored.has(Vector2i(0, 2)));
	CHECK(restored.has(Vector2i(1, 1)));
	Dictionary restored_data = restored[Vector2i(0, 2)];
	CHECK(float(restored_data["fade_beats"]) == doctest::Approx(3.25f));
}

TEST_CASE("[AudioStreamInteractive] Keep wildcard transitions on clip shrink") {
	Ref<AudioStreamInteractive> stream;
	stream.instantiate();
	stream->set_clip_count(3);
	const int any = AudioStreamInteractive::CLIP_ANY;

	add_transition(stream, any, 0);
	add_transition(stream, 1, any);
	add_transition(stream, any, any);
	add_transition(stream, any, 2);
	add_transition(stream, 2, any);
	add_transition(stream, 2, 1);

	stream->set_clip_count(2);
	Dictionary transitions = serialized_transitions(stream);
	CHECK(transitions.size() == 3);
	CHECK(transitions.has(Vector2i(any, 0)));
	CHECK(transitions.has(Vector2i(1, any)));
	CHECK(transitions.has(Vector2i(any, any)));
	CHECK_FALSE(transitions.has(Vector2i(any, 2)));
	CHECK_FALSE(transitions.has(Vector2i(2, any)));
	CHECK_FALSE(transitions.has(Vector2i(2, 1)));

	stream->set_clip_count(0);
	transitions = serialized_transitions(stream);
	CHECK(transitions.size() == 1);
	CHECK(transitions.has(Vector2i(any, any)));
}

TEST_CASE("[AudioStreamInteractive] Reject transitions whose clip index equals the count") {
	Ref<AudioStreamInteractive> stream;
	stream.instantiate();
	stream->set_clip_count(3);
	add_transition(stream, 2, 2);
	add_transition(stream, 0, 1);
	stream->set_clip_count(2);
	CHECK_FALSE(serialized_transitions(stream).has(Vector2i(2, 2)));
	CHECK(serialized_transitions(stream).has(Vector2i(0, 1)));
	stream->set_clip_count(3);
	CHECK(serialized_transitions(stream).has(Vector2i(2, 2)));
}

TEST_CASE("[AudioStreamInteractive] Serialized transitions can be loaded after shrinking") {
	Ref<AudioStreamInteractive> stream;
	stream.instantiate();
	stream->set_clip_count(3);
	add_transition(stream, 0, 1);
	add_transition(stream, 2, 1);
	stream->set_clip_count(2);
	Dictionary serialized = serialized_transitions(stream);
	REQUIRE(serialized.size() == 1);

	Ref<AudioStreamInteractive> reloaded;
	reloaded.instantiate();
	reloaded->set_clip_count(2);
	CHECK(reloaded->set("_transitions", serialized));
	CHECK(reloaded->has_transition(0, 1));
	CHECK_FALSE(reloaded->has_transition(2, 1));
	CHECK(serialized_transitions(reloaded).size() == 1);
}

} // namespace TestAudioStreamInteractive

#endif // MODULE_INTERACTIVE_MUSIC_ENABLED
