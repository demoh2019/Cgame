/**************************************************************************/
/*  cgame_guild_sync.h                                                    */
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
#include "core/variant/dictionary.h"

// Cross-server guild state: per-server replicas of versioned guild documents, an op log that is
// replicated (push + anti-entropy) and a deterministic, order-independent conflict resolution.
//
// Conflict policy: rank and motd are last-writer-wins by (lamport, origin); a kick wins over a
// concurrent rank change or join (remove-wins) and a member only returns through a join that
// observed the kick; treasury deposits are summed per unique op id so replays never double-count.
class CgameGuildSync : public RefCounted {
	GDCLASS(CgameGuildSync, RefCounted);

	int server_id = 0;
	int clock = 0;
	Dictionary guilds;
	Dictionary log;
	Dictionary vv;
	int seq = 0;

	int64_t _ts() const;
	static int64_t _ts_clock(int64_t p_ts);
	Dictionary _doc(const String &p_gid);
	Dictionary _local(const String &p_gid, const String &p_type, const Dictionary &p_args);
	void _apply(const Dictionary &p_op);
	static Dictionary _member(const Dictionary &p_doc, const String &p_pid);
	static void _set_rank(const Dictionary &p_member, int p_rank, int64_t p_ts);
	static bool _present(const Dictionary &p_member);
	Dictionary _vv_strkeys() const;

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(int, server_id)
	CGAME_ACCESSORS(int, clock)
	CGAME_ACCESSORS(Dictionary, guilds)
	CGAME_ACCESSORS(Dictionary, log)
	CGAME_ACCESSORS(Dictionary, vv)

	Dictionary join(const String &p_gid, const String &p_pid, int p_rank);
	Dictionary set_rank(const String &p_gid, const String &p_pid, int p_rank);
	Dictionary kick(const String &p_gid, const String &p_pid);
	Dictionary set_motd(const String &p_gid, const String &p_text);
	Dictionary deposit(const String &p_gid, int p_amount);

	bool receive(const Dictionary &p_op);
	Array ops_after(const Dictionary &p_remote_vv) const;
	int sync_from(Object *p_other);

	bool is_member(const String &p_gid, const String &p_pid) const;
	int rank_of(const String &p_gid, const String &p_pid) const;
	Array members(const String &p_gid) const;
	String motd(const String &p_gid) const;
	int treasury(const String &p_gid) const;
	int version(const String &p_gid) const;
	String digest(const String &p_gid) const;
};
