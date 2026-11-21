/**************************************************************************/
/*  cgame_replay_recorder.h                                               */
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

#include "cgame_server_macros.h"

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Deterministic session recorder / replayer for an authoritative game server.
//
// Records the inputs of a session (seed, world seed, initial players and, per tick, the delta plus
// every command) and re-runs them on a fresh server, returning a state hash per tick. Two runs of
// the same recording must produce identical hash lists; the first differing tick (see compare)
// pinpoints a determinism bug or a tampered recording. The state hash is 64-bit FNV-1a.
//
// Only methods named "cmd_*" (client commands) and "submit_input" (the movement input path) may be
// recorded or replayed. Everything else (add_player, tick, restore, ...) is refused so a replay
// file can never drive privileged server entry points.
class CgameReplayRecorder : public RefCounted {
	GDCLASS(CgameReplayRecorder, RefCounted);

	static constexpr int FORMAT_VERSION = 1;
	static constexpr uint64_t FNV_OFFSET = 0xcbf29ce484222325ULL;
	static constexpr uint64_t FNV_PRIME = 0x100000001b3ULL;

	int64_t seed_value = 0;
	int64_t world_seed = 0;
	Array players;
	Array frames;
	Array pending;
	int tick = 0;

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(int64_t, seed_value)
	CGAME_ACCESSORS(int64_t, world_seed)
	CGAME_ACCESSORS(Array, players)
	CGAME_ACCESSORS(Array, frames)

	void add_initial_player(int p_peer, const String &p_name);
	bool record_command(int p_peer, const String &p_method, const Array &p_args = Array());
	void end_tick(double p_delta);
	static bool is_allowed_method(const String &p_method);
	Dictionary to_dict() const;
	bool save(const String &p_path) const;
	static Dictionary load_replay(const String &p_path);
	static Dictionary play(const Dictionary &p_replay, const Callable &p_make_server, const Callable &p_hash_fn = Callable());
	static int64_t fnv1a(const String &p_text);
	static int64_t hash_variant(const Variant &p_value);
	static int compare(const Array &p_a_hashes, const Array &p_b_hashes);
};
