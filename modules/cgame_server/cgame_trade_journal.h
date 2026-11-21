/**************************************************************************/
/*  cgame_trade_journal.h                                                 */
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
#include "core/os/mutex.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Durable inventory transaction journal for two-account deals (trades and market sales). It is a
// redo log with after-images: the post-deal snapshots of both characters are written to disk
// BEFORE the backend pair commit, so a crash between "deal done in memory" and "backend
// confirmed" can be replayed on restart with the same transaction id (the backend dedupes it).
//
// A side is "superseded" once a later save of that account succeeded: its snapshot is older than
// the backend and must never be written back. Replay then settles only the sides still newest.
// Every public entry point is guarded by a recursive mutex.
class CgameTradeJournal : public RefCounted {
	GDCLASS(CgameTradeJournal, RefCounted);

public:
	static constexpr int VERSION = 1;
	static constexpr int MAX_ENTRIES = 256;

private:
	mutable Mutex mutex;
	String path;
	Dictionary entries;

	bool _flush();
	static Dictionary _side(const String &p_user_id, const Dictionary &p_data);

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(String, path)
	CGAME_ACCESSORS(Dictionary, entries)

	bool open_file(const String &p_journal_path);
	static bool valid_entry(const Variant &p_entry);
	bool record(const String &p_tx, const String &p_user_a, const Dictionary &p_data_a, const String &p_user_b, const Dictionary &p_data_b);
	void settle(const String &p_tx);
	void supersede(const String &p_user_id);
	static String replay_kind(const Dictionary &p_entry);
	PackedStringArray accounts() const;
};
