/**************************************************************************/
/*  audio_effect_convolution_reverb.cpp                                   */
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

#include "audio_effect_convolution_reverb.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "servers/audio/audio_server.h"

/////////////////// Instance ///////////////////

AudioEffectConvolutionReverbInstance::AudioEffectConvolutionReverbInstance() {
	for (int i = 0; i < RETIRED_RING_SIZE; i++) {
		retired[i].store(nullptr, std::memory_order_relaxed);
	}
}

AudioEffectConvolutionReverbInstance::~AudioEffectConvolutionReverbInstance() {
	if (base.is_valid()) {
		MutexLock lock(base->registry_mutex);
		base->instances.erase(this);
	}
	memdelete(pending.exchange(nullptr, std::memory_order_acq_rel));
	collect_retired();
	memdelete(active);
	active = nullptr;
}

void AudioEffectConvolutionReverbInstance::publish(CgameConvolutionEngine *p_engine) {
	collect_retired();
	CgameConvolutionEngine *old = pending.exchange(p_engine, std::memory_order_acq_rel);
	// Anything handed back by the exchange was never seen by the audio thread.
	memdelete(old);
}

void AudioEffectConvolutionReverbInstance::collect_retired() {
	for (;;) {
		const uint32_t tail = retired_tail.load(std::memory_order_relaxed);
		if (tail == retired_head.load(std::memory_order_acquire)) {
			return;
		}
		CgameConvolutionEngine *e = retired[tail % RETIRED_RING_SIZE].load(std::memory_order_relaxed);
		retired_tail.store(tail + 1, std::memory_order_release);
		memdelete(e);
	}
}

bool AudioEffectConvolutionReverbInstance::retire(CgameConvolutionEngine *p_engine) {
	const uint32_t head = retired_head.load(std::memory_order_relaxed);
	if (head - retired_tail.load(std::memory_order_acquire) >= uint32_t(RETIRED_RING_SIZE)) {
		return false;
	}
	retired[head % RETIRED_RING_SIZE].store(p_engine, std::memory_order_relaxed);
	retired_head.store(head + 1, std::memory_order_release);
	return true;
}

void AudioEffectConvolutionReverbInstance::process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count) {
	// Pick up a freshly published engine, but only if the old one can be retired lock-free.
	if (pending.load(std::memory_order_relaxed) != nullptr) {
		const uint32_t head = retired_head.load(std::memory_order_relaxed);
		const bool has_room = active == nullptr || head - retired_tail.load(std::memory_order_acquire) < uint32_t(RETIRED_RING_SIZE);
		if (has_room) {
			CgameConvolutionEngine *fresh = pending.exchange(nullptr, std::memory_order_acq_rel);
			if (fresh != nullptr) {
				if (active != nullptr) {
					retire(active);
				}
				active = fresh;
			}
		}
	}

	const float dry = base->dry;
	const float wet = base->wet;

	if (active == nullptr) {
		for (int i = 0; i < p_frame_count; i++) {
			p_dst_frames[i] = p_src_frames[i] * dry;
		}
		return;
	}

	AudioFrame tmp[256];
	int offset = 0;
	while (offset < p_frame_count) {
		const int chunk = MIN(256, p_frame_count - offset);
		active->process(p_src_frames + offset, tmp, chunk);
		for (int i = 0; i < chunk; i++) {
			p_dst_frames[offset + i] = p_src_frames[offset + i] * dry + tmp[i] * wet;
		}
		offset += chunk;
	}
}

bool AudioEffectConvolutionReverbInstance::process_silence() const {
	// Keep processing silence while the reverb tail of earlier input can still ring out.
	return active != nullptr && active->is_tail_active();
}

/////////////////// Effect ///////////////////

Vector<float> AudioEffectConvolutionReverb::_resample(const float *p_src, int p_len, double p_from_rate, double p_to_rate, float p_gain) {
	Vector<float> out;
	if (p_len <= 0) {
		return out;
	}
	if (p_from_rate <= 0.0 || p_to_rate <= 0.0 || Math::is_equal_approx(p_from_rate, p_to_rate)) {
		out.resize(p_len);
		float *w = out.ptrw();
		for (int i = 0; i < p_len; i++) {
			w[i] = p_src[i] * p_gain;
		}
		return out;
	}
	const double ratio = p_from_rate / p_to_rate;
	const int count = MAX(int(Math::ceil(double(p_len) / ratio)), 1);
	out.resize(count);
	float *w = out.ptrw();
	for (int i = 0; i < count; i++) {
		const double pos = double(i) * ratio;
		const int i0 = MIN(int(pos), p_len - 1);
		const int i1 = MIN(i0 + 1, p_len - 1);
		const float f = float(pos - double(i0));
		w[i] = (p_src[i0] + (p_src[i1] - p_src[i0]) * f) * p_gain;
	}
	return out;
}

void AudioEffectConvolutionReverb::_rebuild_kernel() {
	kernel.unref();
	if (!impulse.is_empty()) {
		double target_rate = impulse_sample_rate;
		if (AudioServer::get_singleton() != nullptr && impulse_sample_rate > 0.0f) {
			target_rate = AudioServer::get_singleton()->get_mix_rate();
		}
		const float gain = Math::db_to_linear(impulse_gain_db);
		Vector<float> left = _resample(impulse.ptr(), impulse.size(), impulse_sample_rate, target_rate, gain);
		Vector<float> right;
		if (!impulse_right.is_empty()) {
			right = _resample(impulse_right.ptr(), impulse_right.size(), impulse_sample_rate, target_rate, gain);
		}
		Ref<CgameConvolutionKernel> k;
		k.instantiate();
		if (k->build(left.ptr(), left.size(), right.is_empty() ? nullptr : right.ptr(), right.size(), block_size)) {
			kernel = k;
		}
	}
	MutexLock lock(registry_mutex);
	for (AudioEffectConvolutionReverbInstance *inst : instances) {
		_publish_kernel(inst);
	}
}

void AudioEffectConvolutionReverb::_publish_kernel(AudioEffectConvolutionReverbInstance *p_instance) {
	CgameConvolutionEngine *engine = memnew(CgameConvolutionEngine);
	engine->setup(kernel);
	p_instance->publish(engine);
}

bool AudioEffectConvolutionReverb::decode_wav(const Ref<AudioStreamWAV> &p_stream, PackedFloat32Array &r_left, PackedFloat32Array &r_right) {
	r_left.clear();
	r_right.clear();
	ERR_FAIL_COND_V(p_stream.is_null(), false);
	const AudioStreamWAV::Format format = p_stream->get_format();
	ERR_FAIL_COND_V_MSG(format != AudioStreamWAV::FORMAT_8_BITS && format != AudioStreamWAV::FORMAT_16_BITS, false, "AudioEffectConvolutionReverb: only 8-bit and 16-bit PCM WAV impulses are supported.");
	const Vector<uint8_t> data = p_stream->get_data();
	const bool stereo = p_stream->is_stereo();
	const int bytes = format == AudioStreamWAV::FORMAT_8_BITS ? 1 : 2;
	const int frames = data.size() / (bytes * (stereo ? 2 : 1));
	ERR_FAIL_COND_V(frames <= 0, false);
	r_left.resize(frames);
	if (stereo) {
		r_right.resize(frames);
	}
	const uint8_t *src = data.ptr();
	for (int i = 0; i < frames; i++) {
		for (int c = 0; c < (stereo ? 2 : 1); c++) {
			const int idx = (i * (stereo ? 2 : 1) + c) * bytes;
			float v;
			if (bytes == 1) {
				v = float(int8_t(src[idx])) / 128.0f;
			} else {
				v = float(int16_t(uint16_t(src[idx]) | (uint16_t(src[idx + 1]) << 8))) / 32768.0f;
			}
			if (c == 0) {
				r_left.write[i] = v;
			} else {
				r_right.write[i] = v;
			}
		}
	}
	return true;
}

Ref<AudioEffectInstance> AudioEffectConvolutionReverb::instantiate() {
	Ref<AudioEffectConvolutionReverbInstance> ins;
	ins.instantiate();
	ins->base = Ref<AudioEffectConvolutionReverb>(this);
	{
		MutexLock lock(registry_mutex);
		instances.push_back(ins.ptr());
		_publish_kernel(ins.ptr());
	}
	return ins;
}

void AudioEffectConvolutionReverb::set_impulse(const PackedFloat32Array &p_impulse) {
	impulse = p_impulse;
	_rebuild_kernel();
}

PackedFloat32Array AudioEffectConvolutionReverb::get_impulse() const {
	return impulse;
}

void AudioEffectConvolutionReverb::set_impulse_right(const PackedFloat32Array &p_impulse) {
	impulse_right = p_impulse;
	_rebuild_kernel();
}

PackedFloat32Array AudioEffectConvolutionReverb::get_impulse_right() const {
	return impulse_right;
}

void AudioEffectConvolutionReverb::set_impulse_stream(const Ref<AudioStreamWAV> &p_stream) {
	impulse_stream = p_stream;
	if (p_stream.is_null()) {
		return;
	}
	PackedFloat32Array left;
	PackedFloat32Array right;
	if (!decode_wav(p_stream, left, right)) {
		return;
	}
	impulse = left;
	impulse_right = right;
	impulse_sample_rate = float(p_stream->get_mix_rate());
	_rebuild_kernel();
}

Ref<AudioStreamWAV> AudioEffectConvolutionReverb::get_impulse_stream() const {
	return impulse_stream;
}

void AudioEffectConvolutionReverb::set_impulse_sample_rate(float p_rate) {
	impulse_sample_rate = MAX(p_rate, 0.0f);
	_rebuild_kernel();
}

float AudioEffectConvolutionReverb::get_impulse_sample_rate() const {
	return impulse_sample_rate;
}

void AudioEffectConvolutionReverb::set_block_size(int p_block_size) {
	const int rounded = CgameConvolutionKernel::round_block(CLAMP(p_block_size, CgameConvolutionKernel::MIN_BLOCK, CgameConvolutionKernel::MAX_BLOCK));
	if (rounded == block_size) {
		return;
	}
	block_size = rounded;
	_rebuild_kernel();
}

int AudioEffectConvolutionReverb::get_block_size() const {
	return block_size;
}

void AudioEffectConvolutionReverb::set_dry(float p_dry) {
	dry = p_dry;
}

float AudioEffectConvolutionReverb::get_dry() const {
	return dry;
}

void AudioEffectConvolutionReverb::set_wet(float p_wet) {
	wet = p_wet;
}

float AudioEffectConvolutionReverb::get_wet() const {
	return wet;
}

void AudioEffectConvolutionReverb::set_impulse_gain_db(float p_db) {
	impulse_gain_db = CLAMP(p_db, -80.0f, 24.0f);
	_rebuild_kernel();
}

float AudioEffectConvolutionReverb::get_impulse_gain_db() const {
	return impulse_gain_db;
}

int AudioEffectConvolutionReverb::get_latency_frames() const {
	return kernel.is_valid() ? kernel->block : block_size;
}

int AudioEffectConvolutionReverb::get_partition_count() const {
	return kernel.is_valid() ? kernel->parts : 0;
}

void AudioEffectConvolutionReverb::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_impulse", "impulse"), &AudioEffectConvolutionReverb::set_impulse);
	ClassDB::bind_method(D_METHOD("get_impulse"), &AudioEffectConvolutionReverb::get_impulse);
	ClassDB::bind_method(D_METHOD("set_impulse_right", "impulse"), &AudioEffectConvolutionReverb::set_impulse_right);
	ClassDB::bind_method(D_METHOD("get_impulse_right"), &AudioEffectConvolutionReverb::get_impulse_right);
	ClassDB::bind_method(D_METHOD("set_impulse_stream", "stream"), &AudioEffectConvolutionReverb::set_impulse_stream);
	ClassDB::bind_method(D_METHOD("get_impulse_stream"), &AudioEffectConvolutionReverb::get_impulse_stream);
	ClassDB::bind_method(D_METHOD("set_impulse_sample_rate", "hz"), &AudioEffectConvolutionReverb::set_impulse_sample_rate);
	ClassDB::bind_method(D_METHOD("get_impulse_sample_rate"), &AudioEffectConvolutionReverb::get_impulse_sample_rate);
	ClassDB::bind_method(D_METHOD("set_block_size", "frames"), &AudioEffectConvolutionReverb::set_block_size);
	ClassDB::bind_method(D_METHOD("get_block_size"), &AudioEffectConvolutionReverb::get_block_size);
	ClassDB::bind_method(D_METHOD("set_dry", "amount"), &AudioEffectConvolutionReverb::set_dry);
	ClassDB::bind_method(D_METHOD("get_dry"), &AudioEffectConvolutionReverb::get_dry);
	ClassDB::bind_method(D_METHOD("set_wet", "amount"), &AudioEffectConvolutionReverb::set_wet);
	ClassDB::bind_method(D_METHOD("get_wet"), &AudioEffectConvolutionReverb::get_wet);
	ClassDB::bind_method(D_METHOD("set_impulse_gain_db", "db"), &AudioEffectConvolutionReverb::set_impulse_gain_db);
	ClassDB::bind_method(D_METHOD("get_impulse_gain_db"), &AudioEffectConvolutionReverb::get_impulse_gain_db);
	ClassDB::bind_method(D_METHOD("get_latency_frames"), &AudioEffectConvolutionReverb::get_latency_frames);
	ClassDB::bind_method(D_METHOD("get_partition_count"), &AudioEffectConvolutionReverb::get_partition_count);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "impulse"), "set_impulse", "get_impulse");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "impulse_right"), "set_impulse_right", "get_impulse_right");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "impulse_stream", PROPERTY_HINT_RESOURCE_TYPE, "AudioStreamWAV", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_ALWAYS_DUPLICATE), "set_impulse_stream", "get_impulse_stream");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "impulse_sample_rate", PROPERTY_HINT_RANGE, "0,192000,1,or_greater,suffix:Hz"), "set_impulse_sample_rate", "get_impulse_sample_rate");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "block_size", PROPERTY_HINT_RANGE, "16,16384,1,suffix:frames"), "set_block_size", "get_block_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "dry", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_dry", "get_dry");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "wet", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_wet", "get_wet");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "impulse_gain_db", PROPERTY_HINT_RANGE, "-80,24,0.1,suffix:dB"), "set_impulse_gain_db", "get_impulse_gain_db");
}

AudioEffectConvolutionReverb::AudioEffectConvolutionReverb() {}

AudioEffectConvolutionReverb::~AudioEffectConvolutionReverb() {}
