/**************************************************************************/
/*  audio_stream_procedural.cpp                                           */
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

#include "audio_stream_procedural.h"

#include "core/object/class_db.h"
#include "scene/resources/audio/audio_stream_wav.h"

/////////////////// Playback ///////////////////

int AudioStreamPlaybackProcedural::_mix_internal(AudioFrame *p_buffer, int p_frames) {
	if (!active || !graph.is_compiled()) {
		for (int i = 0; i < p_frames; i++) {
			p_buffer[i] = AudioFrame(0, 0);
		}
		return 0;
	}

	int to_render = p_frames;
	if (frame_limit > 0) {
		to_render = int(MIN(int64_t(p_frames), frame_limit - frames_mixed));
	}

	float mono[256];
	int done = 0;
	while (done < to_render) {
		const int chunk = MIN(256, to_render - done);
		graph.render(mono, chunk);
		for (int i = 0; i < chunk; i++) {
			p_buffer[done + i] = AudioFrame(mono[i], mono[i]);
		}
		done += chunk;
	}
	for (int i = to_render; i < p_frames; i++) {
		p_buffer[i] = AudioFrame(0, 0);
	}
	frames_mixed += to_render;
	if (frame_limit > 0 && frames_mixed >= frame_limit) {
		active = false;
	}
	return to_render;
}

float AudioStreamPlaybackProcedural::get_stream_sampling_rate() {
	return stream->get_mix_rate();
}

void AudioStreamPlaybackProcedural::start(double p_from_pos) {
	begin_resample();
	graph.reset();
	frames_mixed = 0;
	active = graph.is_compiled();
	if (p_from_pos > 0.0) {
		seek(p_from_pos);
	}
}

void AudioStreamPlaybackProcedural::stop() {
	active = false;
}

bool AudioStreamPlaybackProcedural::is_playing() const {
	return active;
}

int AudioStreamPlaybackProcedural::get_loop_count() const {
	return 0;
}

double AudioStreamPlaybackProcedural::get_playback_position() const {
	return double(frames_mixed) / double(stream->get_mix_rate());
}

void AudioStreamPlaybackProcedural::seek(double p_time) {
	if (!graph.is_compiled()) {
		return;
	}
	// Procedural state is recursive (filters, delays), so seeking means re-rendering from zero.
	graph.reset();
	frames_mixed = 0;
	int64_t target = int64_t(MAX(p_time, 0.0) * double(stream->get_mix_rate()));
	if (frame_limit > 0) {
		target = MIN(target, frame_limit);
	}
	float scratch[256];
	while (frames_mixed < target) {
		const int chunk = int(MIN(int64_t(256), target - frames_mixed));
		graph.render(scratch, chunk);
		frames_mixed += chunk;
	}
	if (frame_limit > 0 && frames_mixed >= frame_limit) {
		active = false;
	}
}

void AudioStreamPlaybackProcedural::tag_used_streams() {
	stream->tag_used(get_playback_position());
}

void AudioStreamPlaybackProcedural::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_graph_valid"), &AudioStreamPlaybackProcedural::is_graph_valid);
}

/////////////////// Stream ///////////////////

void AudioStreamProcedural::set_graph(const Dictionary &p_graph) {
	graph = p_graph.duplicate(true);
	emit_changed();
}

Dictionary AudioStreamProcedural::get_graph() const {
	return graph;
}

void AudioStreamProcedural::set_seed(int64_t p_seed) {
	seed = p_seed;
}

int64_t AudioStreamProcedural::get_seed() const {
	return seed;
}

void AudioStreamProcedural::set_mix_rate(float p_hz) {
	mix_rate = CLAMP(p_hz, 8000.0f, 192000.0f);
}

float AudioStreamProcedural::get_mix_rate() const {
	return mix_rate;
}

void AudioStreamProcedural::set_length(float p_seconds) {
	length = MAX(p_seconds, 0.0f);
}

float AudioStreamProcedural::get_length_seconds() const {
	return length;
}

PackedStringArray AudioStreamProcedural::validate() const {
	return PackedStringArray(CgameAudioGraph::validate(graph));
}

bool AudioStreamProcedural::is_valid() const {
	return CgameAudioGraph::validate(graph).is_empty();
}

PackedFloat32Array AudioStreamProcedural::render(float p_seconds, float p_sample_rate) const {
	PackedFloat32Array out;
	const double rate = p_sample_rate > 0.0f ? double(p_sample_rate) : double(mix_rate);
	if (p_seconds <= 0.0f) {
		return out;
	}
	CgameAudioGraph runtime;
	Vector<String> errors;
	if (!runtime.compile(graph, rate, seed, &errors)) {
		for (const String &e : errors) {
			WARN_PRINT("AudioStreamProcedural: " + e);
		}
		return out;
	}
	const int frames = int(Math::ceil(double(p_seconds) * rate));
	out.resize(frames);
	runtime.render(out.ptrw(), frames);
	return out;
}

Ref<AudioStreamWAV> AudioStreamProcedural::bake_to_wav(float p_seconds) const {
	const PackedFloat32Array samples = render(p_seconds);
	Ref<AudioStreamWAV> wav;
	wav.instantiate();
	wav->set_format(AudioStreamWAV::FORMAT_16_BITS);
	wav->set_mix_rate(int(mix_rate));
	wav->set_stereo(false);
	Vector<uint8_t> bytes;
	bytes.resize(samples.size() * 2);
	uint8_t *w = bytes.ptrw();
	for (int i = 0; i < samples.size(); i++) {
		const int16_t v = int16_t(CLAMP(samples[i], -1.0f, 1.0f) * 32767.0f);
		w[i * 2] = uint8_t(uint16_t(v) & 0xFF);
		w[i * 2 + 1] = uint8_t((uint16_t(v) >> 8) & 0xFF);
	}
	wav->set_data(bytes);
	return wav;
}

Ref<AudioStreamPlayback> AudioStreamProcedural::instantiate_playback() {
	Ref<AudioStreamPlaybackProcedural> playback;
	playback.instantiate();
	playback->stream = Ref<AudioStreamProcedural>(this);
	Vector<String> errors;
	if (!playback->graph.compile(graph, double(mix_rate), seed, &errors)) {
		for (const String &e : errors) {
			WARN_PRINT("AudioStreamProcedural: " + e);
		}
	}
	playback->frame_limit = length > 0.0f ? int64_t(Math::ceil(double(length) * double(mix_rate))) : 0;
	return playback;
}

double AudioStreamProcedural::get_length() const {
	return length;
}

bool AudioStreamProcedural::is_monophonic() const {
	return false;
}

bool AudioStreamProcedural::has_loop() const {
	return false;
}

void AudioStreamProcedural::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_graph", "graph"), &AudioStreamProcedural::set_graph);
	ClassDB::bind_method(D_METHOD("get_graph"), &AudioStreamProcedural::get_graph);
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &AudioStreamProcedural::set_seed);
	ClassDB::bind_method(D_METHOD("get_seed"), &AudioStreamProcedural::get_seed);
	ClassDB::bind_method(D_METHOD("set_mix_rate", "hz"), &AudioStreamProcedural::set_mix_rate);
	ClassDB::bind_method(D_METHOD("get_mix_rate"), &AudioStreamProcedural::get_mix_rate);
	ClassDB::bind_method(D_METHOD("set_length", "seconds"), &AudioStreamProcedural::set_length);
	ClassDB::bind_method(D_METHOD("get_length_seconds"), &AudioStreamProcedural::get_length_seconds);
	ClassDB::bind_method(D_METHOD("validate"), &AudioStreamProcedural::validate);
	ClassDB::bind_method(D_METHOD("is_valid"), &AudioStreamProcedural::is_valid);
	ClassDB::bind_method(D_METHOD("render", "seconds", "sample_rate"), &AudioStreamProcedural::render, DEFVAL(0.0f));
	ClassDB::bind_method(D_METHOD("bake_to_wav", "seconds"), &AudioStreamProcedural::bake_to_wav);

	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "graph"), "set_graph", "get_graph");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mix_rate", PROPERTY_HINT_RANGE, "8000,192000,1,suffix:Hz"), "set_mix_rate", "get_mix_rate");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "length", PROPERTY_HINT_RANGE, "0,600,0.01,or_greater,suffix:s"), "set_length", "get_length_seconds");
}
