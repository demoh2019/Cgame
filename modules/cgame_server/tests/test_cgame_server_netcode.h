/**************************************************************************/
/*  test_cgame_server_netcode.h                                           */
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

#include "../cgame_lag_compensation.h"
#include "../cgame_replay_recorder.h"
#include "../cgame_save_migrations.h"
#include "../cgame_trade_journal.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/object/callable_mp.h"
#include "core/os/os.h"
#include "tests/test_macros.h"

namespace TestCgameServerNetcode {

template <typename... Args>
static Array arr(Args... p_args) {
	Array out;
	(out.push_back(p_args), ...);
	return out;
}

static String temp_path(const String &p_tag) {
	return "user://cgame_server_" + p_tag + "_" + itos(OS::get_singleton()->get_process_id());
}

static void remove_file(const String &p_path) {
	for (const String &p : { p_path, p_path + ".tmp" }) {
		if (FileAccess::exists(p)) {
			DirAccess::remove_absolute(p);
		}
	}
}

static Dictionary deal_data(int p_silver) {
	Dictionary d;
	d["silver"] = p_silver;
	return d;
}

// ---------------------------------------------------------------- trade journal

TEST_CASE("[CgameTradeJournal] Deals are journaled, superseded, settled and replayed") {
	const String path = temp_path("journal") + ".json";
	remove_file(path);
	Ref<CgameTradeJournal> journal;
	journal.instantiate();
	CHECK(journal->open_file(path));
	CHECK(journal->record("tx1", "alice", deal_data(5), "bob", deal_data(95)));
	CHECK(journal->record("tx2", "alice", deal_data(1), "carol", deal_data(9)));

	Ref<CgameTradeJournal> reopened;
	reopened.instantiate();
	CHECK(reopened->open_file(path));
	CHECK(reopened->get_entries().size() == 2);
	Dictionary entries = reopened->get_entries();
	Dictionary tx1 = entries["tx1"];
	CHECK(CgameTradeJournal::replay_kind(tx1) == "pair");
	Dictionary side_b = tx1["b"];
	Dictionary data_b = side_b["data"];
	CHECK(int(data_b["silver"]) == 95);

	reopened->supersede("alice");
	CHECK(CgameTradeJournal::replay_kind(tx1) == "single");
	reopened->supersede("bob");
	CHECK_FALSE(reopened->get_entries().has("tx1"));
	reopened->settle("tx2");
	CHECK(reopened->get_entries().size() == 0);

	Ref<CgameTradeJournal> after;
	after.instantiate();
	after->open_file(path);
	CHECK(after->get_entries().size() == 0);

	Ref<FileAccess> bad = FileAccess::open(path, FileAccess::WRITE);
	bad->store_string("{not json");
	bad.unref();
	Ref<CgameTradeJournal> corrupt;
	corrupt.instantiate();
	CHECK_FALSE(corrupt->open_file(path)); // A corrupt money journal is refused, not guessed.
	remove_file(path);
}

TEST_CASE("[CgameTradeJournal] Accounts, validation and capacity") {
	Ref<CgameTradeJournal> journal;
	journal.instantiate();
	CHECK(journal->open_file("")); // In-memory journal.
	CHECK(journal->record("tx1", "alice", deal_data(5), "bob", deal_data(95)));
	CHECK_FALSE(journal->record("", "alice", deal_data(5), "bob", deal_data(95)));
	PackedStringArray accounts = journal->accounts();
	CHECK(accounts.size() == 2);
	CHECK(accounts.has("alice"));
	CHECK(accounts.has("bob"));
	CHECK_FALSE(CgameTradeJournal::valid_entry(Variant(5)));
	Dictionary empty_user_side;
	empty_user_side["user"] = "";
	empty_user_side["data"] = Dictionary();
	empty_user_side["superseded"] = false;
	Dictionary bad_entry;
	bad_entry["a"] = empty_user_side;
	bad_entry["b"] = empty_user_side;
	CHECK_FALSE(CgameTradeJournal::valid_entry(bad_entry));
	for (int i = 0; i < CgameTradeJournal::MAX_ENTRIES; i++) {
		journal->record("fill" + itos(i), "u" + itos(i), Dictionary(), "v" + itos(i), Dictionary());
	}
	CHECK_FALSE(journal->record("overflow", "x", Dictionary(), "y", Dictionary()));
}

// ---------------------------------------------------------------- lag compensation

TEST_CASE("[CgameLagCompensation] Rewind is capped and positions interpolate") {
	CHECK(CgameLagCompensation::rewind_for(0.0) == 0.0);
	CHECK(CgameLagCompensation::rewind_for(0.1) == doctest::Approx(0.17));
	CHECK(CgameLagCompensation::rewind_for(2.0) == doctest::Approx(CgameLagCompensation::MAX_REWIND));
	CHECK(CgameLagCompensation::rewind_for(Math::NaN) == 0.0);

	Ref<CgameLagCompensation> history;
	history.instantiate();
	history->record(7, 1.0, Vector3(0, 0, 0));
	history->record(7, 1.1, Vector3(1, 0, 0));
	CHECK(history->position_at(7, 1.05, Vector3(9, 0, 0)).x == doctest::Approx(0.5));
	CHECK(history->position_at(7, 1.2, Vector3(9, 0, 0)) == Vector3(9, 0, 0)); // The present uses the live position.
	CHECK(history->position_at(7, 0.5, Vector3(9, 0, 0)) == Vector3(0, 0, 0)); // Older than history clamps to the oldest sample.
	CHECK(history->position_at(8, 1.0, Vector3(3, 0, 3)) == Vector3(3, 0, 3)); // Unknown target uses the live position.
}

TEST_CASE("[CgameLagCompensation] History is trimmed, forgotten and pruned") {
	Ref<CgameLagCompensation> history;
	history.instantiate();
	for (int i = 0; i < 20; i++) {
		history->record(1, i * 0.1, Vector3(i, 0, 0));
	}
	// Only the last HISTORY_SECONDS (plus the newest sample) survive.
	CHECK(history->sample_count(1) <= 7);
	CHECK(history->sample_count(1) >= 2);
	history->record(2, 0.0, Vector3());
	history->forget(2);
	CHECK(history->sample_count(2) == 0);
	history->record(3, 0.0, Vector3());
	Dictionary alive;
	alive[1] = true;
	history->prune(alive);
	CHECK(history->sample_count(1) > 0);
	CHECK(history->sample_count(3) == 0);
}

TEST_CASE("[CgameLagCompensation] Invalid and duplicate timestamps cannot grow history") {
	Ref<CgameLagCompensation> history;
	history.instantiate();
	history->record(7, 1.0, Vector3(1, 0, 0));
	history->record(7, 1.0, Vector3(2, 0, 0));
	history->record(7, 0.9, Vector3(90, 0, 0));
	history->record(7, Math::NaN, Vector3(99, 0, 0));
	history->record(7, 1.05, Vector3(Math::NaN, 0, 0));
	CHECK(history->sample_count(7) == 1);
	history->record(7, 1.1, Vector3(4, 0, 0));
	CHECK(history->position_at(7, 1.05, Vector3()).x == doctest::Approx(3.0));
	CHECK(history->position_at(7, Math::NaN, Vector3(8, 0, 0)) == Vector3(8, 0, 0));
	for (int i = 0; i < 256; i++) {
		history->record(8, 2.0 + i * 0.0001, Vector3(i, 0, 0));
	}
	CHECK(history->sample_count(8) == 128);
}

// ---------------------------------------------------------------- replay recorder

// A tiny deterministic "server" with the entry points the replayer is allowed (and not allowed) to use.
class CgameTestReplayServer : public RefCounted {
	GDCLASS(CgameTestReplayServer, RefCounted);

	Dictionary positions; // peer -> [x, z]
	Dictionary health; // peer -> hp
	int64_t seed = 0;
	int ticks = 0;
	bool restored = false;

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("add_player", "peer", "name"), &CgameTestReplayServer::add_player);
		ClassDB::bind_method(D_METHOD("tick", "delta"), &CgameTestReplayServer::tick);
		ClassDB::bind_method(D_METHOD("submit_input", "peer", "seq", "x", "z"), &CgameTestReplayServer::submit_input);
		ClassDB::bind_method(D_METHOD("cmd_attack", "peer", "dx", "dz"), &CgameTestReplayServer::cmd_attack);
		ClassDB::bind_method(D_METHOD("restore", "peer"), &CgameTestReplayServer::restore);
		ClassDB::bind_method(D_METHOD("capture_state"), &CgameTestReplayServer::capture_state);
	}

public:
	void set_seed_value(int64_t p_seed) { seed = p_seed; }
	bool was_restored() const { return restored; }

	void add_player(int p_peer, const String &p_name) {
		positions[p_peer] = arr(0.0, 0.0);
		health[p_peer] = 100.0;
	}

	void tick(double p_delta) {
		ticks++;
	}

	void submit_input(int p_peer, int p_seq, double p_x, double p_z) {
		Array p = positions[p_peer];
		p[0] = double(p[0]) + p_x * 0.05;
		p[1] = double(p[1]) + p_z * 0.05;
	}

	void cmd_attack(int p_peer, double p_dx, double p_dz) {
		Array keys = health.keys();
		for (int i = 0; i < keys.size(); i++) {
			if (int(keys[i]) != p_peer) {
				health[keys[i]] = double(health[keys[i]]) - 1.0 - p_dx - p_dz;
			}
		}
	}

	void restore(int p_peer) { restored = true; }

	Dictionary capture_state() const {
		Dictionary d;
		d["positions"] = positions.duplicate(true);
		d["health"] = health.duplicate(true);
		d["ticks"] = ticks;
		d["seed"] = seed;
		return d;
	}
};

static const int REPLAY_TICKS = 40;

static Ref<CgameTestReplayServer> make_replay_server(int64_t p_seed, int64_t p_world_seed) {
	if (!ClassDB::class_exists("CgameTestReplayServer")) {
		ClassDB::register_class<CgameTestReplayServer>();
	}
	Ref<CgameTestReplayServer> server;
	server.instantiate();
	server->set_seed_value(p_seed ^ p_world_seed);
	return server;
}

static int64_t projection_hash(const Variant &p_server) {
	Object *server = p_server;
	return CgameReplayRecorder::hash_variant(server->call("capture_state"));
}

static Ref<CgameReplayRecorder> record_session() {
	Ref<CgameReplayRecorder> rec;
	rec.instantiate();
	rec->set_seed_value(4242);
	rec->set_world_seed(4242);
	rec->add_initial_player(1, "Alpha");
	rec->add_initial_player(2, "Beta");
	int seq = 0;
	for (int i = 0; i < REPLAY_TICKS; i++) {
		seq++;
		rec->record_command(1, "submit_input", arr(seq, 1.0, 0.0));
		rec->record_command(2, "submit_input", arr(seq, 0.0, -1.0));
		if (i % 10 == 5) {
			rec->record_command(1, "cmd_attack", arr(1.0, 0.0));
			rec->record_command(2, "cmd_attack", arr(0.0, 1.0));
		}
		rec->end_tick(0.05);
	}
	return rec;
}

static Callable make_callable() {
	return callable_mp_static(&make_replay_server);
}

TEST_CASE("[CgameReplayRecorder] Replays are deterministic and tampering is located") {
	Ref<CgameReplayRecorder> rec = record_session();
	CHECK(rec->get_frames().size() == REPLAY_TICKS);
	Dictionary replay = rec->to_dict();
	Dictionary first = CgameReplayRecorder::play(replay, make_callable());
	Dictionary second = CgameReplayRecorder::play(replay, make_callable());
	CHECK(bool(first["ok"]));
	Array h1 = first["hashes"];
	Array h2 = second["hashes"];
	CHECK(h1.size() == REPLAY_TICKS);
	CHECK(CgameReplayRecorder::compare(h1, h2) == -1);
	CHECK(int64_t(h1[0]) != int64_t(h1[REPLAY_TICKS - 1]));

	// The explicit hash function path agrees with itself too.
	Dictionary third = CgameReplayRecorder::play(replay, make_callable(), callable_mp_static(&projection_hash));
	Dictionary fourth = CgameReplayRecorder::play(replay, make_callable(), callable_mp_static(&projection_hash));
	CHECK(CgameReplayRecorder::compare(third["hashes"], fourth["hashes"]) == -1);

	Dictionary tampered = rec->to_dict();
	Array frames = tampered["frames"];
	Dictionary frame = frames[12];
	Array commands = frame["commands"];
	for (int i = 0; i < commands.size(); i++) {
		Dictionary cmd = commands[i];
		if (String(cmd["method"]) == "submit_input" && int(cmd["peer"]) == 1) {
			Array args = cmd["args"];
			args[1] = -1.0; // Walk the other way.
		}
	}
	Dictionary bad = CgameReplayRecorder::play(tampered, make_callable());
	CHECK(CgameReplayRecorder::compare(h1, bad["hashes"]) == 12);
	CHECK(CgameReplayRecorder::compare(arr(1, 2, 3), arr(1, 2)) == 2);
	CHECK(CgameReplayRecorder::compare(arr(), arr()) == -1);
}

TEST_CASE("[CgameReplayRecorder] Only cmd_* and submit_input are recorded or replayed") {
	Ref<CgameReplayRecorder> evil;
	evil.instantiate();
	evil->set_seed_value(4242);
	evil->set_world_seed(4242);
	evil->add_initial_player(1, "Alpha");
	CHECK_FALSE(evil->record_command(1, "tick", arr(1.0)));
	CHECK_FALSE(evil->record_command(1, "add_player", arr(9, "x")));
	CHECK(evil->record_command(1, "cmd_attack", arr(1.0, 0.0)));
	CHECK(CgameReplayRecorder::is_allowed_method("submit_input"));
	CHECK_FALSE(CgameReplayRecorder::is_allowed_method("restore"));
	evil->end_tick(0.05);

	Dictionary forged = evil->to_dict();
	Array frames = forged["frames"];
	Dictionary frame = frames[0];
	Array commands = frame["commands"];
	Dictionary restore_cmd;
	restore_cmd["peer"] = 1;
	restore_cmd["method"] = "restore";
	restore_cmd["args"] = Array();
	commands.push_back(restore_cmd);
	Dictionary refused = CgameReplayRecorder::play(forged, make_callable());
	CHECK_FALSE(bool(refused["ok"]));
	Array rejected = refused["rejected"];
	CHECK(rejected.size() == 1);
}

TEST_CASE("[CgameReplayRecorder] Save and load round trip") {
	const String path = temp_path("replay") + ".replay";
	remove_file(path);
	Ref<CgameReplayRecorder> rec = record_session();
	Dictionary first = CgameReplayRecorder::play(rec->to_dict(), make_callable());
	CHECK(rec->save(path));
	Dictionary loaded = CgameReplayRecorder::load_replay(path);
	remove_file(path);
	CHECK_FALSE(loaded.is_empty());
	Dictionary again = CgameReplayRecorder::play(loaded, make_callable());
	CHECK(CgameReplayRecorder::compare(first["hashes"], again["hashes"]) == -1);
	CHECK(CgameReplayRecorder::load_replay("user://does_not_exist.replay").is_empty());
}

TEST_CASE("[CgameReplayRecorder] FNV-1a matches the reference vectors") {
	CHECK(CgameReplayRecorder::fnv1a("") == int64_t(0xcbf29ce484222325ULL));
	CHECK(CgameReplayRecorder::fnv1a("a") == int64_t(0xaf63dc4c8601ec8cULL));
	CHECK(CgameReplayRecorder::fnv1a("foobar") == int64_t(0x85944171f73967e8ULL));
}

// ---------------------------------------------------------------- save migrations

static Variant validate_migration(const Dictionary &p_data) {
	Array problems;
	if (p_data.has("money")) {
		problems.push_back("legacy money key survived");
	}
	if (!p_data.has("silver")) {
		problems.push_back("silver missing");
	}
	return problems;
}

static Dictionary forgets_rename(const Dictionary &p_data) {
	Dictionary d = p_data;
	d["money"] = d.get("money", 0); // Forgets the rename.
	return d;
}

static Dictionary identity_step(const Dictionary &p_data) {
	return p_data;
}

static Dictionary character_v1() {
	Dictionary d;
	d["version"] = 1;
	d["health"] = 80.0;
	d["money"] = 250;
	return d;
}

TEST_CASE("[CgameSaveMigrations] Chain walks from any version to the target") {
	Ref<CgameSaveMigrations> reg = CgameSaveMigrations::character_registry();
	Dictionary v1 = character_v1();
	Dictionary snapshot = v1.duplicate(true);
	Dictionary v3 = reg->migrate(v1, 3);
	CHECK(int(v3["version"]) == 3);
	CHECK(int(v3["silver"]) == 250);
	CHECK_FALSE(v3.has("money"));
	CHECK(double(v3["focus"]) == doctest::Approx(100.0));
	CHECK(v1.recursive_equal(snapshot, 0)); // Input untouched.

	Dictionary mid;
	mid["version"] = 2;
	mid["silver"] = 5;
	CHECK(int(reg->migrate(mid, 3)["focus"]) == 100);
	Dictionary current;
	current["version"] = 3;
	current["silver"] = 1;
	current["focus"] = 7.0;
	CHECK(double(reg->migrate(current, 3)["focus"]) == doctest::Approx(7.0));
}

TEST_CASE("[CgameSaveMigrations] Gaps, downgrades and bad versions are refused") {
	Ref<CgameSaveMigrations> reg = CgameSaveMigrations::character_registry();
	Ref<CgameSaveMigrations> gap;
	gap.instantiate();
	CHECK(gap->register_step(1, 2, callable_mp_static(&CgameSaveMigrations::example_v1_to_v2)));
	CHECK(gap->migrate(character_v1(), 3).is_empty());
	CHECK(gap->get_last_error().contains("gap"));
	Dictionary v4;
	v4["version"] = 4;
	CHECK(reg->migrate(v4, 3).is_empty());
	CHECK(reg->get_last_error().contains("downgrade"));
	Dictionary no_version;
	no_version["health"] = 1;
	CHECK(reg->migrate(no_version, 3).is_empty());
	CHECK_FALSE(gap->register_step(1, 3, callable_mp_static(&CgameSaveMigrations::example_v1_to_v2)));
	CHECK_FALSE(gap->register_step(1, 2, callable_mp_static(&CgameSaveMigrations::example_v1_to_v2)));
	CHECK_FALSE(gap->register_step(5, 6, Callable()));
}

TEST_CASE("[CgameSaveMigrations] verify_roundtrip reports broken migrations") {
	Ref<CgameSaveMigrations> reg = CgameSaveMigrations::character_registry();
	const Callable validator = callable_mp_static(&validate_migration);
	TypedArray<String> ok_problems = reg->verify_roundtrip(character_v1(), 3, validator);
	CHECK(ok_problems.size() == 0);

	Ref<CgameSaveMigrations> broken;
	broken.instantiate();
	broken->register_step(1, 2, callable_mp_static(&forgets_rename));
	TypedArray<String> bad_problems = broken->verify_roundtrip(character_v1(), 2, validator);
	CHECK(bad_problems.size() >= 2);

	Ref<CgameSaveMigrations> mutator;
	mutator.instantiate();
	mutator->register_step(1, 2, callable_mp_static(&identity_step));
	Dictionary sample;
	sample["version"] = 1;
	sample["silver"] = 1;
	CHECK(mutator->verify_roundtrip(sample, 5, Callable()).size() == 1);
}

} // namespace TestCgameServerNetcode
