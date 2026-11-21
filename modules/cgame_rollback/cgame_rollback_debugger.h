/**************************************************************************/
/*  cgame_rollback_debugger.h                                             */
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

#include "cgame_rollback_netcode.h"

#include "core/object/ref_counted.h"
#include "core/string/ustring.h"
#include "core/templates/rb_map.h"

// Debug view over a CgameRollbackNetcode: records every rollback (from/to frame, resimulated frames, the player
// whose late input caused it), per-player prediction miss rate, desync frames with a state diff, and a text
// report. Drive the netcode THROUGH this wrapper (add_remote_input / advance / process) so inputs can be
// classified; the netcode itself is not modified.
class CgameRollbackDebugger : public RefCounted {
	GDCLASS(CgameRollbackDebugger, RefCounted);

public:
	static constexpr int64_t HISTORY_LIMIT = 128;

private:
	Ref<CgameRollbackNetcode> net;
	Array rollbacks; // [{from_frame, to_frame, frames_resimulated, cause}]
	Array desyncs; // [{frame, local_checksum, remote_checksum, local_state, diff}]
	Dictionary late_inputs; // pid -> remote inputs that arrived for an already simulated frame
	Dictionary mispredictions; // pid -> of those, how many differed from the prediction used

	RBMap<int64_t, int64_t> cause_by_frame; // frame -> pid that first required rollback to it
	bool last_advanced = false;
	RBMap<int64_t, Dictionary> history; // frame -> state recorded at advance time (bounded)

	void _before_and_run(bool p_only_process);
	void _on_desync(int64_t p_frame, int64_t p_local_checksum, int64_t p_remote_checksum);
	static bool _variants_equal(const Variant &p_a, const Variant &p_b);
	static void _diff(const Variant &p_a, const Variant &p_b, const String &p_path, Vector<String> &r_out);

protected:
	static void _bind_methods();

public:
	void attach(const Ref<CgameRollbackNetcode> &p_net);
	Ref<CgameRollbackNetcode> get_net() const { return net; }

	void add_remote_input(int64_t p_pid, int64_t p_frame, const Dictionary &p_input);
	int64_t add_local_input(int64_t p_pid, const Dictionary &p_input);
	bool advance();
	void process();

	double miss_rate(int64_t p_pid) const;
	Array attach_remote_state(int64_t p_frame, const Dictionary &p_remote_state);
	static Array diff_states(const Variant &p_a, const Variant &p_b, const String &p_path = "");
	String report() const;
	Dictionary state_history(int64_t p_frame) const;

	Array get_rollbacks() const { return rollbacks; }
	Array get_desyncs() const { return desyncs; }
	Dictionary get_late_inputs() const { return late_inputs; }
	Dictionary get_mispredictions() const { return mispredictions; }
};
