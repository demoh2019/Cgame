/**************************************************************************/
/*  cgame_transaction_coordinator.cpp                                     */
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

#include "cgame_transaction_coordinator.h"

#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "core/os/time.h"

void CgameTransactionCoordinator::add_participant(const String &p_name, const Callable &p_prepare, const Callable &p_commit, const Callable &p_abort) {
	MutexLock lock(mutex);
	Dictionary p;
	p["prepare"] = p_prepare;
	p["commit"] = p_commit;
	p["abort"] = p_abort;
	participants[p_name] = p;
}

void CgameTransactionCoordinator::clear_participants() {
	MutexLock lock(mutex);
	participants.clear();
}

void CgameTransactionCoordinator::set_path(const String &p_path) {
	MutexLock lock(mutex);
	store_path = p_path;
}

bool CgameTransactionCoordinator::load_store() {
	MutexLock lock(mutex);
	if (store_path.is_empty() || !FileAccess::exists(store_path)) {
		return false;
	}
	Error err = OK;
	String text = FileAccess::get_file_as_string(store_path, &err);
	if (err != OK) {
		return false;
	}
	Ref<JSON> json;
	json.instantiate();
	if (json->parse(text) != OK || json->get_data().get_type() != Variant::DICTIONARY) {
		return false;
	}
	Dictionary d = json->get_data();
	txs = d.get("txs", Dictionary());
	persistent_orders = d.get("orders", Dictionary());
	next_tx = int(d.get("next_tx", 1));
	next_order = int(d.get("next_order", 1));
	return true;
}

bool CgameTransactionCoordinator::save_store() {
	MutexLock lock(mutex);
	if (store_path.is_empty()) {
		return true;
	}
	const String tmp = store_path + ".tmp";
	Ref<FileAccess> f = FileAccess::open(tmp, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	Dictionary doc;
	doc["txs"] = txs;
	doc["orders"] = persistent_orders;
	doc["next_tx"] = next_tx;
	doc["next_order"] = next_order;
	f->store_string(JSON::stringify(doc));
	f->flush();
	f.unref(); // Closes the file before it is renamed over the store.
	// rename(2) is atomic on one filesystem: readers see the old or the new store, never half.
	return DirAccess::rename_absolute(tmp, store_path) == OK;
}

String CgameTransactionCoordinator::begin(const Dictionary &p_ops_by_participant) {
	MutexLock lock(mutex);
	const String id = "tx" + itos(next_tx);
	next_tx++;
	Dictionary tx;
	tx["state"] = "begun";
	tx["ops"] = p_ops_by_participant.duplicate(true);
	tx["decision"] = "";
	tx["acked"] = Array();
	tx["started"] = Time::get_singleton()->get_unix_time_from_system();
	txs[id] = tx;
	save_store();
	return id;
}

String CgameTransactionCoordinator::get_status(const String &p_tx_id) const {
	MutexLock lock(mutex);
	if (!txs.has(p_tx_id)) {
		return "unknown";
	}
	Dictionary tx = txs[p_tx_id];
	return String(tx["state"]);
}

String CgameTransactionCoordinator::run(const String &p_tx_id) {
	MutexLock lock(mutex);
	if (crashed) {
		return "crashed";
	}
	if (!txs.has(p_tx_id)) {
		return "aborted"; // Presumed abort.
	}
	Dictionary tx = txs[p_tx_id];
	if (String(tx["decision"]).is_empty()) {
		Dictionary ops = tx["ops"];
		bool ok = true;
		Array keys = ops.keys();
		for (int i = 0; i < keys.size(); i++) {
			const Variant pname = keys[i];
			const String key = String(pname);
			if (!participants.has(key)) {
				ok = false;
				break;
			}
			Dictionary p = participants[key];
			Callable prep = p["prepare"];
			const uint64_t t0 = OS::get_singleton()->get_ticks_msec();
			Variant vote = false;
			if (prep.is_valid()) {
				vote = prep.call(p_tx_id, ops[pname]);
			}
			const bool slow = prepare_timeout_msec > 0 && int64_t(OS::get_singleton()->get_ticks_msec() - t0) > prepare_timeout_msec;
			if (vote.get_type() != Variant::BOOL || !bool(vote) || slow) {
				ok = false;
				break;
			}
		}
		if (crash_point == "before_decision") {
			crashed = true;
			return "crashed";
		}
		tx["decision"] = ok ? "commit" : "abort";
		tx["state"] = "decided";
		save_store();
		if (crash_point == "after_decision") {
			crashed = true;
			return "crashed";
		}
	}
	return _deliver(p_tx_id);
}

String CgameTransactionCoordinator::_deliver(const String &p_tx_id) {
	Dictionary tx = txs[p_tx_id];
	const String decision = String(tx["decision"]);
	Array acked = tx["acked"];
	Dictionary ops = tx["ops"];
	Array keys = ops.keys();
	for (int i = 0; i < keys.size(); i++) {
		const String key = String(keys[i]);
		if (acked.has(key) || !participants.has(key)) {
			continue;
		}
		Dictionary p = participants[key];
		Callable cb = decision == "commit" ? Callable(p["commit"]) : Callable(p["abort"]);
		if (cb.is_valid()) {
			cb.call(p_tx_id);
		}
		acked.push_back(key);
		save_store();
	}
	if (acked.size() >= ops.size()) {
		tx["state"] = "done";
		save_store();
	}
	return decision == "commit" ? "committed" : "aborted";
}

Dictionary CgameTransactionCoordinator::recover() {
	MutexLock lock(mutex);
	crashed = false;
	crash_point = "";
	Dictionary results;
	Array ids = txs.keys();
	for (int i = 0; i < ids.size(); i++) {
		const Variant id = ids[i];
		Dictionary tx = txs[id];
		if (String(tx["state"]) == "done") {
			continue;
		}
		if (String(tx["decision"]).is_empty()) {
			tx["decision"] = "abort"; // Presumed abort: no commit decision was logged.
			tx["state"] = "decided";
			save_store();
		}
		results[id] = _deliver(String(id));
	}
	return results;
}

int CgameTransactionCoordinator::abort_stale(double p_now_unix, double p_max_age_sec) {
	MutexLock lock(mutex);
	int n = 0;
	Array ids = txs.keys();
	for (int i = 0; i < ids.size(); i++) {
		const Variant id = ids[i];
		Dictionary tx = txs[id];
		if (String(tx["decision"]).is_empty() && p_now_unix - double(tx["started"]) > p_max_age_sec) {
			tx["decision"] = "abort";
			tx["state"] = "decided";
			(void)_deliver(String(id));
			n++;
		}
	}
	return n;
}

// ---------------------------------------------------------------- persistent order book

String CgameTransactionCoordinator::place_order(const String &p_owner, const String &p_side, const String &p_item, double p_price, int p_qty) {
	MutexLock lock(mutex);
	const String id = itos(next_order);
	Dictionary o;
	o["id"] = id;
	o["seq"] = next_order;
	o["owner"] = p_owner;
	o["side"] = p_side;
	o["item"] = p_item;
	o["price"] = p_price;
	o["qty"] = p_qty;
	persistent_orders[id] = o;
	next_order++;
	save_store();
	return id;
}

bool CgameTransactionCoordinator::cancel_order(const String &p_order_id) {
	MutexLock lock(mutex);
	if (!persistent_orders.has(p_order_id)) {
		return false;
	}
	persistent_orders.erase(p_order_id);
	save_store();
	return true;
}

Array CgameTransactionCoordinator::open_orders(const String &p_item, const String &p_side) const {
	MutexLock lock(mutex);
	Array out;
	Array ids = persistent_orders.keys();
	for (int i = 0; i < ids.size(); i++) {
		Dictionary o = persistent_orders[ids[i]];
		if (String(o["item"]) == p_item && String(o["side"]) == p_side) {
			out.push_back(o);
		}
	}
	const bool buy = p_side == "buy";
	// Best price first, then the older order (price-time priority).
	cgame_sort_array(out, [buy](const Variant &p_a, const Variant &p_b) {
		Dictionary a = p_a;
		Dictionary b = p_b;
		const double pa = a["price"];
		const double pb = b["price"];
		if (pa != pb) {
			return buy ? pa > pb : pa < pb;
		}
		return int(a["seq"]) < int(b["seq"]);
	});
	return out;
}

Array CgameTransactionCoordinator::match_orders(const String &p_item) {
	MutexLock lock(mutex);
	Array trades;
	while (true) {
		Array buys = open_orders(p_item, "buy");
		Array sells = open_orders(p_item, "sell");
		if (buys.is_empty() || sells.is_empty()) {
			break;
		}
		Dictionary b = buys[0];
		Dictionary s = sells[0];
		if (double(b["price"]) < double(s["price"])) {
			break;
		}
		const int qty = MIN(int(b["qty"]), int(s["qty"]));
		const double price = int(b["seq"]) < int(s["seq"]) ? double(b["price"]) : double(s["price"]);
		Dictionary trade;
		trade["buyer"] = b["owner"];
		trade["seller"] = s["owner"];
		trade["item"] = p_item;
		trade["price"] = price;
		trade["qty"] = qty;
		trade["buy_id"] = b["id"];
		trade["sell_id"] = s["id"];
		trades.push_back(trade);
		b["qty"] = int(b["qty"]) - qty;
		s["qty"] = int(s["qty"]) - qty;
		if (int(b["qty"]) <= 0) {
			persistent_orders.erase(String(b["id"]));
		}
		if (int(s["qty"]) <= 0) {
			persistent_orders.erase(String(s["id"]));
		}
	}
	if (!trades.is_empty()) {
		save_store();
	}
	return trades;
}

void CgameTransactionCoordinator::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameTransactionCoordinator, Variant::STRING, store_path)
	CGAME_BIND_PROPERTY(CgameTransactionCoordinator, Variant::INT, prepare_timeout_msec)
	CGAME_BIND_PROPERTY(CgameTransactionCoordinator, Variant::STRING, crash_point)
	CGAME_BIND_PROPERTY(CgameTransactionCoordinator, Variant::DICTIONARY, txs)
	CGAME_BIND_PROPERTY(CgameTransactionCoordinator, Variant::DICTIONARY, persistent_orders)
	ClassDB::bind_method(D_METHOD("set_crashed", "value"), &CgameTransactionCoordinator::set_crashed);
	ClassDB::bind_method(D_METHOD("is_crashed"), &CgameTransactionCoordinator::is_crashed);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "crashed"), "set_crashed", "is_crashed");

	ClassDB::bind_method(D_METHOD("add_participant", "name", "prepare", "commit", "abort"), &CgameTransactionCoordinator::add_participant);
	ClassDB::bind_method(D_METHOD("clear_participants"), &CgameTransactionCoordinator::clear_participants);
	ClassDB::bind_method(D_METHOD("set_path", "path"), &CgameTransactionCoordinator::set_path);
	ClassDB::bind_method(D_METHOD("load_store"), &CgameTransactionCoordinator::load_store);
	ClassDB::bind_method(D_METHOD("save_store"), &CgameTransactionCoordinator::save_store);
	ClassDB::bind_method(D_METHOD("begin", "ops_by_participant"), &CgameTransactionCoordinator::begin);
	ClassDB::bind_method(D_METHOD("status", "tx_id"), &CgameTransactionCoordinator::get_status);
	ClassDB::bind_method(D_METHOD("run", "tx_id"), &CgameTransactionCoordinator::run);
	ClassDB::bind_method(D_METHOD("recover"), &CgameTransactionCoordinator::recover);
	ClassDB::bind_method(D_METHOD("abort_stale", "now_unix", "max_age_sec"), &CgameTransactionCoordinator::abort_stale);
	ClassDB::bind_method(D_METHOD("place_order", "owner", "side", "item", "price", "qty"), &CgameTransactionCoordinator::place_order);
	ClassDB::bind_method(D_METHOD("cancel_order", "order_id"), &CgameTransactionCoordinator::cancel_order);
	ClassDB::bind_method(D_METHOD("open_orders", "item", "side"), &CgameTransactionCoordinator::open_orders);
	ClassDB::bind_method(D_METHOD("match_orders", "item"), &CgameTransactionCoordinator::match_orders);
}
