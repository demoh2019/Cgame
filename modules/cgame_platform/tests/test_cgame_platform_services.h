/**************************************************************************/
/*  test_cgame_platform_services.h                                        */
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

#include "../cgame_platform_services.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/os/main_loop.h"
#include "tests/test_macros.h"
#include "tests/test_utils.h"

namespace TestCgamePlatformServices {

static void rm_tree(const String &p_path) {
	if (!DirAccess::dir_exists_absolute(p_path)) {
		return;
	}
	for (const String &sub : DirAccess::get_directories_at(p_path)) {
		rm_tree(p_path + "/" + sub);
	}
	for (const String &file_name : DirAccess::get_files_at(p_path)) {
		DirAccess::remove_absolute(p_path + "/" + file_name);
	}
	DirAccess::remove_absolute(p_path);
}

static Dictionary save_dict(int p_v, int p_pad = 0) {
	Dictionary d;
	d["v"] = p_v;
	if (p_pad > 0) {
		d["pad"] = String("x").repeat(p_pad);
	}
	return d;
}

static int loaded_v(const Dictionary &p_result) {
	const Dictionary data = p_result["data"];
	return data["v"];
}

static int result_of(const Dictionary &p_result) {
	return p_result["result"];
}

static int source_of(const Dictionary &p_result) {
	return p_result["source"];
}

TEST_CASE("[CgamePlatformServices] Desktop save atomicity and backup recovery") {
	const String root = TestUtils::get_temp_path("cgame_platform_a");
	rm_tree(root);
	Ref<CgameDesktopPlatformBackend> desk = CgameDesktopPlatformBackend::create(root);
	CgamePlatformServices *ps = memnew(CgamePlatformServices);
	ps->set_backend(desk);

	CHECK(ps->save_game("slot", save_dict(1)) == CgamePlatformServices::SAVE_OK);
	CHECK(ps->save_game("slot", save_dict(2)) == CgamePlatformServices::SAVE_OK);
	Dictionary loaded = ps->load_game("slot");
	CHECK(loaded_v(loaded) == 2);
	CHECK(source_of(loaded) == CgamePlatformServices::RECOVER_MAIN);

	desk->corrupt_main("slot");
	loaded = ps->load_game("slot");
	CHECK(result_of(loaded) == CgamePlatformServices::SAVE_OK);
	CHECK(source_of(loaded) == CgamePlatformServices::RECOVER_BACKUP);
	CHECK(loaded_v(loaded) == 1);
	CHECK(ps->get_last_recover_source() == CgamePlatformServices::RECOVER_BACKUP);

	CHECK(result_of(ps->load_game("missing")) == CgamePlatformServices::SAVE_NOT_FOUND);
	CHECK(CgamePlatformServices::decode_save(String("CGS1:1:{}").to_utf8_buffer()).is_empty());

	desk->set_interrupt_before_commit(true);
	CHECK(ps->save_game("slot", save_dict(3)) == CgamePlatformServices::SAVE_INTERRUPTED);
	desk->set_interrupt_before_commit(false);
	CHECK(FileAccess::exists(root + "/slot.tmp"));
	CHECK(loaded_v(ps->load_game("slot")) == 1);

	memdelete(ps);
	rm_tree(root);
}

TEST_CASE("[CgamePlatformServices] Save envelope detects damage") {
	const PackedByteArray good = CgamePlatformServices::encode_save(save_dict(7));
	CHECK(CgamePlatformServices::decode_save(good).get("v", 0) == Variant(7));

	// Flip one payload byte: the hash no longer matches.
	PackedByteArray damaged = good;
	damaged.write[damaged.size() - 3] = 'X';
	CHECK(CgamePlatformServices::decode_save(damaged).is_empty());
	// Truncated file.
	PackedByteArray truncated = good.slice(0, good.size() - 2);
	CHECK(CgamePlatformServices::decode_save(truncated).is_empty());
	CHECK(CgamePlatformServices::decode_save(PackedByteArray()).is_empty());
	CHECK(CgamePlatformServices::decode_save(String("XXXX:1:{}").to_utf8_buffer()).is_empty());

	// Backup recovery and slot removal on the mock backend.
	Ref<CgameMockPlatformBackend> mock;
	mock.instantiate();
	CgamePlatformServices *ps = memnew(CgamePlatformServices);
	ps->set_backend(mock);
	ps->save_game("c", save_dict(1));
	ps->save_game("c", save_dict(2));
	mock->corrupt_main("c");
	CHECK(loaded_v(ps->load_game("c")) == 1);
	mock->delete_save("c");
	CHECK(result_of(ps->load_game("c")) == CgamePlatformServices::SAVE_NOT_FOUND);
	memdelete(ps);
}

TEST_CASE("[CgamePlatformServices] Quota handling") {
	Ref<CgameMockPlatformBackend> mock;
	mock.instantiate();
	CgamePlatformServices *mps = memnew(CgamePlatformServices);
	mps->set_backend(mock);
	CHECK(mps->save_game("q", save_dict(1)) == CgamePlatformServices::SAVE_OK);
	mock->set_quota_bytes(mock->save_used_bytes() + 2);
	CHECK(mps->save_game("q", save_dict(2, 100)) == CgamePlatformServices::SAVE_QUOTA_EXCEEDED);
	CHECK(loaded_v(mps->load_game("q")) == 1);
	memdelete(mps);

	const String root = TestUtils::get_temp_path("cgame_platform_q");
	rm_tree(root);
	Ref<CgameDesktopPlatformBackend> dq = CgameDesktopPlatformBackend::create(root);
	dq->set_quota_bytes(20);
	CgamePlatformServices *dps = memnew(CgamePlatformServices);
	dps->set_backend(dq);
	Dictionary pad;
	pad["pad"] = String("x").repeat(100);
	CHECK(dps->save_game("q", pad) == CgamePlatformServices::SAVE_QUOTA_EXCEEDED);
	memdelete(dps);
	rm_tree(root);
}

TEST_CASE("[CgamePlatformServices] Sign-out mid-session") {
	Ref<CgameMockPlatformBackend> sb;
	sb.instantiate();
	CgamePlatformServices *sps = memnew(CgamePlatformServices);
	sps->set_backend(sb);
	CHECK(sps->start_session(0));
	sb->sign_out();
	CHECK_FALSE(sps->is_session_active());
	CHECK(sps->get_last_session_end_reason().begins_with("signed_out"));
	CHECK(sps->save_game("s", Dictionary()) == CgamePlatformServices::SAVE_NO_USER);
	CHECK(result_of(sps->load_game("s")) == CgamePlatformServices::SAVE_NO_USER);
	CHECK_FALSE(sps->start_session(0));
	memdelete(sps);
}

TEST_CASE("[CgamePlatformServices] Controller disconnect pauses and reconnect resumes") {
	Ref<CgameMockPlatformBackend> cb;
	cb.instantiate();
	CgamePlatformServices *cps = memnew(CgamePlatformServices);
	cps->set_backend(cb);
	cps->start_session(0);
	CHECK_FALSE(cps->should_pause());
	cb->disconnect_controller(0);
	CHECK(cps->should_pause());
	CHECK(cps->is_paused_for_controller());
	cb->reconnect_controller(0);
	CHECK_FALSE(cps->should_pause());
	CHECK(cb->controller_owner(0) == "user1");
	// A different device does not affect the session.
	cb->pair_controller(5, "user2");
	cb->disconnect_controller(5);
	CHECK_FALSE(cps->should_pause());
	memdelete(cps);
}

TEST_CASE("[CgamePlatformServices] Suspend during save and resume") {
	Ref<CgameMockPlatformBackend> xb;
	xb.instantiate();
	CgamePlatformServices *xps = memnew(CgamePlatformServices);
	xps->set_backend(xb);
	xps->save_game("s", save_dict(1));
	xb->set_interrupt_before_commit(true);
	CHECK(xps->save_game("s", save_dict(2)) == CgamePlatformServices::SAVE_INTERRUPTED);
	xb->set_interrupt_before_commit(false);
	xb->suspend();
	CHECK(xps->should_pause());
	CHECK(xps->save_game("s", save_dict(9)) == CgamePlatformServices::SAVE_SUSPENDED);
	CHECK(result_of(xps->load_game("s")) == CgamePlatformServices::SAVE_SUSPENDED);
	xb->resume();
	const Dictionary after = xps->load_game("s");
	CHECK(result_of(after) == CgamePlatformServices::SAVE_OK);
	CHECK(loaded_v(after) == 1);
	CHECK_FALSE(xps->should_pause());
	memdelete(xps);
}

TEST_CASE("[CgamePlatformServices] Application pause and resume notifications suspend the backend") {
	Ref<CgameMockPlatformBackend> mb;
	mb.instantiate();
	CgamePlatformServices *ps = memnew(CgamePlatformServices);
	ps->set_backend(mb);
	ps->handle_notification(MainLoop::NOTIFICATION_APPLICATION_PAUSED);
	CHECK(mb->is_suspended());
	CHECK(ps->is_paused_for_suspend());
	CHECK(ps->should_pause());
	CHECK(ps->save_game("n", save_dict(1)) == CgamePlatformServices::SAVE_SUSPENDED);
	ps->handle_notification(MainLoop::NOTIFICATION_APPLICATION_RESUMED);
	CHECK_FALSE(mb->is_suspended());
	CHECK_FALSE(ps->should_pause());
	CHECK(ps->save_game("n", save_dict(1)) == CgamePlatformServices::SAVE_OK);
	// Unrelated notifications are ignored.
	ps->handle_notification(0);
	CHECK_FALSE(ps->should_pause());
	memdelete(ps);
}

TEST_CASE("[CgamePlatformServices] Achievements persist") {
	const String root = TestUtils::get_temp_path("cgame_platform_ach");
	rm_tree(root);
	Ref<CgameDesktopPlatformBackend> backend = CgameDesktopPlatformBackend::create(root);
	CgamePlatformServices *ach = memnew(CgamePlatformServices);
	ach->set_backend(backend);
	CHECK(ach->unlock_achievement("a1"));
	CHECK_FALSE(ach->unlock_achievement("a1"));
	CHECK(backend->is_achievement_unlocked("a1"));
	CHECK(backend->achievement_ids().size() == 1);
	memdelete(ach);
	rm_tree(root);
}

TEST_CASE("[CgamePlatformServices] Restrictions, presence, entitlements, text input") {
	Ref<CgameMockPlatformBackend> rb;
	rb.instantiate();
	CgamePlatformServices *rps = memnew(CgamePlatformServices);
	rps->set_backend(rb);
	rb->set_restriction("chat", true);
	CHECK_FALSE(rps->can_use_chat());
	rb->set_network(false);
	CHECK_FALSE(rps->network_available());
	CHECK_FALSE(rps->can_use_online());
	rb->grant_entitlement("dlc1");
	CHECK(rps->has_entitlement("dlc1"));
	CHECK_FALSE(rps->has_entitlement("dlc2"));
	rps->set_presence("In raid");
	CHECK(rb->presence() == "In raid");
	PackedStringArray scripted;
	scripted.push_back("toolongname");
	rb->set_scripted_text(scripted);
	CHECK(String(rps->request_text("Name", 5)["text"]) == "toolo");
	CHECK_FALSE(bool(rps->request_text("Name", 5)["ok"]));
	memdelete(rps);
}

} // namespace TestCgamePlatformServices
