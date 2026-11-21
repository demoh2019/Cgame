/**************************************************************************/
/*  cgame_spatial_query.cpp                                               */
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

#include "cgame_spatial_query.h"

#include "cgame_utility_ai.h"

static bool _is_generator_type(const String &p_type) {
	return p_type == "grid" || p_type == "ring" || p_type == "navmesh" || p_type == "actors";
}

static bool _is_test_type(const String &p_type) {
	return p_type == "distance" || p_type == "dot" || p_type == "trace" || p_type == "path_length" || p_type == "custom";
}

// --- asset helpers ---------------------------------------------------------

Dictionary CgameSpatialQuery::new_asset(const String &p_name) {
	Dictionary a;
	a["name"] = p_name;
	a["generators"] = Array();
	a["tests"] = Array();
	a["combine"] = "weighted";
	a["max_results"] = 0;
	a["min_score"] = 0.0;
	return a;
}

Dictionary CgameSpatialQuery::make_generator(const String &p_type, const Dictionary &p_params) {
	Dictionary g;
	g["type"] = p_type;
	if (p_type == "grid") {
		g["half_extents"] = 10.0;
		g["spacing"] = 2.0;
	} else if (p_type == "ring") {
		g["radius"] = 8.0;
		g["count"] = 16;
	} else if (p_type == "navmesh") {
		g["radius"] = 10.0;
		g["count"] = 32;
	} else if (p_type == "actors") {
		g["actor_type"] = "";
		g["radius"] = 30.0;
	}
	const Array keys = p_params.keys();
	for (int i = 0; i < keys.size(); i++) {
		g[keys[i]] = p_params[keys[i]];
	}
	return g;
}

Dictionary CgameSpatialQuery::make_test(const String &p_type, const Dictionary &p_params) {
	Dictionary t;
	t["type"] = p_type;
	t["weight"] = 1.0;
	t["invert"] = false;
	t["curve"] = int(CgameUtilityAI::LINEAR);
	t["slope"] = 1.0;
	t["shift"] = 0.0;
	t["score"] = true;
	if (p_type == "distance") {
		t["min"] = 0.0;
		t["max"] = 20.0;
		t["to"] = "querier";
	} else if (p_type == "dot") {
		t["min"] = -1.0;
		t["max"] = 1.0;
		t["axis"] = "facing";
	} else if (p_type == "trace") {
		t["min"] = 0.0;
		t["max"] = 1.0;
	} else if (p_type == "path_length") {
		t["min"] = 0.0;
		t["max"] = 40.0;
	} else {
		t["min"] = 0.0;
		t["max"] = 1.0;
	}
	const Array keys = p_params.keys();
	for (int i = 0; i < keys.size(); i++) {
		t[keys[i]] = p_params[keys[i]];
	}
	return t;
}

int CgameSpatialQuery::add_generator(const Dictionary &p_asset, const Dictionary &p_generator) {
	Array arr = p_asset["generators"];
	arr.push_back(p_generator);
	return arr.size() - 1;
}

int CgameSpatialQuery::add_test(const Dictionary &p_asset, const Dictionary &p_test) {
	Array arr = p_asset["tests"];
	arr.push_back(p_test);
	return arr.size() - 1;
}

PackedStringArray CgameSpatialQuery::validate(const Dictionary &p_asset) {
	PackedStringArray errs;
	const Array gens = p_asset.get("generators", Array());
	const Array test_defs = p_asset.get("tests", Array());
	if (gens.is_empty()) {
		errs.push_back("query has no generators");
	}
	for (int i = 0; i < gens.size(); i++) {
		const Dictionary g = gens[i];
		if (!_is_generator_type(String(g.get("type", "")))) {
			errs.push_back(vformat("generator %d: unknown type '%s'", i, String(g.get("type", ""))));
		}
	}
	for (int i = 0; i < test_defs.size(); i++) {
		const Dictionary t = test_defs[i];
		if (!_is_test_type(String(t.get("type", "")))) {
			errs.push_back(vformat("test %d: unknown type '%s'", i, String(t.get("type", ""))));
		} else if (double(t.get("max", 1.0)) <= double(t.get("min", 0.0)) && bool(t.get("score", true))) {
			errs.push_back(vformat("test %d: max must be greater than min", i));
		}
	}
	return errs;
}

// --- execution -------------------------------------------------------------

Array CgameSpatialQuery::run(const Dictionary &p_asset, const Dictionary &p_context) {
	start(p_asset, p_context);
	step(MAX_ITEMS * 2);
	return result_items;
}

int CgameSpatialQuery::start(const Dictionary &p_asset, const Dictionary &p_context) {
	asset = p_asset;
	ctx = p_context;
	items.clear();
	result_items = Array();
	cursor = 0;
	steps = 0;
	tests.clear();
	stats.clear();
	filtered_by = Dictionary();
	debug_evaluated = 0;
	debug_passed = 0;
	started = true;
	const Array test_defs = p_asset.get("tests", Array());
	HashSet<String> used;
	for (int i = 0; i < test_defs.size(); i++) {
		Dictionary t = Dictionary(test_defs[i]).duplicate();
		String tn = String(t.get("name", vformat("%s_%d", String(t.get("type", "test")), i)));
		while (used.has(tn)) {
			tn += "_";
		}
		used.insert(tn);
		t["name"] = tn;
		tests.push_back(t);
		stats.push_back(Stat());
	}
	generator_debug = Array();
	const Array gens = p_asset.get("generators", Array());
	for (int i = 0; i < gens.size(); i++) {
		const Dictionary g = gens[i];
		const int before = items.size();
		_generate(g);
		Dictionary gd;
		gd["type"] = String(g.get("type", ""));
		gd["count"] = items.size() - before;
		generator_debug.push_back(gd);
	}
	done = false;
	if (items.is_empty()) {
		_finish();
	}
	return items.size();
}

bool CgameSpatialQuery::step(int p_budget_items) {
	if (done) {
		return true;
	}
	steps++;
	const int end = MIN(cursor + MAX(p_budget_items, 1), items.size());
	while (cursor < end) {
		_evaluate(items.write[cursor]);
		cursor++;
	}
	if (cursor >= items.size()) {
		_finish();
	}
	return done;
}

double CgameSpatialQuery::progress() const {
	return items.is_empty() ? 1.0 : double(cursor) / double(items.size());
}

Dictionary CgameSpatialQuery::get_debug() const {
	Dictionary d;
	if (!started) {
		return d;
	}
	d["name"] = String(asset.get("name", ""));
	d["generated"] = items.size();
	d["generators"] = generator_debug;
	d["evaluated"] = debug_evaluated;
	d["passed"] = debug_passed;
	d["steps"] = done ? steps : 0;
	d["filtered_by"] = filtered_by;
	Dictionary tdbg;
	if (done) {
		for (int i = 0; i < tests.size(); i++) {
			const Stat &st = stats[i];
			Dictionary entry;
			entry["evaluated"] = st.evaluated;
			entry["filtered"] = st.filtered;
			entry["min"] = st.evaluated > 0 ? st.min : 0.0;
			entry["max"] = st.evaluated > 0 ? st.max : 0.0;
			entry["mean"] = st.evaluated > 0 ? st.sum / double(st.evaluated) : 0.0;
			tdbg[String(tests[i]["name"])] = entry;
		}
	}
	d["tests"] = tdbg;
	return d;
}

PackedVector3Array CgameSpatialQuery::get_candidates() const {
	PackedVector3Array out;
	out.resize(items.size());
	for (int i = 0; i < items.size(); i++) {
		out.write[i] = items[i].position;
	}
	return out;
}

// --- internals -------------------------------------------------------------

void CgameSpatialQuery::_add_item(const Vector3 &p_pos, const Variant &p_actor, bool p_has_actor) {
	if (items.size() >= MAX_ITEMS) {
		return;
	}
	Item it;
	it.position = p_pos;
	it.index = items.size();
	it.actor = p_actor;
	it.has_actor = p_has_actor;
	items.push_back(it);
}

void CgameSpatialQuery::_generate(const Dictionary &p_gen) {
	const Vector3 origin = ctx.get("querier", Vector3());
	const String type = String(p_gen.get("type", ""));
	if (type == "grid") {
		const double half = MAX(double(p_gen.get("half_extents", 10.0)), 0.0);
		const double spacing = MAX(double(p_gen.get("spacing", 2.0)), 0.01);
		const int n = int(Math::floor(2.0 * half / spacing + 0.0001)) + 1;
		if (int64_t(n) * int64_t(n) > MAX_ITEMS) {
			return;
		}
		for (int ix = 0; ix < n; ix++) {
			for (int iz = 0; iz < n; iz++) {
				_add_item(origin + Vector3(-half + double(ix) * spacing, 0.0, -half + double(iz) * spacing));
			}
		}
	} else if (type == "ring") {
		const double radius = double(p_gen.get("radius", 8.0));
		const int cnt = CLAMP(int(p_gen.get("count", 16)), 0, 4096);
		for (int i = 0; i < cnt; i++) {
			const double a = Math::TAU * double(i) / double(cnt);
			_add_item(origin + Vector3(Math::cos(a), 0.0, Math::sin(a)) * radius);
		}
	} else if (type == "navmesh") {
		const Callable fn = ctx.get("navmesh_points", Callable());
		if (fn.is_valid()) {
			const Array pts = fn.call(origin, double(p_gen.get("radius", 10.0)), int(p_gen.get("count", 32)));
			for (int i = 0; i < pts.size(); i++) {
				if (Variant(pts[i]).get_type() == Variant::VECTOR3) {
					_add_item(pts[i]);
				}
			}
		}
	} else if (type == "actors") {
		const String want = String(p_gen.get("actor_type", ""));
		const double radius2 = double(p_gen.get("radius", 30.0));
		const Array actors = ctx.get("actors", Array());
		for (int i = 0; i < actors.size(); i++) {
			const Dictionary a = actors[i];
			if (!want.is_empty() && String(a.get("type", "")) != want) {
				continue;
			}
			const Vector3 p = a.get("position", Vector3());
			if (p.distance_to(origin) <= radius2) {
				_add_item(p, a.get("id", a.get("type", "")), true);
			}
		}
	}
}

double CgameSpatialQuery::_raw(const Dictionary &p_test, const Item &p_item) const {
	const Vector3 pos = p_item.position;
	const Vector3 origin = ctx.get("querier", Vector3());
	const Vector3 target = ctx.get("target", origin);
	const String type = String(p_test.get("type", ""));
	if (type == "distance") {
		const Vector3 ref = String(p_test.get("to", "querier")) == "target" ? target : origin;
		return pos.distance_to(ref);
	}
	if (type == "dot") {
		Vector3 axis = ctx.get("facing", Vector3(0, 0, -1));
		if (String(p_test.get("axis", "facing")) == "to_target") {
			axis = target - origin;
		}
		const Vector3 dir = pos - origin;
		if (axis.length_squared() < 1e-12 || dir.length_squared() < 1e-12) {
			return 0.0;
		}
		return axis.normalized().dot(dir.normalized());
	}
	if (type == "trace") {
		const Callable tr = ctx.get("trace", Callable());
		if (!tr.is_valid()) {
			return 1.0;
		}
		return bool(tr.call(origin, pos)) ? 1.0 : 0.0;
	}
	if (type == "path_length") {
		const Callable pl = ctx.get("path_length", Callable());
		if (!pl.is_valid()) {
			return pos.distance_to(origin);
		}
		const double plen = double(pl.call(origin, pos));
		return plen < 0.0 ? double(Math::INF) : plen;
	}
	Callable fn = p_test.get("fn", Callable());
	if (!fn.is_valid()) {
		const Dictionary custom = ctx.get("custom", Dictionary());
		fn = custom.get(String(p_test.get("callable", "")), Callable());
	}
	if (!fn.is_valid()) {
		return 0.0;
	}
	Dictionary item_dict;
	item_dict["position"] = p_item.position;
	item_dict["index"] = p_item.index;
	item_dict["score"] = p_item.score;
	item_dict["passed"] = p_item.passed;
	item_dict["tests"] = p_item.tests;
	if (p_item.has_actor) {
		item_dict["actor"] = p_item.actor;
	}
	return double(fn.call(pos, ctx, item_dict));
}

double CgameSpatialQuery::_normalise(const Dictionary &p_test, double p_raw) {
	const double lo = double(p_test.get("min", 0.0));
	const double hi = double(p_test.get("max", 1.0));
	double x = Math::is_inf(p_raw) ? 1.0 : CLAMP((p_raw - lo) / MAX(hi - lo, 0.000001), 0.0, 1.0);
	if (bool(p_test.get("invert", false))) {
		x = 1.0 - x;
	}
	return CgameUtilityAI::curve(int(p_test.get("curve", int(CgameUtilityAI::LINEAR))), x, double(p_test.get("slope", 1.0)), double(p_test.get("shift", 0.0)));
}

void CgameSpatialQuery::_evaluate(Item &r_item) {
	double weighted = 0.0;
	double weight_sum = 0.0;
	PackedFloat32Array scores;
	for (int i = 0; i < tests.size(); i++) {
		const Dictionary &t = tests[i];
		const String tn = String(t["name"]);
		const double raw = _raw(t, r_item);
		Stat &st = stats.write[i];
		st.evaluated++;
		if (!Math::is_inf(raw)) {
			st.min = MIN(st.min, raw);
			st.max = MAX(st.max, raw);
			st.sum += raw;
		}
		const bool failed = (t.has("filter_min") && raw < double(t["filter_min"])) || (t.has("filter_max") && raw > double(t["filter_max"]));
		if (failed) {
			st.filtered++;
			filtered_by[tn] = int(filtered_by.get(tn, 0)) + 1;
			r_item.passed = false;
			Dictionary entry;
			entry["raw"] = raw;
			entry["score"] = 0.0;
			entry["filtered"] = true;
			r_item.tests[tn] = entry;
			break;
		}
		const double s = _normalise(t, raw);
		Dictionary entry;
		entry["raw"] = raw;
		entry["score"] = s;
		r_item.tests[tn] = entry;
		if (bool(t.get("score", true))) {
			const double w = MAX(double(t.get("weight", 1.0)), 0.0);
			weighted += w * s;
			weight_sum += w;
			scores.push_back(s);
		}
	}
	debug_evaluated++;
	if (!r_item.passed) {
		return;
	}
	if (scores.is_empty()) {
		r_item.score = 1.0;
	} else if (String(asset.get("combine", "weighted")) == "iaus") {
		r_item.score = CgameUtilityAI::combine(scores);
	} else {
		r_item.score = weight_sum > 0.0 ? weighted / weight_sum : 0.0;
	}
	debug_passed++;
}

namespace {
struct RankedItem {
	double score;
	int index;
};

struct RankedItemLess {
	_FORCE_INLINE_ bool operator()(const RankedItem &p_a, const RankedItem &p_b) const {
		if (p_a.score != p_b.score) {
			return p_a.score > p_b.score;
		}
		return p_a.index < p_b.index;
	}
};
} // namespace

void CgameSpatialQuery::_finish() {
	done = true;
	const double min_score = double(asset.get("min_score", 0.0));
	Vector<RankedItem> ranked;
	for (int i = 0; i < items.size(); i++) {
		if (items[i].passed && items[i].score >= min_score) {
			ranked.push_back({ items[i].score, i });
		}
	}
	ranked.sort_custom<RankedItemLess>();
	const int cap = int(asset.get("max_results", 0));
	int count = ranked.size();
	if (cap > 0 && count > cap) {
		count = cap;
	}
	Array out;
	for (int i = 0; i < count; i++) {
		const Item &it = items[ranked[i].index];
		Dictionary d;
		d["position"] = it.position;
		d["index"] = it.index;
		d["score"] = it.score;
		d["passed"] = it.passed;
		d["tests"] = it.tests;
		if (it.has_actor) {
			d["actor"] = it.actor;
		}
		out.push_back(d);
	}
	result_items = out;
}

void CgameSpatialQuery::_bind_methods() {
	ClassDB::bind_static_method("CgameSpatialQuery", D_METHOD("new_asset", "asset_name"), &CgameSpatialQuery::new_asset, DEFVAL("query"));
	ClassDB::bind_static_method("CgameSpatialQuery", D_METHOD("make_generator", "type", "params"), &CgameSpatialQuery::make_generator, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("CgameSpatialQuery", D_METHOD("make_test", "type", "params"), &CgameSpatialQuery::make_test, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("CgameSpatialQuery", D_METHOD("add_generator", "asset", "generator"), &CgameSpatialQuery::add_generator);
	ClassDB::bind_static_method("CgameSpatialQuery", D_METHOD("add_test", "asset", "test"), &CgameSpatialQuery::add_test);
	ClassDB::bind_static_method("CgameSpatialQuery", D_METHOD("validate", "asset"), &CgameSpatialQuery::validate);

	ClassDB::bind_method(D_METHOD("run", "asset", "context"), &CgameSpatialQuery::run);
	ClassDB::bind_method(D_METHOD("start", "asset", "context"), &CgameSpatialQuery::start);
	ClassDB::bind_method(D_METHOD("step", "budget_items"), &CgameSpatialQuery::step);
	ClassDB::bind_method(D_METHOD("is_done"), &CgameSpatialQuery::is_done);
	ClassDB::bind_method(D_METHOD("progress"), &CgameSpatialQuery::progress);
	ClassDB::bind_method(D_METHOD("results"), &CgameSpatialQuery::get_results);
	ClassDB::bind_method(D_METHOD("debug"), &CgameSpatialQuery::get_debug);
	ClassDB::bind_method(D_METHOD("get_candidates"), &CgameSpatialQuery::get_candidates);

	BIND_CONSTANT(MAX_ITEMS);
}
