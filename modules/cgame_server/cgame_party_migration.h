/**************************************************************************/
/*  cgame_party_migration.h                                               */
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

// Cross-server party directory: the party follows its leader through zone handoffs and members
// hosted on different servers keep identical replicas.
//
// A party doc is {id, leader, home, epoch, version, members: {player -> server}}. Only the home
// server (the leader's server) may mutate it; leader_handoff() moves the home and bumps the epoch
// so a stale former home cannot overwrite newer state. Everyone else applies replica snapshots.
class CgamePartyMigration : public RefCounted {
	GDCLASS(CgamePartyMigration, RefCounted);

	int server_id = 0;
	Dictionary parties;

	bool _mutable(const String &p_id) const;
	static void _bump(const Dictionary &p_doc);
	static bool _newer(const Dictionary &p_a, const Dictionary &p_b);

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(int, server_id)
	CGAME_ACCESSORS(Dictionary, parties)

	bool has_party(const String &p_id) const;
	Dictionary get_doc(const String &p_id) const;
	Dictionary snapshot(const String &p_id) const;
	bool create(const String &p_id, const String &p_leader);
	bool add_member(const String &p_id, const String &p_pid, int p_server);
	bool remove_member(const String &p_id, const String &p_pid);
	bool set_member_server(const String &p_id, const String &p_pid, int p_server);
	Dictionary leader_handoff(const String &p_id, int p_dest);
	Array follow_plan(const String &p_id, int p_dest, const Array &p_nearby = Array()) const;
	bool apply_replica(const Dictionary &p_doc);
	Array servers_of(const String &p_id) const;
	bool same_as(Object *p_other, const String &p_id) const;
};
