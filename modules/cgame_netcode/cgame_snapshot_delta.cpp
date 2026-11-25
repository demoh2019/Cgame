/**************************************************************************/
/*  cgame_snapshot_delta.cpp                                              */
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

#include "cgame_snapshot_delta.h"

#include "core/math/vector2.h"
#include "core/math/vector3.h"
#include "core/object/class_db.h"
#include "core/variant/array.h"

Variant CgameSnapshotDelta::_copy(const Variant &p_v) {
	if (p_v.get_type() == Variant::DICTIONARY) {
		return Dictionary(p_v).duplicate(true);
	}
	if (p_v.get_type() == Variant::ARRAY) {
		return Array(p_v).duplicate(true);
	}
	return p_v;
}

bool CgameSnapshotDelta::_same(const Variant &p_a, const Variant &p_b, double p_tol) {
	if (p_a.get_type() != p_b.get_type()) {
		return false;
	}
	if (p_tol > 0.0) {
		switch (p_a.get_type()) {
			case Variant::FLOAT:
				return Math::abs(double(p_a) - double(p_b)) <= p_tol;
			case Variant::VECTOR3:
				return Vector3(p_a).distance_to(Vector3(p_b)) <= p_tol;
			case Variant::VECTOR2:
				return Vector2(p_a).distance_to(Vector2(p_b)) <= p_tol;
			default:
				break;
		}
	}
	return p_a == p_b;
}

Dictionary CgameSnapshotDelta::diff(const Dictionary &p_baseline, const Dictionary &p_current, const Dictionary &p_tolerances) {
	Dictionary changed;
	Dictionary added;
	PackedInt64Array removed;
	Dictionary dropped;

	for (const KeyValue<Variant, Variant> &kv : p_current) {
		const Variant &id = kv.key;
		Dictionary cur_ent = kv.value;
		if (!p_baseline.has(id)) {
			added[id] = _copy(cur_ent);
			continue;
		}
		Dictionary base_ent = p_baseline[id];
		Dictionary fields;
		for (const KeyValue<Variant, Variant> &fv : cur_ent) {
			if (base_ent.has(fv.key)) {
				double tol = double(p_tolerances.get(fv.key, 0.0));
				if (_same(base_ent[fv.key], fv.value, tol)) {
					continue;
				}
			}
			fields[fv.key] = _copy(fv.value);
		}
		if (!fields.is_empty()) {
			changed[id] = fields;
		}
		Array gone;
		for (const KeyValue<Variant, Variant> &bv : base_ent) {
			if (!cur_ent.has(bv.key)) {
				gone.push_back(bv.key);
			}
		}
		if (!gone.is_empty()) {
			dropped[id] = gone;
		}
	}
	for (const KeyValue<Variant, Variant> &kv : p_baseline) {
		if (!p_current.has(kv.key)) {
			removed.push_back(int64_t(kv.key));
		}
	}

	Dictionary out;
	out["changed"] = changed;
	out["added"] = added;
	out["removed"] = removed;
	if (!dropped.is_empty()) {
		out["dropped"] = dropped;
	}
	return out;
}

Dictionary CgameSnapshotDelta::apply(const Dictionary &p_baseline, const Dictionary &p_delta) {
	Dictionary out;
	const PackedInt64Array removed = p_delta.get("removed", PackedInt64Array());
	Dictionary retired;
	for (int64_t id : removed) {
		retired[id] = true;
	}
	// Do not deep-copy entities which have left the interest set.
	// Preserve the original order of surviving entities.
	for (const KeyValue<Variant, Variant> &kv : p_baseline) {
		if (!retired.has(kv.key)) {
			out[kv.key] = _copy(kv.value);
		}
	}
	Dictionary added = p_delta.get("added", Dictionary());
	for (const KeyValue<Variant, Variant> &kv : added) {
		out[kv.key] = _copy(kv.value);
	}
	Dictionary changed = p_delta.get("changed", Dictionary());
	for (const KeyValue<Variant, Variant> &kv : changed) {
		if (!out.has(kv.key)) {
			continue;
		}
		Dictionary ent = out[kv.key];
		Dictionary fields = kv.value;
		for (const KeyValue<Variant, Variant> &fv : fields) {
			ent[fv.key] = _copy(fv.value);
		}
	}
	Dictionary dropped = p_delta.get("dropped", Dictionary());
	for (const KeyValue<Variant, Variant> &kv : dropped) {
		if (!out.has(kv.key)) {
			continue;
		}
		Dictionary ent = out[kv.key];
		Array gone = kv.value;
		for (int i = 0; i < gone.size(); i++) {
			ent.erase(gone[i]);
		}
	}
	return out;
}

bool CgameSnapshotDelta::is_empty(const Dictionary &p_delta) {
	Dictionary changed = p_delta.get("changed", Dictionary());
	Dictionary added = p_delta.get("added", Dictionary());
	PackedInt64Array removed = p_delta.get("removed", PackedInt64Array());
	Dictionary dropped = p_delta.get("dropped", Dictionary());
	return changed.is_empty() && added.is_empty() && removed.is_empty() && dropped.is_empty();
}

void CgameSnapshotDelta::_bind_methods() {
	ClassDB::bind_static_method("CgameSnapshotDelta", D_METHOD("diff", "baseline", "current", "tolerances"), &CgameSnapshotDelta::diff, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("CgameSnapshotDelta", D_METHOD("apply", "baseline", "delta"), &CgameSnapshotDelta::apply);
	ClassDB::bind_static_method("CgameSnapshotDelta", D_METHOD("is_empty", "delta"), &CgameSnapshotDelta::is_empty);
}
