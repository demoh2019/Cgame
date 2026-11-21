/**************************************************************************/
/*  cgame_audio_graph.h                                                   */
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

// Block-based procedural audio graph evaluator (MetaSounds-style dataflow).
//
// Graph asset (identical to the project's GDScript audio_graph.gd):
//   {"nodes": {id: {"type": ..., param: value, ...}},
//    "connections": [[from_id, to_id, input_name], ...],
//    "output": id}
// A connection to input "X" replaces the constant param X with the source signal; a
// connection to "X_mod" is added to it. Several connections to one input are summed.
//
// Node types: sine saw square triangle, noise_white noise_pink noise_brown, const, adsr, ar,
// lowpass highpass bandpass, smooth, delay, gain, mixer, multiply, clip (alias distortion),
// random_pitch, random_trigger.
//
// Algorithms (formulas only, all re-implemented):
//  - Biquad coefficients: "Audio EQ Cookbook" by Robert Bristow-Johnson (RBJ),
//    https://www.w3.org/TR/audio-eq-cookbook/
//  - polyBLEP band-limited step correction: V. Valimaki and A. Huovilainen, "Antialiasing
//    Oscillators in Subtractive Synthesis", IEEE Signal Processing Magazine 24(2), 2007.
//  - Pink noise: Voss-McCartney multi-row algorithm (Gardner 1978).
//  - Block dataflow with topological evaluation follows the general design of node-based
//    audio engines; cycles are only legal through a delay node.
//
// Real-time safety: compile() allocates; render() performs no allocation.

#include "core/math/random_pcg.h"
#include "core/string/ustring.h"
#include "core/templates/pair.h"
#include "core/variant/variant.h"
#include "core/templates/local_vector.h"
#include "core/variant/dictionary.h"

class CgameAudioGraph {
public:
	static constexpr int BLOCK = 64;
	static constexpr int MAX_NODE_COUNT = 256;
	static constexpr float MAX_DELAY_SECONDS = 10.0f;

	// Human readable problems; empty means the graph can be compiled.
	static Vector<String> validate(const Dictionary &p_graph);

private:
	enum NodeType {
		T_SINE,
		T_SAW,
		T_SQUARE,
		T_TRIANGLE,
		T_NOISE_WHITE,
		T_NOISE_PINK,
		T_NOISE_BROWN,
		T_CONST,
		T_ADSR,
		T_AR,
		T_LOWPASS,
		T_HIGHPASS,
		T_BANDPASS,
		T_SMOOTH,
		T_DELAY,
		T_GAIN,
		T_MIXER,
		T_MULTIPLY,
		T_CLIP,
		T_RANDOM_PITCH,
		T_RANDOM_TRIGGER,
		T_MAX,
	};

	enum Param {
		P_FREQ,
		P_AMP,
		P_PHASE,
		P_PW,
		P_VALUE,
		P_START,
		P_GATE,
		P_ATTACK,
		P_DECAY,
		P_SUSTAIN,
		P_RELEASE,
		P_CUTOFF,
		P_Q,
		P_TIME,
		P_FEEDBACK,
		P_GAIN,
		P_A,
		P_B,
		P_DRIVE,
		P_MIN,
		P_MAX,
		P_RATE,
		P_MIN_AMP,
		P_COUNT,
	};

	enum Input {
		IN_IN,
		IN_FREQ,
		IN_AMP,
		IN_CUTOFF,
		IN_Q,
		IN_GAIN,
		IN_A,
		IN_B,
		IN_DRIVE,
		IN_COUNT,
	};

	struct DefaultParam {
		Param param;
		double value;
	};

	struct Node {
		String id;
		NodeType type = T_CONST;
		double params[P_COUNT] = {};
		LocalVector<int> srcs[IN_COUNT];
		LocalVector<int> mods[IN_COUNT];
		float out[BLOCK] = {};
		float scratch[3][BLOCK] = {};

		// State.
		double ph = 0.0;
		double s1 = 0.0;
		double s2 = 0.0;
		double lvl = 0.0;
		double rate = 0.0;
		int stage = 0;
		int counter = 0;
		double held = 0.0;
		double rows[8] = {};
		double rows_sum = 0.0;
		RandomPCG rng;
		LocalVector<float> hist; // Delay ring buffer.
		int delay_samples = 0;
	};

	LocalVector<Node *> nodes; // Evaluation order.
	int output_node = -1;
	double sample_rate = 44100.0;
	int64_t frame_counter = 0; // First sample index of the next block.
	int64_t seed = 0;
	float block_out[BLOCK] = {};
	int block_pos = BLOCK;
	bool compiled = false;

	static void get_defaults(NodeType p_type, LocalVector<DefaultParam> &r_out);
	static uint32_t node_seed(int64_t p_seed, const String &p_id);
	static bool type_from_string(const String &p_name, NodeType &r_type);
	static bool param_from_string(const String &p_name, Param &r_param);
	static bool input_from_string(const String &p_name, Input &r_input);
	static Vector<String> cycle_nodes(const Dictionary &p_nodes, const Vector<Pair<String, String>> &p_edges);

	const float *sig(Node &p_node, Input p_input, int p_slot);
	void process_node(Node &p_node);
	void process_osc(Node &p_node);
	void process_envelope(Node &p_node);
	void process_biquad(Node &p_node);
	void delay_write(Node &p_node);
	void process_block();
	void clear_state();

public:
	// Compiles a graph. Returns false and fills r_errors when invalid.
	bool compile(const Dictionary &p_graph, double p_sample_rate, int64_t p_seed, Vector<String> *r_errors = nullptr);
	bool is_compiled() const { return compiled; }
	// Rewinds to time zero with the original seed.
	void reset();
	// Produces p_frames mono samples; clamped to [-1, 1] with NaN/Inf replaced by silence.
	void render(float *r_out, int p_frames);
	int64_t get_frame_position() const;

	~CgameAudioGraph();
};
