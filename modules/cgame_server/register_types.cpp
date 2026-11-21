/**************************************************************************/
/*  register_types.cpp                                                    */
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

#include "register_types.h"

#include "cgame_cluster_simulator.h"
#include "cgame_guild_sync.h"
#include "cgame_item_ledger.h"
#include "cgame_lag_compensation.h"
#include "cgame_ownership_leases.h"
#include "cgame_party_migration.h"
#include "cgame_replay_recorder.h"
#include "cgame_save_migrations.h"
#include "cgame_trade_journal.h"
#include "cgame_transaction_coordinator.h"
#include "cgame_world_sharding.h"

#include "core/object/class_db.h"

void initialize_cgame_server_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(CgameTransactionCoordinator);
	GDREGISTER_CLASS(CgameWorldSharding);
	GDREGISTER_CLASS(CgameItemLedger);
	GDREGISTER_CLASS(CgameGuildSync);
	GDREGISTER_CLASS(CgamePartyMigration);
	GDREGISTER_CLASS(CgameFencedStore);
	GDREGISTER_CLASS(CgameOwnershipLeases);
	GDREGISTER_CLASS(CgameClusterSimulator);
	GDREGISTER_CLASS(CgameTradeJournal);
	GDREGISTER_CLASS(CgameLagCompensation);
	GDREGISTER_CLASS(CgameReplayRecorder);
	GDREGISTER_CLASS(CgameSaveMigrations);
}

void uninitialize_cgame_server_module(ModuleInitializationLevel p_level) {
}
