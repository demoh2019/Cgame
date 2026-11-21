/**************************************************************************/
/*  stream_readiness_gate.h                                               */
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

#include "core/math/vector2i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"

// Unified readiness gate for streamed cells (data, GPU, physics, navmesh).
class StreamReadinessGate : public RefCounted {
	GDCLASS(StreamReadinessGate, RefCounted);

public:
	enum Stage {
		STAGE_DATA_LOADED = 1,
		STAGE_GPU_UPLOADED = 2,
		STAGE_PHYSICS_READY = 4,
		STAGE_NAVMESH_READY = 8,
	};
	static constexpr int STAGE_ALL = 15;

private:
	struct CellState {
		int marked = 0;
		double since = 0.0;
		int last_eff = 0;
		int stuck_reported = 0;
		bool revealed = false;
		bool warmup_queued = false;
	};

	struct Warmup {
		int64_t id = 0;
		Vector2i cell;
		Callable bake;
		int attempts = 0;
	};

	double default_timeout = 10.0;
	Dictionary stage_timeouts;
	Callable on_stuck;
	Callable on_reveal;
	int max_warmup_attempts = 3;
	TypedArray<Vector2i> warmup_failed;
	TypedArray<Dictionary> stuck_log;

	HashMap<Vector2i, CellState> cells;
	HashMap<int, Callable> probes;
	LocalVector<Warmup> warmups;
	Callable auto_bake;
	double now = 0.0;
	int64_t warmup_id_counter = 0;

	static int _effective(int p_marked);
	static bool _prereqs_met(int p_stage, int p_eff);
	static int _waiting(int p_eff);
	static String _stage_name(int p_stage);
	void _refresh(const Vector2i &p_cell, CellState &p_state);
	void _report_stuck(double p_now);

protected:
	static void _bind_methods();

public:
	void set_default_timeout(double p_seconds);
	double get_default_timeout() const;
	void set_stage_timeouts(const Dictionary &p_timeouts);
	Dictionary get_stage_timeouts() const;
	void set_on_stuck(const Callable &p_callback);
	Callable get_on_stuck() const;
	void set_on_reveal(const Callable &p_callback);
	Callable get_on_reveal() const;
	void set_max_warmup_attempts(int p_attempts);
	int get_max_warmup_attempts() const;
	TypedArray<Vector2i> get_warmup_failed() const;
	TypedArray<Dictionary> get_stuck_log() const;

	void set_probe(int p_stage, const Callable &p_probe);
	void set_auto_warmup(const Callable &p_bake);
	void begin(const Vector2i &p_cell, double p_now);
	void release(const Vector2i &p_cell);
	bool is_tracked(const Vector2i &p_cell) const;
	void mark(const Vector2i &p_cell, int p_stage, double p_now = -1.0);
	int ready_mask(const Vector2i &p_cell) const;
	bool is_stage_ready(const Vector2i &p_cell, int p_stage) const;
	bool is_revealable(const Vector2i &p_cell) const;
	bool is_revealed(const Vector2i &p_cell) const;
	int waiting_stage(const Vector2i &p_cell) const;
	TypedArray<Vector2i> update(double p_now);
	void warmup_navmesh(const Vector2i &p_cell, const Callable &p_bake);
	int pending_warmups() const;
	int process_warmup(int p_max_count, int64_t p_max_usec = 0);

	static bool probe_rids_valid(const Array &p_rids);
	static bool probe_body_shapes(const RID &p_body, int p_min_shapes = 1);
	static bool probe_nav_region(const RID &p_region);
};

VARIANT_ENUM_CAST(StreamReadinessGate::Stage);
