/**************************************************************************/
/*  cgame_audio_graph.cpp                                                 */
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

#include "cgame_audio_graph.h"

#include "core/math/math_funcs.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/pair.h"
#include "core/templates/vector.h"

// Parameter and input name tables ------------------------------------------------------------

bool CgameAudioGraph::type_from_string(const String &p_name, NodeType &r_type) {
	static const char *names[T_MAX] = {
		"sine", "saw", "square", "triangle", "noise_white", "noise_pink", "noise_brown", "const",
		"adsr", "ar", "lowpass", "highpass", "bandpass", "smooth", "delay", "gain", "mixer",
		"multiply", "clip", "random_pitch", "random_trigger"
	};
	for (int i = 0; i < T_MAX; i++) {
		if (p_name == names[i]) {
			r_type = NodeType(i);
			return true;
		}
	}
	if (p_name == "distortion") {
		r_type = T_CLIP;
		return true;
	}
	return false;
}

bool CgameAudioGraph::param_from_string(const String &p_name, Param &r_param) {
	static const char *names[P_COUNT] = {
		"freq", "amp", "phase", "pw", "value", "start", "gate", "attack", "decay", "sustain",
		"release", "cutoff", "q", "time", "feedback", "gain", "a", "b", "drive", "min", "max",
		"rate", "min_amp"
	};
	for (int i = 0; i < P_COUNT; i++) {
		if (p_name == names[i]) {
			r_param = Param(i);
			return true;
		}
	}
	return false;
}

bool CgameAudioGraph::input_from_string(const String &p_name, Input &r_input) {
	static const char *names[IN_COUNT] = { "in", "freq", "amp", "cutoff", "q", "gain", "a", "b", "drive" };
	for (int i = 0; i < IN_COUNT; i++) {
		if (p_name == names[i]) {
			r_input = Input(i);
			return true;
		}
	}
	return false;
}

void CgameAudioGraph::get_defaults(NodeType p_type, LocalVector<DefaultParam> &r_out) {
	r_out.clear();
	switch (p_type) {
		case T_SINE:
		case T_SAW:
		case T_SQUARE:
		case T_TRIANGLE:
			r_out.push_back({ P_FREQ, 440.0 });
			r_out.push_back({ P_AMP, 1.0 });
			r_out.push_back({ P_PHASE, 0.0 });
			r_out.push_back({ P_PW, 0.5 });
			break;
		case T_NOISE_WHITE:
		case T_NOISE_PINK:
		case T_NOISE_BROWN:
			r_out.push_back({ P_AMP, 1.0 });
			break;
		case T_CONST:
			r_out.push_back({ P_VALUE, 1.0 });
			break;
		case T_ADSR:
			r_out.push_back({ P_START, 0.0 });
			r_out.push_back({ P_GATE, 0.3 });
			r_out.push_back({ P_ATTACK, 0.01 });
			r_out.push_back({ P_DECAY, 0.1 });
			r_out.push_back({ P_SUSTAIN, 0.6 });
			r_out.push_back({ P_RELEASE, 0.2 });
			break;
		case T_AR:
			r_out.push_back({ P_START, 0.0 });
			r_out.push_back({ P_ATTACK, 0.01 });
			r_out.push_back({ P_RELEASE, 0.2 });
			break;
		case T_LOWPASS:
		case T_HIGHPASS:
			r_out.push_back({ P_CUTOFF, 1000.0 });
			r_out.push_back({ P_Q, 0.707 });
			break;
		case T_BANDPASS:
			r_out.push_back({ P_CUTOFF, 1000.0 });
			r_out.push_back({ P_Q, 1.0 });
			break;
		case T_SMOOTH:
			r_out.push_back({ P_TIME, 0.05 });
			break;
		case T_DELAY:
			r_out.push_back({ P_TIME, 0.25 });
			r_out.push_back({ P_FEEDBACK, 0.3 });
			break;
		case T_GAIN:
		case T_MIXER:
			r_out.push_back({ P_GAIN, 1.0 });
			break;
		case T_MULTIPLY:
			r_out.push_back({ P_A, 1.0 });
			r_out.push_back({ P_B, 1.0 });
			break;
		case T_CLIP:
			r_out.push_back({ P_DRIVE, 1.0 });
			break;
		case T_RANDOM_PITCH:
			r_out.push_back({ P_MIN, 200.0 });
			r_out.push_back({ P_MAX, 400.0 });
			r_out.push_back({ P_RATE, 4.0 });
			break;
		case T_RANDOM_TRIGGER:
			r_out.push_back({ P_RATE, 20.0 });
			r_out.push_back({ P_DECAY, 0.02 });
			r_out.push_back({ P_MIN_AMP, 0.3 });
			break;
		default:
			break;
	}
}

uint32_t CgameAudioGraph::node_seed(int64_t p_seed, const String &p_id) {
	return (String::num_int64(p_seed) + ":" + p_id).hash();
}

// Validation ---------------------------------------------------------------------------------

Vector<String> CgameAudioGraph::cycle_nodes(const Dictionary &p_nodes, const Vector<Pair<String, String>> &p_edges) {
	HashMap<String, int> indeg;
	HashMap<String, Vector<String>> adj;
	LocalVector<String> ids;
	for (const KeyValue<Variant, Variant> &kv : p_nodes) {
		const String id = String(kv.key);
		indeg[id] = 0;
		ids.push_back(id);
	}
	for (const Pair<String, String> &e : p_edges) {
		const Dictionary def = p_nodes[e.first];
		if (String(def.get("type", "")) == "delay") {
			continue; // Delay output only needs history; it does not order evaluation.
		}
		indeg[e.second] += 1;
		adj[e.first].push_back(e.second);
	}
	Vector<String> queue;
	for (uint32_t i = 0; i < ids.size(); i++) {
		if (indeg[ids[i]] == 0) {
			queue.push_back(ids[i]);
		}
	}
	int done = 0;
	while (!queue.is_empty()) {
		const String cur = queue[queue.size() - 1];
		queue.resize(queue.size() - 1);
		done++;
		const HashMap<String, Vector<String>>::Iterator it = adj.find(cur);
		if (it == adj.end()) {
			continue;
		}
		for (const String &nxt : it->value) {
			indeg[nxt] -= 1;
			if (indeg[nxt] == 0) {
				queue.push_back(nxt);
			}
		}
	}
	Vector<String> left;
	if (done < int(ids.size())) {
		for (uint32_t i = 0; i < ids.size(); i++) {
			if (indeg[ids[i]] > 0) {
				left.push_back(ids[i]);
			}
		}
		left.sort();
	}
	return left;
}

Vector<String> CgameAudioGraph::validate(const Dictionary &p_graph) {
	Vector<String> errors;
	const Dictionary nodes_dict = p_graph.get("nodes", Dictionary());
	if (nodes_dict.is_empty()) {
		errors.push_back("graph has no nodes");
		return errors;
	}
	if (nodes_dict.size() > MAX_NODE_COUNT) {
		errors.push_back(vformat("too many nodes (%d > %d)", nodes_dict.size(), MAX_NODE_COUNT));
	}
	for (const KeyValue<Variant, Variant> &kv : nodes_dict) {
		const Dictionary def = kv.value;
		const String type = String(def.get("type", ""));
		NodeType t;
		if (!type_from_string(type, t)) {
			errors.push_back(vformat("node '%s' has unknown type '%s'", String(kv.key), type));
		}
	}
	const String output = String(p_graph.get("output", ""));
	if (!nodes_dict.has(output)) {
		errors.push_back(vformat("output node '%s' does not exist", output));
	}
	Vector<Pair<String, String>> order_edges;
	const Array connections = p_graph.get("connections", Array());
	for (int i = 0; i < connections.size(); i++) {
		const Array conn = connections[i];
		if (conn.size() != 3) {
			errors.push_back(vformat("connection %s must be [from, to, input]", Variant(conn)));
			continue;
		}
		const String from_id = String(conn[0]);
		const String to_id = String(conn[1]);
		if (!nodes_dict.has(from_id)) {
			errors.push_back(vformat("connection from unknown node '%s'", from_id));
			continue;
		}
		if (!nodes_dict.has(to_id)) {
			errors.push_back(vformat("connection to unknown node '%s'", to_id));
			continue;
		}
		if (String(conn[2]).is_empty()) {
			errors.push_back(vformat("connection %s -> %s has an empty input name", from_id, to_id));
		}
		order_edges.push_back(Pair<String, String>(from_id, to_id));
	}
	const Vector<String> cyc = cycle_nodes(nodes_dict, order_edges);
	if (!cyc.is_empty()) {
		String joined;
		for (int i = 0; i < cyc.size(); i++) {
			joined += (i > 0 ? ", " : "") + cyc[i];
		}
		errors.push_back("cycle without a delay node through: " + joined);
	}
	return errors;
}

// Compilation --------------------------------------------------------------------------------

CgameAudioGraph::~CgameAudioGraph() {
	for (uint32_t i = 0; i < nodes.size(); i++) {
		memdelete(nodes[i]);
	}
}

bool CgameAudioGraph::compile(const Dictionary &p_graph, double p_sample_rate, int64_t p_seed, Vector<String> *r_errors) {
	for (uint32_t i = 0; i < nodes.size(); i++) {
		memdelete(nodes[i]);
	}
	nodes.clear();
	compiled = false;
	output_node = -1;

	const Vector<String> errors = validate(p_graph);
	if (r_errors) {
		*r_errors = errors;
	}
	if (!errors.is_empty()) {
		return false;
	}
	ERR_FAIL_COND_V(p_sample_rate < 1.0, false);

	sample_rate = p_sample_rate;
	seed = p_seed;
	const Dictionary nodes_dict = p_graph["nodes"];
	const Array connections = p_graph.get("connections", Array());

	// Incoming map over all connections.
	HashMap<String, Vector<String>> incoming;
	for (int i = 0; i < connections.size(); i++) {
		const Array conn = connections[i];
		incoming[String(conn[1])].push_back(String(conn[0]));
	}

	// Nodes the output transitively depends on.
	const String output_id = String(p_graph["output"]);
	HashSet<String> needed;
	Vector<String> stack;
	stack.push_back(output_id);
	while (!stack.is_empty()) {
		const String cur = stack[stack.size() - 1];
		stack.resize(stack.size() - 1);
		if (needed.has(cur)) {
			continue;
		}
		needed.insert(cur);
		const HashMap<String, Vector<String>>::Iterator it = incoming.find(cur);
		if (it != incoming.end()) {
			for (const String &s : it->value) {
				stack.push_back(s);
			}
		}
	}

	// Depth-first post-order evaluation order; a delay's own inputs are not followed.
	Vector<String> ids;
	for (const String &s : needed) {
		ids.push_back(s);
	}
	ids.sort();
	HashSet<String> visited;
	Vector<String> order;
	struct Frame {
		String id;
		int next;
	};
	for (int root = 0; root < ids.size(); root++) {
		if (visited.has(ids[root])) {
			continue;
		}
		Vector<Frame> frames;
		visited.insert(ids[root]);
		frames.push_back({ ids[root], 0 });
		while (!frames.is_empty()) {
			Frame &f = frames.write[frames.size() - 1];
			const Dictionary def = nodes_dict[f.id];
			const bool is_delay = String(def.get("type", "")) == "delay";
			const HashMap<String, Vector<String>>::Iterator it = incoming.find(f.id);
			if (!is_delay && it != incoming.end() && f.next < it->value.size()) {
				const String src = it->value[f.next];
				f.next++;
				if (!visited.has(src)) {
					visited.insert(src);
					frames.push_back({ src, 0 });
				}
				continue;
			}
			order.push_back(f.id);
			frames.resize(frames.size() - 1);
		}
	}

	HashMap<String, int> index_of;
	for (int i = 0; i < order.size(); i++) {
		const Dictionary def = nodes_dict[order[i]];
		Node *nd = memnew(Node);
		nd->id = order[i];
		NodeType type = T_CONST;
		type_from_string(String(def.get("type", "")), type);
		nd->type = type;

		LocalVector<DefaultParam> defaults;
		get_defaults(type, defaults);
		for (uint32_t d = 0; d < defaults.size(); d++) {
			nd->params[defaults[d].param] = defaults[d].value;
		}
		for (const KeyValue<Variant, Variant> &kv : def) {
			const String key = String(kv.key);
			Param p;
			if (key != "type" && param_from_string(key, p) && (kv.value.get_type() == Variant::FLOAT || kv.value.get_type() == Variant::INT)) {
				nd->params[p] = double(kv.value);
			}
		}
		nd->rng.seed(node_seed(p_seed, nd->id));
		if (type == T_DELAY) {
			const double time = CLAMP(nd->params[P_TIME], 0.0, double(MAX_DELAY_SECONDS));
			nd->params[P_TIME] = time;
			nd->delay_samples = MAX(BLOCK, int(time * sample_rate));
			nd->hist.resize(nd->delay_samples + BLOCK);
		}
		index_of[nd->id] = int(nodes.size());
		nodes.push_back(nd);
	}
	for (int i = 0; i < connections.size(); i++) {
		const Array conn = connections[i];
		const HashMap<String, int>::Iterator src_it = index_of.find(String(conn[0]));
		const HashMap<String, int>::Iterator dst_it = index_of.find(String(conn[1]));
		if (src_it == index_of.end() || dst_it == index_of.end()) {
			continue;
		}
		String name = String(conn[2]);
		bool is_mod = false;
		if (name.ends_with("_mod")) {
			name = name.substr(0, name.length() - 4);
			is_mod = true;
		}
		Input in;
		if (!input_from_string(name, in)) {
			continue; // Unknown inputs are stored but never read, like the GDScript original.
		}
		if (is_mod) {
			nodes[dst_it->value]->mods[in].push_back(src_it->value);
		} else {
			nodes[dst_it->value]->srcs[in].push_back(src_it->value);
		}
	}
	output_node = index_of[output_id];
	compiled = true;
	clear_state();
	return true;
}

void CgameAudioGraph::clear_state() {
	frame_counter = 0;
	block_pos = BLOCK;
	for (int i = 0; i < BLOCK; i++) {
		block_out[i] = 0.0f;
	}
	for (uint32_t n = 0; n < nodes.size(); n++) {
		Node &nd = *nodes[n];
		nd.ph = nd.s1 = nd.s2 = nd.lvl = nd.rate = nd.held = nd.rows_sum = 0.0;
		nd.stage = 0;
		nd.counter = 0;
		for (int i = 0; i < 8; i++) {
			nd.rows[i] = 0.0;
		}
		for (int i = 0; i < BLOCK; i++) {
			nd.out[i] = 0.0f;
		}
		for (uint32_t i = 0; i < nd.hist.size(); i++) {
			nd.hist[i] = 0.0f;
		}
		nd.rng.seed(node_seed(seed, nd.id));
	}
}

void CgameAudioGraph::reset() {
	clear_state();
}

int64_t CgameAudioGraph::get_frame_position() const {
	// Samples already handed out: whole blocks computed minus the unread remainder.
	return frame_counter - (block_pos < BLOCK ? (BLOCK - block_pos) : 0);
}

// Rendering ----------------------------------------------------------------------------------

const float *CgameAudioGraph::sig(Node &p_node, Input p_input, int p_slot) {
	const LocalVector<int> &srcs = p_node.srcs[p_input];
	const LocalVector<int> &mods = p_node.mods[p_input];
	if (srcs.size() == 1 && mods.is_empty()) {
		return nodes[srcs[0]]->out;
	}
	float *buf = p_node.scratch[p_slot];
	if (srcs.is_empty()) {
		float base = 0.0f;
		switch (p_input) {
			case IN_FREQ:
				base = float(p_node.params[P_FREQ]);
				break;
			case IN_AMP:
				base = float(p_node.params[P_AMP]);
				break;
			case IN_CUTOFF:
				base = float(p_node.params[P_CUTOFF]);
				break;
			case IN_Q:
				base = float(p_node.params[P_Q]);
				break;
			case IN_GAIN:
				base = float(p_node.params[P_GAIN]);
				break;
			case IN_A:
				base = float(p_node.params[P_A]);
				break;
			case IN_B:
				base = float(p_node.params[P_B]);
				break;
			case IN_DRIVE:
				base = float(p_node.params[P_DRIVE]);
				break;
			default:
				break;
		}
		for (int i = 0; i < BLOCK; i++) {
			buf[i] = base;
		}
	} else {
		for (int i = 0; i < BLOCK; i++) {
			buf[i] = 0.0f;
		}
		for (uint32_t s = 0; s < srcs.size(); s++) {
			const float *so = nodes[srcs[s]]->out;
			for (int i = 0; i < BLOCK; i++) {
				buf[i] += so[i];
			}
		}
	}
	for (uint32_t m = 0; m < mods.size(); m++) {
		const float *mo = nodes[mods[m]]->out;
		for (int i = 0; i < BLOCK; i++) {
			buf[i] += mo[i];
		}
	}
	return buf;
}

static inline float poly_blep(double p_t, double p_dt) {
	if (p_dt <= 0.0) {
		return 0.0f;
	}
	if (p_t < p_dt) {
		const double x = p_t / p_dt;
		return float(x + x - x * x - 1.0);
	}
	if (p_t > 1.0 - p_dt) {
		const double x = (p_t - 1.0) / p_dt;
		return float(x * x + x + x + 1.0);
	}
	return 0.0f;
}

void CgameAudioGraph::process_osc(Node &p_node) {
	const float *freq = sig(p_node, IN_FREQ, 0);
	const float *amp = sig(p_node, IN_AMP, 1);
	const double phase_off = p_node.params[P_PHASE];
	const double pw = CLAMP(p_node.params[P_PW], 0.01, 0.99);
	double ph = p_node.ph;
	for (int i = 0; i < BLOCK; i++) {
		const double dt = CLAMP(double(freq[i]) / sample_rate, 0.0, 0.49);
		double t = ph + phase_off;
		t -= Math::floor(t);
		double v = 0.0;
		switch (p_node.type) {
			case T_SINE:
				v = Math::sin(Math::TAU * t);
				break;
			case T_SAW:
				v = 2.0 * t - 1.0 - double(poly_blep(t, dt));
				break;
			case T_SQUARE: {
				v = t < pw ? 1.0 : -1.0;
				v += double(poly_blep(t, dt));
				double t2 = t + 1.0 - pw;
				t2 -= Math::floor(t2);
				v -= double(poly_blep(t2, dt));
			} break;
			case T_TRIANGLE:
				v = 4.0 * Math::abs(t - 0.5) - 1.0;
				break;
			default:
				break;
		}
		p_node.out[i] = float(v) * amp[i];
		ph += dt;
		ph -= Math::floor(ph);
	}
	p_node.ph = ph;
}

// Stages: 0 waiting, 1 attack, 2 decay, 3 sustain, 4 release, 5 finished.
void CgameAudioGraph::process_envelope(Node &p_node) {
	const bool is_adsr = p_node.type == T_ADSR;
	const double start = p_node.params[P_START];
	const double gate_end = is_adsr ? start + p_node.params[P_GATE] : Math::INF;
	const double atk = 1.0 / (MAX(p_node.params[P_ATTACK], 1e-4) * sample_rate);
	double dec = 0.0;
	double sus = 1.0;
	const double rel = MAX(p_node.params[P_RELEASE], 1e-4) * sample_rate;
	if (is_adsr) {
		sus = CLAMP(p_node.params[P_SUSTAIN], 0.0, 1.0);
		dec = (1.0 - sus) / (MAX(p_node.params[P_DECAY], 1e-4) * sample_rate);
	}
	double lvl = p_node.lvl;
	int stage = p_node.stage;
	double rate = p_node.rate;
	for (int i = 0; i < BLOCK; i++) {
		const double t = double(frame_counter + i) / sample_rate;
		if (stage == 0 && t >= start) {
			stage = 1;
		}
		if (is_adsr && t >= gate_end && stage >= 1 && stage <= 3) {
			stage = 4;
			rate = lvl / rel;
		}
		switch (stage) {
			case 1:
				lvl += atk;
				if (lvl >= 1.0) {
					lvl = 1.0;
					if (is_adsr) {
						stage = 2;
					} else {
						stage = 4;
						rate = 1.0 / rel;
					}
				}
				break;
			case 2:
				lvl -= dec;
				if (lvl <= sus) {
					lvl = sus;
					stage = 3;
				}
				break;
			case 4:
				lvl -= rate;
				if (lvl <= 0.0) {
					lvl = 0.0;
					stage = 5;
				}
				break;
			default:
				break;
		}
		p_node.out[i] = float(lvl);
	}
	p_node.lvl = lvl;
	p_node.stage = stage;
	p_node.rate = rate;
}

void CgameAudioGraph::process_biquad(Node &p_node) {
	const float *x = sig(p_node, IN_IN, 0);
	const float *cutoff = sig(p_node, IN_CUTOFF, 1);
	const float *q = sig(p_node, IN_Q, 2);
	const bool modulated = !p_node.srcs[IN_CUTOFF].is_empty() || !p_node.mods[IN_CUTOFF].is_empty() || !p_node.srcs[IN_Q].is_empty() || !p_node.mods[IN_Q].is_empty();
	double s1 = p_node.s1;
	double s2 = p_node.s2;
	double b0 = 0.0;
	double b1 = 0.0;
	double b2 = 0.0;
	double a1 = 0.0;
	double a2 = 0.0;
	for (int i = 0; i < BLOCK; i++) {
		if (i == 0 || modulated) {
			// RBJ Audio EQ Cookbook.
			const double f = CLAMP(double(cutoff[i]), 10.0, sample_rate * 0.45);
			const double w0 = Math::TAU * f / sample_rate;
			const double cs = Math::cos(w0);
			const double alpha = Math::sin(w0) / (2.0 * MAX(double(q[i]), 0.05));
			const double a0 = 1.0 + alpha;
			a1 = -2.0 * cs / a0;
			a2 = (1.0 - alpha) / a0;
			switch (p_node.type) {
				case T_LOWPASS:
					b0 = (1.0 - cs) * 0.5 / a0;
					b1 = (1.0 - cs) / a0;
					b2 = b0;
					break;
				case T_HIGHPASS:
					b0 = (1.0 + cs) * 0.5 / a0;
					b1 = -(1.0 + cs) / a0;
					b2 = b0;
					break;
				default:
					b0 = alpha / a0;
					b1 = 0.0;
					b2 = -b0;
					break;
			}
		}
		const double v = x[i];
		const double y = b0 * v + s1;
		s1 = b1 * v - a1 * y + s2;
		s2 = b2 * v - a2 * y;
		p_node.out[i] = float(y);
	}
	p_node.s1 = s1;
	p_node.s2 = s2;
}

void CgameAudioGraph::process_node(Node &p_node) {
	float *out = p_node.out;
	switch (p_node.type) {
		case T_SINE:
		case T_SAW:
		case T_SQUARE:
		case T_TRIANGLE:
			process_osc(p_node);
			break;
		case T_NOISE_WHITE: {
			const float *amp = sig(p_node, IN_AMP, 0);
			for (int i = 0; i < BLOCK; i++) {
				out[i] = p_node.rng.random(-1.0f, 1.0f) * amp[i];
			}
		} break;
		case T_NOISE_PINK: {
			const float *amp = sig(p_node, IN_AMP, 0);
			for (int i = 0; i < BLOCK; i++) {
				p_node.counter++;
				// Voss-McCartney: row k refreshes every 2^k samples.
				int c = p_node.counter;
				int row = 0;
				while (row < 7 && (c & 1) == 0) {
					c >>= 1;
					row++;
				}
				p_node.rows_sum -= p_node.rows[row];
				p_node.rows[row] = p_node.rng.random(-1.0f, 1.0f);
				p_node.rows_sum += p_node.rows[row];
				out[i] = float((p_node.rows_sum + p_node.rng.random(-1.0f, 1.0f)) * 0.25) * amp[i];
			}
		} break;
		case T_NOISE_BROWN: {
			const float *amp = sig(p_node, IN_AMP, 0);
			double b = p_node.s1;
			for (int i = 0; i < BLOCK; i++) {
				b = (b + 0.02 * p_node.rng.random(-1.0f, 1.0f)) / 1.02;
				out[i] = float(b * 3.5) * amp[i];
			}
			p_node.s1 = b;
		} break;
		case T_CONST:
			for (int i = 0; i < BLOCK; i++) {
				out[i] = float(p_node.params[P_VALUE]);
			}
			break;
		case T_ADSR:
		case T_AR:
			process_envelope(p_node);
			break;
		case T_LOWPASS:
		case T_HIGHPASS:
		case T_BANDPASS:
			process_biquad(p_node);
			break;
		case T_SMOOTH: {
			const float *x = sig(p_node, IN_IN, 0);
			const double k = 1.0 - Math::exp(-1.0 / (MAX(p_node.params[P_TIME], 1e-5) * sample_rate));
			double y = p_node.s1;
			for (int i = 0; i < BLOCK; i++) {
				y += k * (double(x[i]) - y);
				out[i] = float(y);
			}
			p_node.s1 = y;
		} break;
		case T_DELAY: {
			const int d = p_node.delay_samples;
			const int64_t ring = int64_t(p_node.hist.size());
			const int64_t t0 = frame_counter;
			for (int i = 0; i < BLOCK; i++) {
				const int64_t idx = t0 + i - d;
				out[i] = idx >= 0 ? p_node.hist[idx % ring] : 0.0f;
			}
		} break;
		case T_GAIN:
		case T_MIXER: {
			const float *x = sig(p_node, IN_IN, 0);
			const float *g = sig(p_node, IN_GAIN, 1);
			for (int i = 0; i < BLOCK; i++) {
				out[i] = x[i] * g[i];
			}
		} break;
		case T_MULTIPLY: {
			const float *a = sig(p_node, IN_A, 0);
			const float *b = sig(p_node, IN_B, 1);
			for (int i = 0; i < BLOCK; i++) {
				out[i] = a[i] * b[i];
			}
		} break;
		case T_CLIP: {
			const float *x = sig(p_node, IN_IN, 0);
			const float *drive = sig(p_node, IN_DRIVE, 1);
			for (int i = 0; i < BLOCK; i++) {
				out[i] = Math::tanh(x[i] * drive[i]);
			}
		} break;
		case T_RANDOM_PITCH: {
			const double lo = MAX(p_node.params[P_MIN], 1.0);
			const double hi = MAX(p_node.params[P_MAX], lo);
			const int interval = int(sample_rate / MAX(p_node.params[P_RATE], 0.01));
			for (int i = 0; i < BLOCK; i++) {
				if (p_node.counter <= 0) {
					p_node.held = Math::exp(p_node.rng.random(Math::log(lo), Math::log(hi)));
					p_node.counter = interval;
				}
				p_node.counter--;
				out[i] = float(p_node.held);
			}
		} break;
		case T_RANDOM_TRIGGER: {
			const double p = p_node.params[P_RATE] / sample_rate;
			const double k = Math::exp(-1.0 / (MAX(p_node.params[P_DECAY], 1e-4) * sample_rate));
			const double min_amp = p_node.params[P_MIN_AMP];
			double e = p_node.lvl;
			for (int i = 0; i < BLOCK; i++) {
				if (double(p_node.rng.randf()) < p) {
					e = p_node.rng.random(min_amp, 1.0);
				}
				out[i] = float(e);
				e *= k;
			}
			p_node.lvl = e;
		} break;
		default:
			break;
	}
}

// Second pass of a block: records the input (plus internal feedback of the wet signal).
void CgameAudioGraph::delay_write(Node &p_node) {
	const float *x = sig(p_node, IN_IN, 0);
	const float fb = float(CLAMP(p_node.params[P_FEEDBACK], 0.0, 0.98));
	const int d = p_node.delay_samples;
	const int64_t ring = int64_t(p_node.hist.size());
	const int64_t t0 = frame_counter;
	for (int i = 0; i < BLOCK; i++) {
		const int64_t idx = t0 + i;
		const float wet = idx - d >= 0 ? p_node.hist[(idx - d) % ring] : 0.0f;
		p_node.hist[idx % ring] = x[i] + fb * wet;
	}
}

void CgameAudioGraph::process_block() {
	for (uint32_t n = 0; n < nodes.size(); n++) {
		process_node(*nodes[n]);
	}
	for (uint32_t n = 0; n < nodes.size(); n++) {
		if (nodes[n]->type == T_DELAY) {
			delay_write(*nodes[n]);
		}
	}
	const float *buf = nodes[output_node]->out;
	for (int i = 0; i < BLOCK; i++) {
		float v = buf[i];
		if (Math::is_nan(v) || Math::is_inf(v)) {
			v = 0.0f;
		}
		block_out[i] = CLAMP(v, -1.0f, 1.0f);
	}
	frame_counter += BLOCK;
}

void CgameAudioGraph::render(float *r_out, int p_frames) {
	if (!compiled) {
		for (int i = 0; i < p_frames; i++) {
			r_out[i] = 0.0f;
		}
		return;
	}
	int written = 0;
	while (written < p_frames) {
		if (block_pos >= BLOCK) {
			process_block();
			block_pos = 0;
		}
		const int n = MIN(BLOCK - block_pos, p_frames - written);
		for (int i = 0; i < n; i++) {
			r_out[written + i] = block_out[block_pos + i];
		}
		block_pos += n;
		written += n;
	}
}
