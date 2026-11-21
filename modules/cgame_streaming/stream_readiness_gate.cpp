/**************************************************************************/
/*  stream_readiness_gate.cpp                                             */
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

#include "stream_readiness_gate.h"

#include "core/object/class_db.h"
#include "core/os/os.h"
#include "servers/navigation_3d/navigation_server_3d.h"
#include "servers/physics_3d/physics_server_3d.h"

static const int STAGE_ORDER[4] = {
	StreamReadinessGate::STAGE_DATA_LOADED,
	StreamReadinessGate::STAGE_GPU_UPLOADED,
	StreamReadinessGate::STAGE_PHYSICS_READY,
	StreamReadinessGate::STAGE_NAVMESH_READY,
};

int StreamReadinessGate::_effective(int p_marked) {
	int e = p_marked & STAGE_DATA_LOADED;
	if (e != 0) {
		e |= p_marked & (STAGE_GPU_UPLOADED | STAGE_PHYSICS_READY);
	}
	if ((e & STAGE_PHYSICS_READY) != 0) {
		e |= p_marked & STAGE_NAVMESH_READY;
	}
	return e;
}

bool StreamReadinessGate::_prereqs_met(int p_stage, int p_eff) {
	switch (p_stage) {
		case STAGE_GPU_UPLOADED:
		case STAGE_PHYSICS_READY:
			return (p_eff & STAGE_DATA_LOADED) != 0;
		case STAGE_NAVMESH_READY:
			return (p_eff & STAGE_PHYSICS_READY) != 0;
		default:
			return true;
	}
}

int StreamReadinessGate::_waiting(int p_eff) {
	for (int stage : STAGE_ORDER) {
		if ((p_eff & stage) == 0 && _prereqs_met(stage, p_eff)) {
			return stage;
		}
	}
	return 0;
}

String StreamReadinessGate::_stage_name(int p_stage) {
	switch (p_stage) {
		case STAGE_DATA_LOADED:
			return "data_loaded";
		case STAGE_GPU_UPLOADED:
			return "gpu_uploaded";
		case STAGE_PHYSICS_READY:
			return "physics_ready";
		case STAGE_NAVMESH_READY:
			return "navmesh_ready";
		default:
			return "";
	}
}

void StreamReadinessGate::set_default_timeout(double p_seconds) {
	default_timeout = p_seconds;
}

double StreamReadinessGate::get_default_timeout() const {
	return default_timeout;
}

void StreamReadinessGate::set_stage_timeouts(const Dictionary &p_timeouts) {
	stage_timeouts = p_timeouts;
}

Dictionary StreamReadinessGate::get_stage_timeouts() const {
	return stage_timeouts;
}

void StreamReadinessGate::set_on_stuck(const Callable &p_callback) {
	on_stuck = p_callback;
}

Callable StreamReadinessGate::get_on_stuck() const {
	return on_stuck;
}

void StreamReadinessGate::set_on_reveal(const Callable &p_callback) {
	on_reveal = p_callback;
}

Callable StreamReadinessGate::get_on_reveal() const {
	return on_reveal;
}

void StreamReadinessGate::set_max_warmup_attempts(int p_attempts) {
	max_warmup_attempts = p_attempts;
}

int StreamReadinessGate::get_max_warmup_attempts() const {
	return max_warmup_attempts;
}

TypedArray<Vector2i> StreamReadinessGate::get_warmup_failed() const {
	return warmup_failed;
}

TypedArray<Dictionary> StreamReadinessGate::get_stuck_log() const {
	return stuck_log;
}

void StreamReadinessGate::set_probe(int p_stage, const Callable &p_probe) {
	probes[p_stage] = p_probe;
}

void StreamReadinessGate::set_auto_warmup(const Callable &p_bake) {
	auto_bake = p_bake;
}

void StreamReadinessGate::begin(const Vector2i &p_cell, double p_now) {
	now = p_now;
	if (cells.has(p_cell)) {
		return;
	}
	CellState c;
	c.since = p_now;
	cells[p_cell] = c;
}

void StreamReadinessGate::release(const Vector2i &p_cell) {
	cells.erase(p_cell);
	for (int i = (int)warmups.size() - 1; i >= 0; i--) {
		if (warmups[i].cell == p_cell) {
			warmups.remove_at(i);
		}
	}
}

bool StreamReadinessGate::is_tracked(const Vector2i &p_cell) const {
	return cells.has(p_cell);
}

void StreamReadinessGate::mark(const Vector2i &p_cell, int p_stage, double p_now) {
	if (p_now >= 0.0) {
		now = p_now;
	}
	if (!cells.has(p_cell)) {
		begin(p_cell, now);
	}
	CellState &c = cells[p_cell];
	c.marked |= p_stage;
	_refresh(p_cell, c);
}

int StreamReadinessGate::ready_mask(const Vector2i &p_cell) const {
	HashMap<Vector2i, CellState>::ConstIterator it = cells.find(p_cell);
	if (!it) {
		return 0;
	}
	return _effective(it->value.marked);
}

bool StreamReadinessGate::is_stage_ready(const Vector2i &p_cell, int p_stage) const {
	return (ready_mask(p_cell) & p_stage) != 0;
}

bool StreamReadinessGate::is_revealable(const Vector2i &p_cell) const {
	return ready_mask(p_cell) == STAGE_ALL;
}

bool StreamReadinessGate::is_revealed(const Vector2i &p_cell) const {
	HashMap<Vector2i, CellState>::ConstIterator it = cells.find(p_cell);
	return it && it->value.revealed;
}

int StreamReadinessGate::waiting_stage(const Vector2i &p_cell) const {
	return _waiting(ready_mask(p_cell));
}

void StreamReadinessGate::_refresh(const Vector2i &p_cell, CellState &p_state) {
	int eff = _effective(p_state.marked);
	if (eff != p_state.last_eff) {
		p_state.last_eff = eff;
		p_state.since = now;
	}
	if (auto_bake.is_valid() && (eff & STAGE_PHYSICS_READY) != 0 && (eff & STAGE_NAVMESH_READY) == 0 && !p_state.warmup_queued) {
		warmup_navmesh(p_cell, auto_bake);
	}
}

TypedArray<Vector2i> StreamReadinessGate::update(double p_now) {
	now = p_now;
	TypedArray<Vector2i> out;
	LocalVector<Vector2i> keys;
	for (const KeyValue<Vector2i, CellState> &kv : cells) {
		keys.push_back(kv.key);
	}
	for (const Vector2i &cell : keys) {
		if (!cells.has(cell)) {
			continue;
		}
		int eff = _effective(cells[cell].marked);
		for (int stage : STAGE_ORDER) {
			if ((eff & stage) != 0 || !probes.has(stage) || !_prereqs_met(stage, eff)) {
				continue;
			}
			Callable probe = probes[stage];
			if (probe.is_valid()) {
				Variant arg = cell;
				const Variant *argp = &arg;
				Variant ret;
				Callable::CallError err;
				probe.callp(&argp, 1, ret, err);
				if (err.error == Callable::CallError::CALL_OK && (bool)ret && cells.has(cell)) {
					cells[cell].marked |= stage;
					eff = _effective(cells[cell].marked);
				}
			}
		}
		if (!cells.has(cell)) {
			continue;
		}
		CellState &c = cells[cell];
		_refresh(cell, c);
		if (eff == STAGE_ALL && !cells[cell].revealed) {
			cells[cell].revealed = true;
			out.push_back(cell);
			if (on_reveal.is_valid()) {
				on_reveal.call(cell);
			}
		}
	}
	_report_stuck(p_now);
	return out;
}

void StreamReadinessGate::_report_stuck(double p_now) {
	LocalVector<Vector2i> keys;
	for (const KeyValue<Vector2i, CellState> &kv : cells) {
		keys.push_back(kv.key);
	}
	for (const Vector2i &cell : keys) {
		if (!cells.has(cell)) {
			continue;
		}
		CellState &c = cells[cell];
		if (c.revealed) {
			continue;
		}
		int w = _waiting(_effective(c.marked));
		if (w == 0 || (c.stuck_reported & w) != 0) {
			continue;
		}
		double limit = default_timeout;
		if (stage_timeouts.has(w)) {
			limit = stage_timeouts[w];
		}
		double waited = p_now - c.since;
		if (waited >= limit) {
			c.stuck_reported |= w;
			Dictionary rep;
			rep["cell"] = cell;
			rep["stage"] = w;
			rep["stage_name"] = _stage_name(w);
			rep["waited"] = waited;
			stuck_log.push_back(rep);
			if (on_stuck.is_valid()) {
				on_stuck.call(rep);
			}
		}
	}
}

void StreamReadinessGate::warmup_navmesh(const Vector2i &p_cell, const Callable &p_bake) {
	if (!cells.has(p_cell)) {
		begin(p_cell, now);
	}
	cells[p_cell].warmup_queued = true;
	Warmup w;
	w.id = warmup_id_counter++;
	w.cell = p_cell;
	w.bake = p_bake;
	warmups.push_back(w);
}

int StreamReadinessGate::pending_warmups() const {
	return warmups.size();
}

int StreamReadinessGate::process_warmup(int p_max_count, int64_t p_max_usec) {
	uint64_t t0 = OS::get_singleton()->get_ticks_usec();
	int ran = 0;
	LocalVector<Warmup> snapshot(warmups);
	for (const Warmup &item : snapshot) {
		if (ran >= p_max_count || (p_max_usec > 0 && (int64_t)(OS::get_singleton()->get_ticks_usec() - t0) >= p_max_usec)) {
			break;
		}
		if ((ready_mask(item.cell) & STAGE_PHYSICS_READY) == 0) {
			continue;
		}
		ran++;
		bool ok = false;
		if (item.bake.is_valid()) {
			Variant arg = item.cell;
			const Variant *argp = &arg;
			Variant ret;
			Callable::CallError err;
			item.bake.callp(&argp, 1, ret, err);
			ok = err.error == Callable::CallError::CALL_OK && (bool)ret;
		}
		int idx = -1;
		for (uint32_t i = 0; i < warmups.size(); i++) {
			if (warmups[i].id == item.id) {
				idx = i;
				break;
			}
		}
		if (ok) {
			if (idx >= 0) {
				warmups.remove_at(idx);
			}
			mark(item.cell, STAGE_NAVMESH_READY);
			continue;
		}
		if (idx >= 0) {
			warmups[idx].attempts++;
			if (warmups[idx].attempts >= max_warmup_attempts) {
				warmups.remove_at(idx);
				warmup_failed.push_back(item.cell);
			}
		}
	}
	return ran;
}

bool StreamReadinessGate::probe_rids_valid(const Array &p_rids) {
	for (int i = 0; i < p_rids.size(); i++) {
		const Variant &v = p_rids[i];
		if (v.get_type() != Variant::RID || !((RID)v).is_valid()) {
			return false;
		}
	}
	return !p_rids.is_empty();
}

bool StreamReadinessGate::probe_body_shapes(const RID &p_body, int p_min_shapes) {
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	return ps && p_body.is_valid() && ps->body_get_shape_count(p_body) >= p_min_shapes;
}

bool StreamReadinessGate::probe_nav_region(const RID &p_region) {
	NavigationServer3D *ns = NavigationServer3D::get_singleton();
	return ns && p_region.is_valid() && ns->region_get_iteration_id(p_region) > 0;
}

void StreamReadinessGate::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_default_timeout", "seconds"), &StreamReadinessGate::set_default_timeout);
	ClassDB::bind_method(D_METHOD("get_default_timeout"), &StreamReadinessGate::get_default_timeout);
	ClassDB::bind_method(D_METHOD("set_stage_timeouts", "timeouts"), &StreamReadinessGate::set_stage_timeouts);
	ClassDB::bind_method(D_METHOD("get_stage_timeouts"), &StreamReadinessGate::get_stage_timeouts);
	ClassDB::bind_method(D_METHOD("set_on_stuck", "callback"), &StreamReadinessGate::set_on_stuck);
	ClassDB::bind_method(D_METHOD("get_on_stuck"), &StreamReadinessGate::get_on_stuck);
	ClassDB::bind_method(D_METHOD("set_on_reveal", "callback"), &StreamReadinessGate::set_on_reveal);
	ClassDB::bind_method(D_METHOD("get_on_reveal"), &StreamReadinessGate::get_on_reveal);
	ClassDB::bind_method(D_METHOD("set_max_warmup_attempts", "attempts"), &StreamReadinessGate::set_max_warmup_attempts);
	ClassDB::bind_method(D_METHOD("get_max_warmup_attempts"), &StreamReadinessGate::get_max_warmup_attempts);
	ClassDB::bind_method(D_METHOD("get_warmup_failed"), &StreamReadinessGate::get_warmup_failed);
	ClassDB::bind_method(D_METHOD("get_stuck_log"), &StreamReadinessGate::get_stuck_log);

	ClassDB::bind_method(D_METHOD("set_probe", "stage", "probe"), &StreamReadinessGate::set_probe);
	ClassDB::bind_method(D_METHOD("set_auto_warmup", "bake"), &StreamReadinessGate::set_auto_warmup);
	ClassDB::bind_method(D_METHOD("begin", "cell", "now"), &StreamReadinessGate::begin);
	ClassDB::bind_method(D_METHOD("release", "cell"), &StreamReadinessGate::release);
	ClassDB::bind_method(D_METHOD("is_tracked", "cell"), &StreamReadinessGate::is_tracked);
	ClassDB::bind_method(D_METHOD("mark", "cell", "stage", "now"), &StreamReadinessGate::mark, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("ready_mask", "cell"), &StreamReadinessGate::ready_mask);
	ClassDB::bind_method(D_METHOD("is_stage_ready", "cell", "stage"), &StreamReadinessGate::is_stage_ready);
	ClassDB::bind_method(D_METHOD("is_revealable", "cell"), &StreamReadinessGate::is_revealable);
	ClassDB::bind_method(D_METHOD("is_revealed", "cell"), &StreamReadinessGate::is_revealed);
	ClassDB::bind_method(D_METHOD("waiting_stage", "cell"), &StreamReadinessGate::waiting_stage);
	ClassDB::bind_method(D_METHOD("update", "now"), &StreamReadinessGate::update);
	ClassDB::bind_method(D_METHOD("warmup_navmesh", "cell", "bake"), &StreamReadinessGate::warmup_navmesh);
	ClassDB::bind_method(D_METHOD("pending_warmups"), &StreamReadinessGate::pending_warmups);
	ClassDB::bind_method(D_METHOD("process_warmup", "max_count", "max_usec"), &StreamReadinessGate::process_warmup, DEFVAL(0));

	ClassDB::bind_static_method("StreamReadinessGate", D_METHOD("probe_rids_valid", "rids"), &StreamReadinessGate::probe_rids_valid);
	ClassDB::bind_static_method("StreamReadinessGate", D_METHOD("probe_body_shapes", "body", "min_shapes"), &StreamReadinessGate::probe_body_shapes, DEFVAL(1));
	ClassDB::bind_static_method("StreamReadinessGate", D_METHOD("probe_nav_region", "region"), &StreamReadinessGate::probe_nav_region);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "default_timeout", PROPERTY_HINT_RANGE, "0,3600,0.01,or_greater,suffix:s"), "set_default_timeout", "get_default_timeout");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "stage_timeouts"), "set_stage_timeouts", "get_stage_timeouts");
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "on_stuck"), "set_on_stuck", "get_on_stuck");
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "on_reveal"), "set_on_reveal", "get_on_reveal");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_warmup_attempts", PROPERTY_HINT_RANGE, "1,100,1,or_greater"), "set_max_warmup_attempts", "get_max_warmup_attempts");

	BIND_ENUM_CONSTANT(STAGE_DATA_LOADED);
	BIND_ENUM_CONSTANT(STAGE_GPU_UPLOADED);
	BIND_ENUM_CONSTANT(STAGE_PHYSICS_READY);
	BIND_ENUM_CONSTANT(STAGE_NAVMESH_READY);
	BIND_CONSTANT(STAGE_ALL);
}
