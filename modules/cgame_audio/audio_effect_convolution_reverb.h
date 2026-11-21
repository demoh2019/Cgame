/**************************************************************************/
/*  audio_effect_convolution_reverb.h                                     */
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

// Real-time convolution reverb built on uniformly partitioned FFT convolution
// (see cgame_convolution.h for the algorithm references).
//
// Threading model: all properties are set from the main thread. Setting the impulse
// response builds an immutable CgameConvolutionKernel plus one pre-allocated
// CgameConvolutionEngine per live effect instance on the calling thread, and publishes the
// engine with an atomic pointer exchange. The audio thread swaps engines without locks or
// allocations and hands the old engine back through a single-producer/single-consumer ring
// so it is freed on the main thread.

#include "cgame_convolution.h"

#include "core/os/mutex.h"
#include "scene/resources/audio/audio_stream_wav.h"
#include "servers/audio/audio_effect.h"

#include <atomic>

class AudioEffectConvolutionReverb;

class AudioEffectConvolutionReverbInstance : public AudioEffectInstance {
	GDCLASS(AudioEffectConvolutionReverbInstance, AudioEffectInstance);

	friend class AudioEffectConvolutionReverb;

	static constexpr int RETIRED_RING_SIZE = 8;

	Ref<AudioEffectConvolutionReverb> base;

	// Audio-thread owned.
	CgameConvolutionEngine *active = nullptr;

	// Lock-free mailbox: main thread writes, audio thread takes.
	std::atomic<CgameConvolutionEngine *> pending{ nullptr };

	// SPSC ring of engines the audio thread no longer uses (consumer: main thread).
	std::atomic<CgameConvolutionEngine *> retired[RETIRED_RING_SIZE];
	std::atomic<uint32_t> retired_head{ 0 }; // Written by the audio thread.
	std::atomic<uint32_t> retired_tail{ 0 }; // Written by the main thread.

	// Main thread: replaces the pending engine (taking ownership) and frees retired ones.
	void publish(CgameConvolutionEngine *p_engine);
	void collect_retired();
	bool retire(CgameConvolutionEngine *p_engine);

public:
	virtual void process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count) override;
	virtual bool process_silence() const override;

	AudioEffectConvolutionReverbInstance();
	~AudioEffectConvolutionReverbInstance();
};

class AudioEffectConvolutionReverb : public AudioEffect {
	GDCLASS(AudioEffectConvolutionReverb, AudioEffect);

	friend class AudioEffectConvolutionReverbInstance;

	PackedFloat32Array impulse;
	PackedFloat32Array impulse_right;
	Ref<AudioStreamWAV> impulse_stream;
	float impulse_sample_rate = 0.0f;
	int block_size = 256;
	float dry = 1.0f;
	float wet = 0.5f;
	float impulse_gain_db = 0.0f;

	Ref<CgameConvolutionKernel> kernel;
	Mutex registry_mutex;
	Vector<AudioEffectConvolutionReverbInstance *> instances;

	void _rebuild_kernel();
	void _publish_kernel(AudioEffectConvolutionReverbInstance *p_instance);
	static Vector<float> _resample(const float *p_src, int p_len, double p_from_rate, double p_to_rate, float p_gain);

protected:
	static void _bind_methods();

public:
	void set_impulse(const PackedFloat32Array &p_impulse);
	PackedFloat32Array get_impulse() const;
	void set_impulse_right(const PackedFloat32Array &p_impulse);
	PackedFloat32Array get_impulse_right() const;
	void set_impulse_stream(const Ref<AudioStreamWAV> &p_stream);
	Ref<AudioStreamWAV> get_impulse_stream() const;
	void set_impulse_sample_rate(float p_rate);
	float get_impulse_sample_rate() const;
	void set_block_size(int p_block_size);
	int get_block_size() const;
	void set_dry(float p_dry);
	float get_dry() const;
	void set_wet(float p_wet);
	float get_wet() const;
	void set_impulse_gain_db(float p_db);
	float get_impulse_gain_db() const;

	int get_latency_frames() const;
	int get_partition_count() const;

	// Decodes 8/16-bit PCM WAV data into per-channel float arrays (static for tests).
	static bool decode_wav(const Ref<AudioStreamWAV> &p_stream, PackedFloat32Array &r_left, PackedFloat32Array &r_right);

	virtual Ref<AudioEffectInstance> instantiate() override;

	AudioEffectConvolutionReverb();
	~AudioEffectConvolutionReverb();
};
