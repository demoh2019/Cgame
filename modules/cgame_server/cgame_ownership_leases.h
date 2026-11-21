/**************************************************************************/
/*  cgame_ownership_leases.h                                              */
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

// The protected resource of a lease table: remembers the highest fencing token accepted per key
// and rejects any write that carries a lower one, so a paused or zombie holder cannot clobber the
// state written by its successor.
class CgameFencedStore : public RefCounted {
	GDCLASS(CgameFencedStore, RefCounted);

	Dictionary max_token;
	Dictionary values;
	int rejected = 0;

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(Dictionary, max_token)
	CGAME_ACCESSORS(Dictionary, values)
	CGAME_ACCESSORS(int, rejected)

	bool write(const String &p_key, int p_token, const Variant &p_value);
	Variant read(const String &p_key) const;
};

// Expiring ownership leases with monotonic fencing tokens. Time is passed in explicitly (seconds
// or ticks) so the table is deterministic.
class CgameOwnershipLeases : public RefCounted {
	GDCLASS(CgameOwnershipLeases, RefCounted);

	Dictionary leases;
	Dictionary tokens;

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(Dictionary, leases)

	Dictionary acquire(const String &p_key, const String &p_holder, double p_now, double p_ttl);
	bool renew(const String &p_key, const String &p_holder, int p_token, double p_now, double p_ttl);
	bool release(const String &p_key, const String &p_holder, int p_token);
	String holder_of(const String &p_key, double p_now) const;
	int token_of(const String &p_key) const;
	bool is_valid(const String &p_key, const String &p_holder, int p_token, double p_now) const;
	static bool client_valid(double p_expires, double p_now, double p_drift);
	Array reap(double p_now);
};
