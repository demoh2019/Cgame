/**************************************************************************/
/*  audio_stream_procedural.h                                             */
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

// AudioStreamProcedural plays a node-based audio graph (see cgame_audio_graph.h for the
// dictionary format and the algorithm references) by evaluating it block by block in the
// audio thread, so procedural sounds need no baking step.

#include "cgame_audio_graph.h"

#include "scene/resources/audio/audio_stream.h"
#include "scene/resources/audio/audio_stream_wav.h"

class AudioStreamProcedural;

class AudioStreamPlaybackProcedural : public AudioStreamPlaybackResampled {
	GDCLASS(AudioStreamPlaybackProcedural, AudioStreamPlaybackResampled);

	friend class AudioStreamProcedural;

	Ref<AudioStreamProcedural> stream;
	CgameAudioGraph graph;
	bool active = false;
	int64_t frames_mixed = 0;
	int64_t frame_limit = 0; // 0 = endless.

protected:
	virtual int _mix_internal(AudioFrame *p_buffer, int p_frames) override;
	virtual float get_stream_sampling_rate() override;

	static void _bind_methods();

public:
	virtual void start(double p_from_pos = 0.0) override;
	virtual void stop() override;
	virtual bool is_playing() const override;

	virtual int get_loop_count() const override;
	virtual double get_playback_position() const override;
	virtual void seek(double p_time) override;

	virtual void tag_used_streams() override;

	bool is_graph_valid() const { return graph.is_compiled(); }
};

class AudioStreamProcedural : public AudioStream {
	GDCLASS(AudioStreamProcedural, AudioStream);

	Dictionary graph;
	int64_t seed = 0;
	float mix_rate = 44100.0f;
	float length = 0.0f;

protected:
	static void _bind_methods();

public:
	void set_graph(const Dictionary &p_graph);
	Dictionary get_graph() const;
	void set_seed(int64_t p_seed);
	int64_t get_seed() const;
	void set_mix_rate(float p_hz);
	float get_mix_rate() const;
	void set_length(float p_seconds);
	float get_length_seconds() const;

	// Problems with the current graph; empty means it can be played.
	PackedStringArray validate() const;
	bool is_valid() const;
	// Offline render of p_seconds of mono audio at mix_rate (0 = use the stream rate).
	PackedFloat32Array render(float p_seconds, float p_sample_rate = 0.0f) const;
	// Offline render wrapped into a 16-bit mono AudioStreamWAV.
	Ref<AudioStreamWAV> bake_to_wav(float p_seconds) const;

	virtual Ref<AudioStreamPlayback> instantiate_playback() override;
	virtual double get_length() const override;
	virtual bool is_monophonic() const override;
	virtual bool has_loop() const override;

	AudioStreamProcedural() {}
};
