/**************************************************************************/
/*  cgame_transaction_coordinator.h                                       */
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
#include "core/variant/array.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"

// Two-phase-commit coordinator (presumed abort) with a durable decision log, plus a persistent
// order book. All public entry points take an internal recursive mutex so a dedicated server may
// drive it from several threads; participant callbacks run while the lock is held.
class CgameTransactionCoordinator : public RefCounted {
	GDCLASS(CgameTransactionCoordinator, RefCounted);

	mutable Mutex mutex;

	String store_path;
	int prepare_timeout_msec = 0;
	String crash_point;
	bool crashed = false;

	Dictionary txs;
	Dictionary persistent_orders;
	int next_tx = 1;
	int next_order = 1;
	Dictionary participants;

	String _deliver(const String &p_tx_id);

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(String, store_path)
	CGAME_ACCESSORS(int, prepare_timeout_msec)
	CGAME_ACCESSORS(String, crash_point)
	CGAME_ACCESSORS(Dictionary, txs)
	CGAME_ACCESSORS(Dictionary, persistent_orders)
	void set_crashed(bool p_crashed) { crashed = p_crashed; }
	bool is_crashed() const { return crashed; }

	void add_participant(const String &p_name, const Callable &p_prepare, const Callable &p_commit, const Callable &p_abort);
	void clear_participants();
	void set_path(const String &p_path);

	bool load_store();
	bool save_store();

	String begin(const Dictionary &p_ops_by_participant);
	String get_status(const String &p_tx_id) const;
	String run(const String &p_tx_id);
	Dictionary recover();
	int abort_stale(double p_now_unix, double p_max_age_sec);

	String place_order(const String &p_owner, const String &p_side, const String &p_item, double p_price, int p_qty);
	bool cancel_order(const String &p_order_id);
	Array open_orders(const String &p_item, const String &p_side) const;
	Array match_orders(const String &p_item);
};
