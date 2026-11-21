/**************************************************************************/
/*  vfx_bindings.h                                                        */
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

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"

// A timed list of effects {t, effect, offset, params}. advance(dt) fires the entries whose time
// has passed through a spawn callable: spawn.call(effect: String, position: Vector3, params: Dictionary).
class VFXSequence : public RefCounted {
	GDCLASS(VFXSequence, RefCounted);

	Array entries;
	Vector3 origin;
	Dictionary base_params;
	Callable spawn;
	double time = 0.0;
	double duration = 0.0;
	int fired = 0;
	int cursor = 0;

protected:
	static void _bind_methods();

public:
	void configure(const Array &p_entries, const Callable &p_spawn, const Vector3 &p_origin, const Dictionary &p_params);
	int advance(double p_dt);
	bool is_finished() const { return cursor >= entries.size(); }
	double get_time() const { return time; }
	double get_duration() const { return duration; }
	int get_fired_count() const { return fired; }
	Vector3 get_origin() const { return origin; }
};

// Data registry mapping gameplay event types ("hit", "lightning_struck", ...) to VFX presets or
// graph assets, with parameter mapping from the event payload, plus named VFX sequences.
// Spawning is delegated to a Callable so the registry stays engine-agnostic; wire it to
// VFXPresets.spawn(), a GameplayCueQueue consumer, or any other effect factory.
class VFXBindings : public RefCounted {
	GDCLASS(VFXBindings, RefCounted);

	HashMap<String, Array> bindings; // event type -> Array of binding specs
	HashMap<String, Array> sequences; // name -> Array of entries
	Vector<Ref<VFXSequence>> active;
	HashMap<String, double> last_fire;
	double clock = 0.0;

protected:
	static void _bind_methods();

public:
	// spec keys: effect (String), offset (Vector3), params {name: const | {from, scale, offset,
	// default, min, max}}, min_interval (seconds), sequence (name of a registered sequence).
	void register_binding(const String &p_event_type, const Dictionary &p_spec);
	void register_sequence(const String &p_name, const Array &p_entries);
	bool has_binding(const String &p_event_type) const { return bindings.has(p_event_type); }
	int get_binding_count() const;
	Ref<VFXSequence> make_sequence(const String &p_name, const Callable &p_spawn, const Vector3 &p_origin = Vector3(), const Dictionary &p_params = Dictionary()) const;
	static Dictionary map_params(const Dictionary &p_mapping, const Dictionary &p_payload);
	// Dispatches an event {type, payload, position}; returns how many effects/sequences started.
	int handle(const Dictionary &p_event, const Callable &p_spawn);
	// Feeds events drained from GameplayCueQueue.take_events() (gameplay_fx module) into handle().
	// Each cue {tag, event, stacks, magnitude, priority, count} becomes an event whose type is
	// the cue tag ("started"/"executed") or "<tag>:stopped" ("stopped"); "updated" cues are
	// skipped. The cue fields are available to bindings as payload values, and every cue is
	// placed at p_position. Returns the total number of effects/sequences started.
	int handle_cue_events(const Array &p_cue_events, const Callable &p_spawn, const Vector3 &p_position = Vector3());
	// Advances the clock and all sequences started by handle().
	void tick(double p_dt);
	int get_active_sequence_count() const { return active.size(); }
	double get_clock() const { return clock; }
	void clear();
};
