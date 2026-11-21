/**************************************************************************/
/*  cgame_platform_services.h                                             */
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

#include "core/object/object.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/variant/binder_common.h"
#include "core/variant/dictionary.h"

class Node;

// Platform abstraction: everything the game needs from the host platform that is not rendering or input mapping.
// Game code talks to CgamePlatformServices only; a backend supplies the platform behaviour. This module ships a
// desktop backend (filesystem + local JSON) and a mock backend that reproduces generic console-style failure modes
// (quota, sign-out, controller loss, suspend) so they can be tested on any machine. It contains no vendor SDK code
// or names; a licensed port adds its own backend subclass.

// ---- Backend contract ----------------------------------------------------------------------------------------

class CgamePlatformBackend : public RefCounted {
	GDCLASS(CgamePlatformBackend, RefCounted);

public:
	// Result codes returned by write_save(); they mirror CgamePlatformServices::SaveResult.
	enum SaveCode {
		CODE_OK,
		CODE_QUOTA_EXCEEDED,
		CODE_IO_ERROR,
		CODE_NOT_FOUND,
		CODE_CORRUPT,
		CODE_NO_USER,
		CODE_INTERRUPTED,
		CODE_SUSPENDED,
	};

protected:
	int64_t quota_bytes = 0; // 0 = unlimited.
	// Test hook: stop a save after the temporary file is written but before it is committed (power loss).
	bool interrupt_before_commit = false;
	String user_id;
	bool suspended = false;
	bool network = true;
	String presence_text;
	HashSet<String> entitlements;
	HashMap<String, bool> restrictions;
	HashMap<int, String> pairs; // device id -> user id.
	HashSet<int> connected; // connected device ids.

	static void _bind_methods();

public:
	void set_quota_bytes(int64_t p_bytes) { quota_bytes = MAX(p_bytes, (int64_t)0); }
	int64_t get_quota_bytes() const { return quota_bytes; }
	void set_interrupt_before_commit(bool p_interrupt) { interrupt_before_commit = p_interrupt; }
	bool get_interrupt_before_commit() const { return interrupt_before_commit; }

	virtual String backend_name() const { return "base"; }

	// Accounts.
	String current_user() const { return user_id; }
	bool is_signed_in() const { return !user_id.is_empty(); }
	void sign_in(const String &p_user_id);
	void sign_out();

	// Save storage (raw bytes; the facade adds the integrity envelope).
	virtual int write_save(const String &p_slot, const PackedByteArray &p_bytes);
	virtual PackedByteArray read_save_main(const String &p_slot);
	virtual PackedByteArray read_save_backup(const String &p_slot);
	virtual void delete_save(const String &p_slot);
	virtual int64_t save_used_bytes();

	// Achievements.
	virtual bool unlock_achievement(const String &p_id);
	virtual bool is_achievement_unlocked(const String &p_id);
	virtual PackedStringArray achievement_ids();

	// Presence and entitlements.
	void set_presence(const String &p_text) { presence_text = p_text; }
	String presence() const { return presence_text; }
	void grant_entitlement(const String &p_id) { entitlements.insert(p_id); }
	bool has_entitlement(const String &p_id) const { return entitlements.has(p_id); }

	// Controller to user pairing.
	void pair_controller(int p_device_id, const String &p_user_id);
	String controller_owner(int p_device_id) const;
	bool is_controller_connected(int p_device_id) const { return connected.has(p_device_id); }
	void disconnect_controller(int p_device_id);
	void reconnect_controller(int p_device_id);

	// Lifecycle.
	bool is_suspended() const { return suspended; }
	void suspend();
	void resume();

	// Network.
	bool network_available() const { return network; }
	void set_network(bool p_available);

	// Text input.
	virtual bool uses_native_keyboard() const { return false; }
	virtual Dictionary request_text_input(const String &p_prompt, int p_max_len);

	// Content restrictions / parental controls (kinds: "chat", "user_content", "purchases", "online").
	void set_restriction(const String &p_kind, bool p_restricted) { restrictions[p_kind] = p_restricted; }
	bool is_restricted(const String &p_kind) const;
};

// ---- Desktop: filesystem under user://, local achievements JSON -------------------------------------------------

class CgameDesktopPlatformBackend : public CgamePlatformBackend {
	GDCLASS(CgameDesktopPlatformBackend, CgamePlatformBackend);

	String root = "user://platform";
	bool root_ready = false;

	void _ensure_root();
	String _path(const String &p_slot, const String &p_suffix) const;
	int64_t _size_of(const String &p_path) const;
	String _ach_path() const;
	Dictionary _ach_load() const;
	void _setup_local_user();

protected:
	static void _bind_methods();

public:
	void set_root(const String &p_root);
	String get_root() const { return root; }
	static Ref<CgameDesktopPlatformBackend> create(const String &p_root = "user://platform");

	virtual String backend_name() const override { return "desktop"; }
	virtual int write_save(const String &p_slot, const PackedByteArray &p_bytes) override;
	virtual PackedByteArray read_save_main(const String &p_slot) override;
	virtual PackedByteArray read_save_backup(const String &p_slot) override;
	virtual void delete_save(const String &p_slot) override;
	virtual int64_t save_used_bytes() override;
	virtual bool unlock_achievement(const String &p_id) override;
	virtual bool is_achievement_unlocked(const String &p_id) override;
	virtual PackedStringArray achievement_ids() override;

	// Test helper: overwrite the main file with garbage (torn write / disk fault).
	void corrupt_main(const String &p_slot);

	CgameDesktopPlatformBackend();
};

// ---- Mock console-style backend: in-memory storage with quota and scriptable failures ---------------------------

class CgameMockPlatformBackend : public CgamePlatformBackend {
	GDCLASS(CgameMockPlatformBackend, CgamePlatformBackend);

	HashMap<String, PackedByteArray> main_store;
	HashMap<String, PackedByteArray> tmp_store;
	HashMap<String, PackedByteArray> bak_store;
	HashSet<String> achievements;
	Vector<String> scripted_text;
	bool native_keyboard = true;

	static int64_t _size(const HashMap<String, PackedByteArray> &p_map, const String &p_slot);

protected:
	static void _bind_methods();

public:
	void set_scripted_text(const PackedStringArray &p_text);
	PackedStringArray get_scripted_text() const;
	void set_native_keyboard(bool p_native) { native_keyboard = p_native; }
	bool get_native_keyboard() const { return native_keyboard; }

	virtual String backend_name() const override { return "mock_console"; }
	virtual int write_save(const String &p_slot, const PackedByteArray &p_bytes) override;
	virtual PackedByteArray read_save_main(const String &p_slot) override;
	virtual PackedByteArray read_save_backup(const String &p_slot) override;
	virtual void delete_save(const String &p_slot) override;
	virtual int64_t save_used_bytes() override;
	virtual bool unlock_achievement(const String &p_id) override;
	virtual bool is_achievement_unlocked(const String &p_id) override;
	virtual PackedStringArray achievement_ids() override;
	virtual bool uses_native_keyboard() const override { return native_keyboard; }
	virtual Dictionary request_text_input(const String &p_prompt, int p_max_len) override;

	void corrupt_main(const String &p_slot);

	CgameMockPlatformBackend();
};

// ---- Facade ----------------------------------------------------------------------------------------------------

class CgamePlatformServices : public Object {
	GDCLASS(CgamePlatformServices, Object);

public:
	enum SaveResult {
		SAVE_OK,
		SAVE_QUOTA_EXCEEDED,
		SAVE_IO_ERROR,
		SAVE_NOT_FOUND,
		SAVE_CORRUPT,
		SAVE_NO_USER,
		SAVE_INTERRUPTED,
		SAVE_SUSPENDED,
	};

	enum RecoverSource {
		RECOVER_NONE,
		RECOVER_MAIN,
		RECOVER_BACKUP,
	};

	static const char *const MAGIC;

private:
	class LifecycleRelay;

	static CgamePlatformServices *singleton;

	Ref<CgamePlatformBackend> backend;
	bool paused_for_controller = false;
	bool paused_for_suspend = false;
	bool session_active = false;
	String last_session_end_reason;
	RecoverSource last_recover_source = RECOVER_NONE;
	int owner_device = 0;
	ObjectID relay_id;

	void _on_user_signed_out(const String &p_user_id);
	void _on_controller_disconnected(int p_device_id);
	void _on_controller_connected(int p_device_id);
	void _on_lifecycle_changed(bool p_suspended);
	void _connect_backend();
	void _disconnect_backend();

protected:
	static void _bind_methods();

public:
	static CgamePlatformServices *get_singleton() { return singleton; }
	static void create_singleton();
	static void free_singleton();

	// Binds to the scene tree (once it exists) so application pause/resume notifications reach the backend.
	void attach_to_scene_tree();
	void handle_notification(int p_what);

	void set_backend(const Ref<CgamePlatformBackend> &p_backend);
	Ref<CgamePlatformBackend> get_backend();

	bool start_session(int p_device_id = 0);
	bool should_pause() const { return paused_for_controller || paused_for_suspend; }
	bool is_session_active() const { return session_active; }
	bool is_paused_for_controller() const { return paused_for_controller; }
	bool is_paused_for_suspend() const { return paused_for_suspend; }
	String get_last_session_end_reason() const { return last_session_end_reason; }
	int get_last_recover_source() const { return last_recover_source; }

	// Saving: the payload is wrapped in "CGS1:<hash>:<json>" so truncated or garbled files are detected on load.
	static PackedByteArray encode_save(const Dictionary &p_data);
	static Dictionary decode_save(const PackedByteArray &p_bytes);
	int save_game(const String &p_slot, const Dictionary &p_data);
	Dictionary load_game(const String &p_slot);

	bool unlock_achievement(const String &p_id);
	void set_presence(const String &p_text);
	bool has_entitlement(const String &p_id);
	bool network_available();
	bool can_use_chat();
	bool can_use_online();
	Dictionary request_text(const String &p_prompt, int p_max_len);

	CgamePlatformServices();
	~CgamePlatformServices();
};

VARIANT_ENUM_CAST(CgamePlatformServices::SaveResult);
VARIANT_ENUM_CAST(CgamePlatformServices::RecoverSource);
