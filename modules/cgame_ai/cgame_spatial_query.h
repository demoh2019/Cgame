/**************************************************************************/
/*  cgame_spatial_query.h                                                 */
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

#include "cgame_ai_common.h"

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"

// EQS-style spatial query graph: generators -> tests (filters + scorers) ->
// ranked items. The asset is a plain Dictionary (serialisable); Callables are
// supplied through the context. Result entries use the same keys (position,
// index, score) as EnvironmentQuery3D results so both can feed the same
// consumers, and generated candidates can be exported with get_candidates().
class CgameSpatialQuery : public RefCounted {
	GDCLASS(CgameSpatialQuery, RefCounted);

public:
	enum {
		MAX_ITEMS = 65536,
	};

private:
	struct Item {
		Vector3 position;
		int index = 0;
		double score = 0.0;
		bool passed = true;
		Dictionary tests;
		Variant actor;
		bool has_actor = false;
	};

	struct Stat {
		int64_t evaluated = 0;
		int64_t filtered = 0;
		double min = Math::INF;
		double max = -Math::INF;
		double sum = 0.0;
	};

	Dictionary asset;
	Dictionary ctx;
	Vector<Item> items;
	int cursor = 0;
	bool done = true;
	bool started = false;
	int steps = 0;
	Array result_items;
	Vector<Dictionary> tests;
	Vector<Stat> stats;
	Array generator_debug;
	Dictionary filtered_by;
	int64_t debug_evaluated = 0;
	int64_t debug_passed = 0;

	void _add_item(const Vector3 &p_pos, const Variant &p_actor = Variant(), bool p_has_actor = false);
	void _generate(const Dictionary &p_gen);
	double _raw(const Dictionary &p_test, const Item &p_item) const;
	static double _normalise(const Dictionary &p_test, double p_raw);
	void _evaluate(Item &r_item);
	void _finish();

protected:
	static void _bind_methods();

public:
	static Dictionary new_asset(const String &p_name = "query");
	static Dictionary make_generator(const String &p_type, const Dictionary &p_params = Dictionary());
	static Dictionary make_test(const String &p_type, const Dictionary &p_params = Dictionary());
	static int add_generator(const Dictionary &p_asset, const Dictionary &p_generator);
	static int add_test(const Dictionary &p_asset, const Dictionary &p_test);
	static PackedStringArray validate(const Dictionary &p_asset);

	Array run(const Dictionary &p_asset, const Dictionary &p_context);
	int start(const Dictionary &p_asset, const Dictionary &p_context);
	bool step(int p_budget_items);
	bool is_done() const { return done; }
	double progress() const;
	Array get_results() const { return result_items; }
	Dictionary get_debug() const;
	PackedVector3Array get_candidates() const;
};
