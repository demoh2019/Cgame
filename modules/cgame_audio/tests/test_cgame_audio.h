/**************************************************************************/
/*  test_cgame_audio.h                                                    */
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

#include "../audio_effect_convolution_reverb.h"
#include "../audio_stream_procedural.h"
#include "../cgame_audio_graph.h"
#include "../cgame_convolution.h"
#include "../cgame_early_reflections.h"

#include "core/math/random_pcg.h"
#include "servers/audio/audio_server.h"
#include "tests/test_macros.h"

namespace TestCgameAudio {

static Vector<float> random_signal(int p_count, uint64_t p_seed) {
	RandomPCG rng(p_seed);
	Vector<float> v;
	v.resize(p_count);
	for (int i = 0; i < p_count; i++) {
		v.write[i] = rng.random(-1.0f, 1.0f);
	}
	return v;
}

// Streams p_input through the engine in irregular chunk sizes, returns all wet output.
static Vector<AudioFrame> stream_through(CgameConvolutionEngine &p_engine, const Vector<AudioFrame> &p_input) {
	Vector<AudioFrame> out;
	out.resize(p_input.size());
	static const int chunks[] = { 1, 7, 64, 100, 33, 255, 3, 512 };
	int pos = 0;
	int ci = 0;
	while (pos < p_input.size()) {
		const int n = MIN(chunks[ci++ % 8], p_input.size() - pos);
		p_engine.process(p_input.ptr() + pos, out.ptrw() + pos, n);
		pos += n;
	}
	return out;
}

static bool same(const PackedFloat32Array &p_a, const PackedFloat32Array &p_b) {
	if (p_a.size() != p_b.size()) {
		return false;
	}
	for (int i = 0; i < p_a.size(); i++) {
		if (p_a[i] != p_b[i]) {
			return false;
		}
	}
	return true;
}

static Dictionary node(const String &p_type) {
	Dictionary d;
	d["type"] = p_type;
	return d;
}

static Dictionary single_node_graph(const Dictionary &p_def) {
	Dictionary nodes;
	nodes["o"] = p_def;
	Dictionary g;
	g["nodes"] = nodes;
	g["connections"] = Array();
	g["output"] = "o";
	return g;
}

static Array connection(const String &p_from, const String &p_to, const String &p_input) {
	Array a;
	a.push_back(p_from);
	a.push_back(p_to);
	a.push_back(p_input);
	return a;
}

TEST_CASE("[CgameAudio][Convolution] Partitioned FFT convolution matches direct convolution") {
	const int ir_len = 1000;
	const int x_len = 3000;
	const Vector<float> ir = random_signal(ir_len, 11);
	const Vector<float> x = random_signal(x_len, 22);

	Vector<float> expected;
	expected.resize(x_len + ir_len - 1);
	CgameConvolutionKernel::direct_convolve(x.ptr(), x_len, ir.ptr(), ir_len, expected.ptrw());

	for (int block : { 16, 64, 256 }) {
		Ref<CgameConvolutionKernel> kernel;
		kernel.instantiate();
		REQUIRE(kernel->build(ir.ptr(), ir_len, nullptr, 0, block));
		CHECK(kernel->parts == (ir_len + block - 1) / block);

		CgameConvolutionEngine engine;
		engine.setup(kernel);
		CHECK(engine.get_latency_frames() == block);

		const int total = expected.size() + block;
		Vector<AudioFrame> input;
		input.resize(total);
		for (int i = 0; i < total; i++) {
			const float s = i < x_len ? x[i] : 0.0f;
			input.write[i] = AudioFrame(s, -s);
		}
		const Vector<AudioFrame> wet = stream_through(engine, input);

		float max_err = 0.0f;
		for (int i = 0; i < expected.size(); i++) {
			max_err = MAX(max_err, Math::abs(wet[i + block].left - expected[i]));
			max_err = MAX(max_err, Math::abs(wet[i + block].right + expected[i]));
		}
		CHECK_MESSAGE(max_err < 1e-4f, "block ", block, " max error ", max_err);
		// The wet signal is silent during the latency window.
		for (int i = 0; i < block; i++) {
			CHECK(wet[i].left == 0.0f);
		}
	}
}

TEST_CASE("[CgameAudio][Convolution] Stereo impulse responses are applied per channel") {
	const Vector<float> left_ir = random_signal(300, 5);
	const Vector<float> right_ir = random_signal(450, 6);
	const Vector<float> x = random_signal(1000, 7);

	Vector<float> exp_l;
	Vector<float> exp_r;
	exp_l.resize(1000 + 300 - 1);
	exp_r.resize(1000 + 450 - 1);
	CgameConvolutionKernel::direct_convolve(x.ptr(), 1000, left_ir.ptr(), 300, exp_l.ptrw());
	CgameConvolutionKernel::direct_convolve(x.ptr(), 1000, right_ir.ptr(), 450, exp_r.ptrw());

	Ref<CgameConvolutionKernel> kernel;
	kernel.instantiate();
	REQUIRE(kernel->build(left_ir.ptr(), 300, right_ir.ptr(), 450, 64));
	CHECK(kernel->channels == 2);

	CgameConvolutionEngine engine;
	engine.setup(kernel);
	Vector<AudioFrame> input;
	input.resize(1500 + 64);
	for (int i = 0; i < input.size(); i++) {
		const float s = i < 1000 ? x[i] : 0.0f;
		input.write[i] = AudioFrame(s, s);
	}
	const Vector<AudioFrame> wet = stream_through(engine, input);
	float max_err = 0.0f;
	for (int i = 0; i < exp_l.size(); i++) {
		max_err = MAX(max_err, Math::abs(wet[i + 64].left - exp_l[i]));
	}
	for (int i = 0; i < exp_r.size(); i++) {
		max_err = MAX(max_err, Math::abs(wet[i + 64].right - exp_r[i]));
	}
	CHECK(max_err < 1e-4f);
}

TEST_CASE("[CgameAudio][Convolution] Tail activity ends after the impulse response") {
	Vector<float> ir;
	ir.resize(100);
	ir.write[0] = 1.0f;
	Ref<CgameConvolutionKernel> kernel;
	kernel.instantiate();
	REQUIRE(kernel->build(ir.ptr(), 100, nullptr, 0, 16));
	CgameConvolutionEngine engine;
	engine.setup(kernel);
	CHECK(engine.is_tail_active());
	Vector<AudioFrame> zeros;
	zeros.resize(512);
	Vector<AudioFrame> out;
	out.resize(512);
	engine.process(zeros.ptr(), out.ptrw(), 512);
	CHECK_FALSE(engine.is_tail_active());
	AudioFrame one[1] = { AudioFrame(1, 1) };
	AudioFrame wet[1];
	engine.process(one, wet, 1);
	CHECK(engine.is_tail_active());
}

TEST_CASE("[CgameAudio][Convolution] Reverb effect delays a unit impulse by the block size and swaps IR lock-free") {
	Ref<AudioEffectConvolutionReverb> effect;
	effect.instantiate();
	effect->set_block_size(16);
	effect->set_dry(0.0f);
	effect->set_wet(1.0f);
	PackedFloat32Array delta;
	delta.push_back(1.0f);
	effect->set_impulse(delta);
	CHECK(effect->get_latency_frames() == 16);

	Ref<AudioEffectInstance> instance = effect->instantiate();
	const int frames = 64;
	Vector<AudioFrame> src;
	src.resize(frames);
	Vector<AudioFrame> dst;
	dst.resize(frames);
	for (int i = 0; i < frames; i++) {
		src.write[i] = AudioFrame(float(i + 1), float(-(i + 1)));
	}
	instance->process(src.ptr(), dst.ptrw(), frames);
	for (int i = 0; i < frames; i++) {
		const float expected = i >= 16 ? float(i - 16 + 1) : 0.0f;
		CHECK(Math::abs(dst[i].left - expected) < 1e-3f);
		CHECK(Math::abs(dst[i].right + expected) < 1e-3f);
	}

	// Swap to a two-tap IR while the instance is live; the next process call picks it up.
	PackedFloat32Array two_tap;
	two_tap.push_back(0.0f);
	two_tap.push_back(2.0f);
	effect->set_impulse(two_tap);
	Vector<AudioFrame> impulse_in;
	impulse_in.resize(64);
	impulse_in.write[0] = AudioFrame(1, 1);
	Vector<AudioFrame> out;
	out.resize(64);
	instance->process(impulse_in.ptr(), out.ptrw(), 64);
	CHECK(Math::abs(out[17].left - 2.0f) < 1e-3f);
	CHECK(Math::abs(out[16].left) < 1e-3f);
}

TEST_CASE("[CgameAudio][Convolution] Reverb effect decodes 16-bit WAV impulses") {
	Ref<AudioStreamWAV> wav;
	wav.instantiate();
	wav->set_format(AudioStreamWAV::FORMAT_16_BITS);
	wav->set_stereo(false);
	Vector<uint8_t> data;
	data.resize(8);
	const int16_t samples[4] = { 16384, 0, -16384, 8192 };
	for (int i = 0; i < 4; i++) {
		data.write[i * 2] = uint8_t(uint16_t(samples[i]) & 0xFF);
		data.write[i * 2 + 1] = uint8_t(uint16_t(samples[i]) >> 8);
	}
	wav->set_data(data);

	PackedFloat32Array left;
	PackedFloat32Array right;
	REQUIRE(AudioEffectConvolutionReverb::decode_wav(wav, left, right));
	CHECK(left.size() == 4);
	CHECK(right.is_empty());
	CHECK(Math::abs(left[0] - 0.5f) < 1e-6f);
	CHECK(Math::abs(left[2] + 0.5f) < 1e-6f);
	CHECK(Math::abs(left[3] - 0.25f) < 1e-6f);
}

TEST_CASE("[CgameAudio][EarlyReflections] First-order image sources of a shoebox") {
	const Vector3 room(10, 8, 3);
	const Vector3 source(2, 3, 1);
	const Vector3 listener(5, 4, 1.5);

	CHECK(CgameEarlyReflections::image_source_count(0) == 1);
	CHECK(CgameEarlyReflections::image_source_count(1) == 7);
	CHECK(CgameEarlyReflections::image_source_count(2) == 25);

	const TypedArray<Dictionary> images = CgameEarlyReflections::image_sources_box(room, source, listener, 1, 0.0f);
	REQUIRE(images.size() == 7);

	int first_order = 0;
	double previous = -1.0;
	for (int i = 0; i < images.size(); i++) {
		const Dictionary d = images[i];
		if (int(d["order"]) == 1) {
			first_order++;
		}
		const double delay = d["delay_s"];
		CHECK(delay >= previous);
		previous = delay;
	}
	CHECK(first_order == 6);

	// Direct path first.
	const Dictionary direct = images[0];
	CHECK(int(direct["order"]) == 0);
	CHECK(Math::abs(double(direct["distance"]) - double((source - listener).length())) < 1e-4);
	CHECK(Math::abs(double(direct["delay_s"]) - double((source - listener).length()) / 343.0) < 1e-6);

	// The six mirror images must match the analytic wall distances.
	const Vector3 mirrors[6] = {
		Vector3(-source.x, source.y, source.z),
		Vector3(2 * room.x - source.x, source.y, source.z),
		Vector3(source.x, -source.y, source.z),
		Vector3(source.x, 2 * room.y - source.y, source.z),
		Vector3(source.x, source.y, -source.z),
		Vector3(source.x, source.y, 2 * room.z - source.z),
	};
	Vector<double> expected;
	for (const Vector3 &m : mirrors) {
		expected.push_back(double((m - listener).length()) / 343.0);
	}
	expected.sort();
	Vector<double> actual;
	for (int i = 0; i < images.size(); i++) {
		const Dictionary d = images[i];
		if (int(d["order"]) == 1) {
			actual.push_back(d["delay_s"]);
		}
	}
	actual.sort();
	REQUIRE(actual.size() == 6);
	for (int i = 0; i < 6; i++) {
		CHECK(Math::abs(actual[i] - expected[i]) < 1e-6);
	}

	// Absorption: one bounce scales by sqrt(1 - absorption).
	const TypedArray<Dictionary> absorbed = CgameEarlyReflections::image_sources_box(room, source, listener, 1, 0.75f);
	for (int i = 0; i < absorbed.size(); i++) {
		const Dictionary d = absorbed[i];
		if (int(d["order"]) == 1) {
			const double expected_gain = 0.5 / MAX(double(d["distance"]), 0.1);
			CHECK(Math::abs(double(d["gain"]) - expected_gain) < 1e-6);
		}
	}
}

TEST_CASE("[CgameAudio][EarlyReflections] IR synthesis is normalised, sized and deterministic") {
	const TypedArray<Dictionary> images = CgameEarlyReflections::image_sources_box(Vector3(6, 4, 3), Vector3(1, 1, 1), Vector3(4, 2, 1.5), 2, 0.3f);
	const PackedFloat32Array a = CgameEarlyReflections::to_ir(images, 22050, 0.5f);
	const PackedFloat32Array b = CgameEarlyReflections::to_ir(images, 22050, 0.5f);
	CHECK(a.size() == 11025);
	CHECK(same(a, b));
	float peak = 0.0f;
	for (int i = 0; i < a.size(); i++) {
		CHECK(Math::is_finite(a[i]));
		peak = MAX(peak, Math::abs(a[i]));
	}
	CHECK(Math::abs(peak - 1.0f) < 1e-5f);
	const PackedFloat32Array c = CgameEarlyReflections::to_ir(images, 22050, 0.5f, Vector3(0.7, 0.6, 0.4), 0.04f, 0.25f, 2);
	CHECK_FALSE(same(a, c));
}

TEST_CASE("[CgameAudio][Procedural] Graph validation") {
	CHECK(CgameAudioGraph::validate(Dictionary()).size() == 1);

	Dictionary bad_type = single_node_graph(node("nonsense"));
	CHECK_FALSE(CgameAudioGraph::validate(bad_type).is_empty());

	// Cycle without a delay is rejected.
	Dictionary nodes;
	nodes["a"] = node("gain");
	nodes["b"] = node("gain");
	Dictionary cyc;
	cyc["nodes"] = nodes;
	Array conns;
	conns.push_back(connection("a", "b", "in"));
	conns.push_back(connection("b", "a", "in"));
	cyc["connections"] = conns;
	cyc["output"] = "a";
	CHECK_FALSE(CgameAudioGraph::validate(cyc).is_empty());

	// The same loop closed through a delay is valid.
	nodes["b"] = node("delay");
	cyc["nodes"] = nodes;
	CHECK(CgameAudioGraph::validate(cyc).is_empty());
}

TEST_CASE("[CgameAudio][Procedural] Sine oscillator frequency and finite output") {
	const double rate = 22050.0;
	Dictionary def = node("sine");
	def["freq"] = 440.0;
	CgameAudioGraph graph;
	REQUIRE(graph.compile(single_node_graph(def), rate, 0));
	Vector<float> samples;
	samples.resize(11025);
	graph.render(samples.ptrw(), samples.size());
	int crossings = 0;
	float energy = 0.0f;
	for (int i = 0; i < samples.size(); i++) {
		CHECK(Math::is_finite(samples[i]));
		energy += samples[i] * samples[i];
		if (i > 0 && samples[i - 1] < 0.0f && samples[i] >= 0.0f) {
			crossings++;
		}
	}
	CHECK(Math::abs(crossings - 220) <= 2);
	CHECK(energy > 1000.0f);
}

TEST_CASE("[CgameAudio][Procedural] Envelope, filter, delay and determinism") {
	// Noise -> lowpass -> gain driven by an AR envelope, plus a feedback delay.
	Dictionary nodes;
	nodes["n"] = node("noise_white");
	Dictionary lp = node("lowpass");
	lp["cutoff"] = 800.0;
	nodes["f"] = lp;
	Dictionary env = node("ar");
	env["attack"] = 0.02;
	env["release"] = 0.1;
	nodes["e"] = env;
	nodes["g"] = node("gain");
	Dictionary dl = node("delay");
	dl["time"] = 0.05;
	dl["feedback"] = 0.5;
	nodes["d"] = dl;
	nodes["m"] = node("mixer");
	Array conns;
	conns.push_back(connection("n", "f", "in"));
	conns.push_back(connection("f", "g", "in"));
	conns.push_back(connection("e", "g", "gain"));
	conns.push_back(connection("g", "d", "in"));
	conns.push_back(connection("g", "m", "in"));
	conns.push_back(connection("d", "m", "in"));
	Dictionary graph;
	graph["nodes"] = nodes;
	graph["connections"] = conns;
	graph["output"] = "m";

	Ref<AudioStreamProcedural> stream;
	stream.instantiate();
	stream->set_graph(graph);
	stream->set_mix_rate(22050.0f);
	stream->set_seed(42);
	REQUIRE(stream->is_valid());

	const PackedFloat32Array a = stream->render(0.5f);
	const PackedFloat32Array b = stream->render(0.5f);
	CHECK(a.size() == 11025);
	CHECK(same(a, b)); // Deterministic for a fixed seed.

	float energy = 0.0f;
	for (int i = 0; i < a.size(); i++) {
		CHECK(Math::is_finite(a[i]));
		CHECK(Math::abs(a[i]) <= 1.0f);
		energy += a[i] * a[i];
	}
	CHECK(energy > 0.01f);
	// Envelope has finished long before the end; only the decaying echoes remain.
	float late = 0.0f;
	for (int i = 10000; i < a.size(); i++) {
		late = MAX(late, Math::abs(a[i]));
	}
	CHECK(late < 0.1f);

	stream->set_seed(43);
	CHECK_FALSE(same(stream->render(0.5f), a));

	// Rendering in odd chunk sizes yields the same samples as one pass.
	CgameAudioGraph runtime;
	REQUIRE(runtime.compile(graph, 22050.0, 42));
	Vector<float> chunked;
	chunked.resize(a.size());
	int pos = 0;
	int step = 1;
	while (pos < chunked.size()) {
		const int n = MIN(step, chunked.size() - pos);
		runtime.render(chunked.ptrw() + pos, n);
		pos += n;
		step = (step * 3 + 1) % 200 + 1;
	}
	for (int i = 0; i < a.size(); i++) {
		CHECK(chunked[i] == a[i]);
	}
}

TEST_CASE("[CgameAudio][Procedural] Stream playback renders through the audio mixer path") {
	if (AudioServer::get_singleton() == nullptr) {
		return;
	}
	Dictionary def = node("saw");
	def["freq"] = 220.0;
	Ref<AudioStreamProcedural> stream;
	stream.instantiate();
	stream->set_graph(single_node_graph(def));

	Ref<AudioStreamPlayback> playback = stream->instantiate_playback();
	REQUIRE(playback.is_valid());
	playback->start();
	CHECK(playback->is_playing());
	Vector<AudioFrame> buffer;
	buffer.resize(2048);
	playback->mix(buffer.ptrw(), 1.0f, buffer.size());
	float energy = 0.0f;
	for (int i = 0; i < buffer.size(); i++) {
		CHECK(Math::is_finite(buffer[i].left));
		energy += buffer[i].left * buffer[i].left;
	}
	CHECK(energy > 1.0f);
}

} // namespace TestCgameAudio
