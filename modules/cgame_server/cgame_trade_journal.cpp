/**************************************************************************/
/*  cgame_trade_journal.cpp                                               */
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

#include "cgame_trade_journal.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/os/time.h"

Dictionary CgameTradeJournal::_side(const String &p_user_id, const Dictionary &p_data) {
	Dictionary side;
	side["user"] = p_user_id;
	side["data"] = p_data;
	side["superseded"] = false;
	return side;
}

bool CgameTradeJournal::open_file(const String &p_journal_path) {
	MutexLock lock(mutex);
	path = p_journal_path;
	entries.clear();
	if (!FileAccess::exists(path)) {
		return _flush();
	}
	Error err = OK;
	const String text = FileAccess::get_file_as_string(path, &err);
	if (err != OK) {
		return false;
	}
	Ref<JSON> json;
	json.instantiate();
	if (json->parse(text) != OK || json->get_data().get_type() != Variant::DICTIONARY) {
		return false; // Never guess at a corrupt money journal; the operator must look.
	}
	Dictionary parsed = json->get_data();
	if (int(parsed.get("version", 0)) != VERSION || parsed.get("entries", Variant()).get_type() != Variant::DICTIONARY) {
		return false;
	}
	Dictionary stored = parsed["entries"];
	Array txs = stored.keys();
	for (int i = 0; i < txs.size(); i++) {
		const Variant entry = stored[txs[i]];
		if (valid_entry(entry)) {
			entries[String(txs[i])] = entry;
		}
	}
	return true;
}

bool CgameTradeJournal::valid_entry(const Variant &p_entry) {
	if (p_entry.get_type() != Variant::DICTIONARY) {
		return false;
	}
	Dictionary entry = p_entry;
	for (const char *key : { "a", "b" }) {
		const Variant side_var = entry.get(key, Variant());
		if (side_var.get_type() != Variant::DICTIONARY) {
			return false;
		}
		Dictionary side = side_var;
		if (side.get("user", Variant()).get_type() != Variant::STRING || String(side["user"]).is_empty() ||
				side.get("data", Variant()).get_type() != Variant::DICTIONARY ||
				side.get("superseded", Variant()).get_type() != Variant::BOOL) {
			return false;
		}
	}
	return true;
}

// Write-ahead: returns false if the deal could not be made durable.
bool CgameTradeJournal::record(const String &p_tx, const String &p_user_a, const Dictionary &p_data_a, const String &p_user_b, const Dictionary &p_data_b) {
	MutexLock lock(mutex);
	if (p_tx.is_empty() || entries.size() >= MAX_ENTRIES) {
		return false;
	}
	Dictionary entry;
	entry["a"] = _side(p_user_a, p_data_a.duplicate(true));
	entry["b"] = _side(p_user_b, p_data_b.duplicate(true));
	entry["time"] = Time::get_singleton()->get_unix_time_from_system();
	entries[p_tx] = entry;
	return _flush();
}

// The backend confirmed the deal (or a replay settled it).
void CgameTradeJournal::settle(const String &p_tx) {
	MutexLock lock(mutex);
	if (entries.erase(p_tx)) {
		_flush();
	}
}

// A newer single-account save landed: that side's journaled snapshot is stale.
void CgameTradeJournal::supersede(const String &p_user_id) {
	MutexLock lock(mutex);
	bool changed = false;
	Array txs = entries.keys();
	for (int i = 0; i < txs.size(); i++) {
		Dictionary entry = entries[txs[i]];
		for (const char *key : { "a", "b" }) {
			Dictionary side = entry[key];
			if (String(side["user"]) == p_user_id && !bool(side["superseded"])) {
				side["superseded"] = true;
				changed = true;
			}
		}
		Dictionary a = entry["a"];
		Dictionary b = entry["b"];
		if (bool(a["superseded"]) && bool(b["superseded"])) {
			entries.erase(txs[i]);
		}
	}
	if (changed) {
		_flush();
	}
}

// Replay plan: "pair" when both sides are newest, else "single" for the live side.
String CgameTradeJournal::replay_kind(const Dictionary &p_entry) {
	Dictionary a = p_entry["a"];
	Dictionary b = p_entry["b"];
	const bool a_live = !bool(a["superseded"]);
	const bool b_live = !bool(b["superseded"]);
	if (a_live && b_live) {
		return "pair";
	}
	if (a_live || b_live) {
		return "single";
	}
	return "none";
}

PackedStringArray CgameTradeJournal::accounts() const {
	MutexLock lock(mutex);
	PackedStringArray result;
	Array txs = entries.keys();
	for (int i = 0; i < txs.size(); i++) {
		Dictionary entry = entries[txs[i]];
		for (const char *key : { "a", "b" }) {
			Dictionary side = entry[key];
			const String user = String(side["user"]);
			if (!result.has(user)) {
				result.push_back(user);
			}
		}
	}
	return result;
}

bool CgameTradeJournal::_flush() {
	if (path.is_empty()) {
		return true; // In-memory journal (tests, offline servers).
	}
	const String temp = path + ".tmp";
	Ref<FileAccess> file = FileAccess::open(temp, FileAccess::WRITE);
	if (file.is_null()) {
		return false;
	}
	Dictionary doc;
	doc["version"] = VERSION;
	doc["entries"] = entries;
	file->store_string(JSON::stringify(doc));
	file->flush();
	file.unref();
	// Rename is atomic on the same filesystem: readers see the old or the new journal, never half.
	return DirAccess::rename_absolute(temp, path) == OK;
}

void CgameTradeJournal::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameTradeJournal, Variant::STRING, path)
	CGAME_BIND_PROPERTY(CgameTradeJournal, Variant::DICTIONARY, entries)

	ClassDB::bind_method(D_METHOD("open_file", "journal_path"), &CgameTradeJournal::open_file);
	ClassDB::bind_static_method("CgameTradeJournal", D_METHOD("valid_entry", "entry"), &CgameTradeJournal::valid_entry);
	ClassDB::bind_method(D_METHOD("record", "tx", "user_a", "data_a", "user_b", "data_b"), &CgameTradeJournal::record);
	ClassDB::bind_method(D_METHOD("settle", "tx"), &CgameTradeJournal::settle);
	ClassDB::bind_method(D_METHOD("supersede", "user_id"), &CgameTradeJournal::supersede);
	ClassDB::bind_static_method("CgameTradeJournal", D_METHOD("replay_kind", "entry"), &CgameTradeJournal::replay_kind);
	ClassDB::bind_method(D_METHOD("accounts"), &CgameTradeJournal::accounts);

	BIND_CONSTANT(VERSION);
	BIND_CONSTANT(MAX_ENTRIES);
}
