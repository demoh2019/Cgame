/**************************************************************************/
/*  cgame_item_ledger.cpp                                                 */
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

#include "cgame_item_ledger.h"

static CgameItemLedger *_as_ledger(const Variant &p_value) {
	return Object::cast_to<CgameItemLedger>(p_value.get_type() == Variant::OBJECT ? static_cast<Object *>(p_value) : nullptr);
}

// Mints a brand-new item with a globally unique id ("i<server>-<n>").
String CgameItemLedger::mint(const String &p_owner, const String &p_def) {
	counter++;
	const String id = "i" + itos(server_id) + "-" + itos(counter);
	Dictionary it;
	it["id"] = id;
	it["owner"] = p_owner;
	it["def"] = p_def;
	it["epoch"] = 0;
	it["state"] = "active";
	it["lock_tx"] = "";
	items[id] = it;
	return id;
}

bool CgameItemLedger::has_item(const String &p_id) const {
	return items.has(p_id);
}

String CgameItemLedger::state_of(const String &p_id) const {
	if (!items.has(p_id)) {
		return "";
	}
	Dictionary it = items[p_id];
	return String(it["state"]);
}

bool CgameItemLedger::is_active(const String &p_id) const {
	return state_of(p_id) == "active";
}

String CgameItemLedger::owner_of(const String &p_id) const {
	if (!items.has(p_id)) {
		return "";
	}
	Dictionary it = items[p_id];
	return String(it["owner"]);
}

int CgameItemLedger::epoch_of(const String &p_id) const {
	if (!items.has(p_id)) {
		return -1;
	}
	Dictionary it = items[p_id];
	return int(it["epoch"]);
}

int CgameItemLedger::total_count() const {
	return items.size();
}

int CgameItemLedger::active_count() const {
	int n = 0;
	Array ids = items.keys();
	for (int i = 0; i < ids.size(); i++) {
		if (is_active(String(ids[i]))) {
			n++;
		}
	}
	return n;
}

Array CgameItemLedger::ids_sorted() const {
	Array ids = items.keys();
	ids.sort();
	return ids;
}

// Active item ids owned by the given owner, sorted.
Array CgameItemLedger::items_of(const String &p_owner) const {
	Array out;
	Array ids = ids_sorted();
	for (int i = 0; i < ids.size(); i++) {
		Dictionary it = items[ids[i]];
		if (String(it["owner"]) == p_owner && String(it["state"]) == "active") {
			out.push_back(ids[i]);
		}
	}
	return out;
}

Array CgameItemLedger::snapshot(const Array &p_ids) const {
	Array out;
	for (int i = 0; i < p_ids.size(); i++) {
		if (items.has(p_ids[i])) {
			Dictionary it = items[p_ids[i]];
			out.push_back(it.duplicate(true));
		}
	}
	return out;
}

// ------------------------------------------------------------------ 2PC participant

// op: {"kind": "out", "ids": [...]} on the source, {"kind": "in", "recs": [...]} on the target.
// Returns the vote. Re-preparing the same transaction is idempotent.
bool CgameItemLedger::prepare(const String &p_tx_id, const Variant &p_op) {
	if (p_op.get_type() != Variant::DICTIONARY) {
		return false;
	}
	if (applied.has(p_tx_id)) {
		return String(applied[p_tx_id]) == "commit";
	}
	if (pending.has(p_tx_id)) {
		return true;
	}
	Dictionary d = p_op;
	const String kind = String(d.get("kind", ""));
	if (kind == "out") {
		Array ids = d.get("ids", Array());
		for (int i = 0; i < ids.size(); i++) {
			if (!is_active(String(ids[i]))) {
				return false; // Missing, locked by another tx, or quarantined.
			}
		}
		for (int i = 0; i < ids.size(); i++) {
			Dictionary it = items[String(ids[i])];
			it["state"] = "locked";
			it["lock_tx"] = p_tx_id;
		}
		Dictionary p;
		p["kind"] = "out";
		p["ids"] = ids.duplicate();
		p["recs"] = Array();
		pending[p_tx_id] = p;
		return true;
	}
	if (kind == "in") {
		Array recs = d.get("recs", Array());
		Dictionary seen;
		for (int i = 0; i < recs.size(); i++) {
			Dictionary rec = recs[i];
			const String rid = String(rec["id"]);
			if (items.has(rid) || seen.has(rid)) {
				return false; // We already hold this id: refuse instead of duplicating.
			}
			seen[rid] = true;
		}
		Dictionary p;
		p["kind"] = "in";
		p["ids"] = seen.keys();
		p["recs"] = recs.duplicate(true);
		pending[p_tx_id] = p;
		return true;
	}
	return false;
}

void CgameItemLedger::commit(const String &p_tx_id) {
	if (applied.has(p_tx_id)) {
		return;
	}
	applied[p_tx_id] = "commit";
	if (!pending.has(p_tx_id)) {
		return;
	}
	Dictionary p = pending[p_tx_id];
	pending.erase(p_tx_id);
	Array ids = p["ids"];
	Array recs = p["recs"];
	if (String(p["kind"]) == "out") {
		for (int i = 0; i < ids.size(); i++) {
			items.erase(String(ids[i]));
		}
	} else {
		for (int i = 0; i < recs.size(); i++) {
			Dictionary rec = recs[i];
			const String rid = String(rec["id"]);
			Dictionary incoming;
			incoming["id"] = rid;
			incoming["owner"] = String(rec["owner"]);
			incoming["def"] = String(rec["def"]);
			incoming["epoch"] = int(rec["epoch"]) + 1;
			incoming["state"] = "active";
			incoming["lock_tx"] = "";
			if (items.has(rid)) {
				// Should be impossible (prepare refuses): freeze the existing copy for review.
				quarantine_item(rid, "duplicate received in tx " + p_tx_id);
			} else {
				items[rid] = incoming;
			}
		}
	}
}

void CgameItemLedger::abort(const String &p_tx_id) {
	if (applied.has(p_tx_id)) {
		return;
	}
	applied[p_tx_id] = "abort";
	if (!pending.has(p_tx_id)) {
		return;
	}
	Dictionary p = pending[p_tx_id];
	pending.erase(p_tx_id);
	if (String(p["kind"]) == "out") {
		Array ids = p["ids"];
		for (int i = 0; i < ids.size(); i++) {
			const String key = String(ids[i]);
			if (items.has(key)) {
				Dictionary it = items[key];
				if (String(it["state"]) == "locked" && String(it["lock_tx"]) == p_tx_id) {
					it["state"] = "active";
					it["lock_tx"] = "";
				}
			}
		}
	}
}

// ------------------------------------------------------------------ duplicate handling

void CgameItemLedger::quarantine_item(const String &p_id, const String &p_reason) {
	if (!items.has(p_id)) {
		return;
	}
	Dictionary it = items[p_id];
	it["state"] = "quarantined";
	it["lock_tx"] = "";
	quarantine[p_id] = p_reason;
}

// Returns {item id -> [server ids holding it]} for every id held by more than one ledger.
Dictionary CgameItemLedger::find_duplicates(const Array &p_ledgers) {
	Dictionary where;
	for (int i = 0; i < p_ledgers.size(); i++) {
		CgameItemLedger *led = _as_ledger(p_ledgers[i]);
		if (!led) {
			continue;
		}
		Array ids = led->items.keys();
		for (int j = 0; j < ids.size(); j++) {
			const String key = String(ids[j]);
			if (!where.has(key)) {
				where[key] = Array();
			}
			Array arr = where[key];
			arr.push_back(led->server_id);
		}
	}
	Dictionary dups;
	Array keys = where.keys();
	for (int i = 0; i < keys.size(); i++) {
		Array arr = where[keys[i]];
		if (arr.size() > 1) {
			dups[keys[i]] = arr;
		}
	}
	return dups;
}

// Freezes every copy of every duplicated id. Returns the sorted list of quarantined ids.
Array CgameItemLedger::quarantine_duplicates(const Array &p_ledgers) {
	Dictionary dups = find_duplicates(p_ledgers);
	Array ids = dups.keys();
	for (int i = 0; i < ids.size(); i++) {
		const String id = String(ids[i]);
		for (int j = 0; j < p_ledgers.size(); j++) {
			CgameItemLedger *led = _as_ledger(p_ledgers[j]);
			if (led && led->items.has(id)) {
				led->quarantine_item(id, "duplicate across servers");
			}
		}
	}
	ids.sort();
	return ids;
}

// Keeps the copy with the highest epoch (ties: lowest server id) as active and deletes the rest.
// Returns the surviving server id, or -1 if the id is unknown.
int CgameItemLedger::resolve_duplicate(const Array &p_ledgers, const String &p_id) {
	CgameItemLedger *best = nullptr;
	for (int i = 0; i < p_ledgers.size(); i++) {
		CgameItemLedger *led = _as_ledger(p_ledgers[i]);
		if (!led || !led->items.has(p_id)) {
			continue;
		}
		if (!best || led->epoch_of(p_id) > best->epoch_of(p_id) || (led->epoch_of(p_id) == best->epoch_of(p_id) && led->server_id < best->server_id)) {
			best = led;
		}
	}
	if (!best) {
		return -1;
	}
	for (int i = 0; i < p_ledgers.size(); i++) {
		CgameItemLedger *led = _as_ledger(p_ledgers[i]);
		if (led && led != best && led->items.has(p_id)) {
			led->items.erase(p_id);
			led->quarantine.erase(p_id);
		}
	}
	Dictionary it = best->items[p_id];
	it["state"] = "active";
	best->quarantine.erase(p_id);
	return best->server_id;
}

// ------------------------------------------------------------------ persistence

Dictionary CgameItemLedger::to_dict() const {
	Dictionary d;
	d["server_id"] = server_id;
	d["items"] = items.duplicate(true);
	d["pending"] = pending.duplicate(true);
	d["applied"] = applied.duplicate();
	d["quarantine"] = quarantine.duplicate();
	d["counter"] = counter;
	return d;
}

void CgameItemLedger::from_dict(const Dictionary &p_dict) {
	server_id = int(p_dict.get("server_id", 0));
	items = p_dict.get("items", Dictionary());
	pending = p_dict.get("pending", Dictionary());
	applied = p_dict.get("applied", Dictionary());
	quarantine = p_dict.get("quarantine", Dictionary());
	counter = int(p_dict.get("counter", 0));
}

void CgameItemLedger::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameItemLedger, Variant::INT, server_id)
	CGAME_BIND_PROPERTY(CgameItemLedger, Variant::DICTIONARY, items)
	CGAME_BIND_PROPERTY(CgameItemLedger, Variant::DICTIONARY, pending)
	CGAME_BIND_PROPERTY(CgameItemLedger, Variant::DICTIONARY, applied)
	CGAME_BIND_PROPERTY(CgameItemLedger, Variant::DICTIONARY, quarantine)

	ClassDB::bind_method(D_METHOD("mint", "owner", "def"), &CgameItemLedger::mint);
	ClassDB::bind_method(D_METHOD("has_item", "id"), &CgameItemLedger::has_item);
	ClassDB::bind_method(D_METHOD("state_of", "id"), &CgameItemLedger::state_of);
	ClassDB::bind_method(D_METHOD("is_active", "id"), &CgameItemLedger::is_active);
	ClassDB::bind_method(D_METHOD("owner_of", "id"), &CgameItemLedger::owner_of);
	ClassDB::bind_method(D_METHOD("epoch_of", "id"), &CgameItemLedger::epoch_of);
	ClassDB::bind_method(D_METHOD("total_count"), &CgameItemLedger::total_count);
	ClassDB::bind_method(D_METHOD("active_count"), &CgameItemLedger::active_count);
	ClassDB::bind_method(D_METHOD("ids_sorted"), &CgameItemLedger::ids_sorted);
	ClassDB::bind_method(D_METHOD("items_of", "owner"), &CgameItemLedger::items_of);
	ClassDB::bind_method(D_METHOD("snapshot", "ids"), &CgameItemLedger::snapshot);
	ClassDB::bind_method(D_METHOD("prepare", "tx_id", "op"), &CgameItemLedger::prepare);
	ClassDB::bind_method(D_METHOD("commit", "tx_id"), &CgameItemLedger::commit);
	ClassDB::bind_method(D_METHOD("abort", "tx_id"), &CgameItemLedger::abort);
	ClassDB::bind_method(D_METHOD("quarantine_item", "id", "reason"), &CgameItemLedger::quarantine_item);
	ClassDB::bind_static_method("CgameItemLedger", D_METHOD("find_duplicates", "ledgers"), &CgameItemLedger::find_duplicates);
	ClassDB::bind_static_method("CgameItemLedger", D_METHOD("quarantine_duplicates", "ledgers"), &CgameItemLedger::quarantine_duplicates);
	ClassDB::bind_static_method("CgameItemLedger", D_METHOD("resolve_duplicate", "ledgers", "id"), &CgameItemLedger::resolve_duplicate);
	ClassDB::bind_method(D_METHOD("to_dict"), &CgameItemLedger::to_dict);
	ClassDB::bind_method(D_METHOD("from_dict", "dict"), &CgameItemLedger::from_dict);
}
