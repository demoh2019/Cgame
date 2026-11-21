/**************************************************************************/
/*  cgame_platform_services.cpp                                           */
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

#include "cgame_platform_services.h"

#include "core/config/engine.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/main_loop.h"
#include "core/os/os.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

static_assert((int)CgamePlatformBackend::CODE_OK == (int)CgamePlatformServices::SAVE_OK);
static_assert((int)CgamePlatformBackend::CODE_QUOTA_EXCEEDED == (int)CgamePlatformServices::SAVE_QUOTA_EXCEEDED);
static_assert((int)CgamePlatformBackend::CODE_IO_ERROR == (int)CgamePlatformServices::SAVE_IO_ERROR);
static_assert((int)CgamePlatformBackend::CODE_NOT_FOUND == (int)CgamePlatformServices::SAVE_NOT_FOUND);
static_assert((int)CgamePlatformBackend::CODE_CORRUPT == (int)CgamePlatformServices::SAVE_CORRUPT);
static_assert((int)CgamePlatformBackend::CODE_NO_USER == (int)CgamePlatformServices::SAVE_NO_USER);
static_assert((int)CgamePlatformBackend::CODE_INTERRUPTED == (int)CgamePlatformServices::SAVE_INTERRUPTED);
static_assert((int)CgamePlatformBackend::CODE_SUSPENDED == (int)CgamePlatformServices::SAVE_SUSPENDED);

// ---------------------------------------------------------------- Backend contract

void CgamePlatformBackend::sign_in(const String &p_user_id) {
	user_id = p_user_id;
	emit_signal(SNAME("user_signed_in"), p_user_id);
}

void CgamePlatformBackend::sign_out() {
	if (user_id.is_empty()) {
		return;
	}
	const String gone = user_id;
	user_id = "";
	emit_signal(SNAME("user_signed_out"), gone);
}

int CgamePlatformBackend::write_save(const String &p_slot, const PackedByteArray &p_bytes) {
	return CODE_IO_ERROR;
}

PackedByteArray CgamePlatformBackend::read_save_main(const String &p_slot) {
	return PackedByteArray();
}

PackedByteArray CgamePlatformBackend::read_save_backup(const String &p_slot) {
	return PackedByteArray();
}

void CgamePlatformBackend::delete_save(const String &p_slot) {
}

int64_t CgamePlatformBackend::save_used_bytes() {
	return 0;
}

bool CgamePlatformBackend::unlock_achievement(const String &p_id) {
	return false;
}

bool CgamePlatformBackend::is_achievement_unlocked(const String &p_id) {
	return false;
}

PackedStringArray CgamePlatformBackend::achievement_ids() {
	return PackedStringArray();
}

void CgamePlatformBackend::pair_controller(int p_device_id, const String &p_user_id) {
	pairs[p_device_id] = p_user_id;
	connected.insert(p_device_id);
}

String CgamePlatformBackend::controller_owner(int p_device_id) const {
	HashMap<int, String>::ConstIterator it = pairs.find(p_device_id);
	return it == pairs.end() ? String() : it->value;
}

void CgamePlatformBackend::disconnect_controller(int p_device_id) {
	if (connected.has(p_device_id)) {
		connected.erase(p_device_id);
		emit_signal(SNAME("controller_disconnected"), p_device_id);
	}
}

void CgamePlatformBackend::reconnect_controller(int p_device_id) {
	if (pairs.has(p_device_id) && !connected.has(p_device_id)) {
		connected.insert(p_device_id);
		emit_signal(SNAME("controller_connected"), p_device_id);
	}
}

void CgamePlatformBackend::suspend() {
	if (!suspended) {
		suspended = true;
		emit_signal(SNAME("lifecycle_changed"), true);
	}
}

void CgamePlatformBackend::resume() {
	if (suspended) {
		suspended = false;
		emit_signal(SNAME("lifecycle_changed"), false);
	}
}

void CgamePlatformBackend::set_network(bool p_available) {
	if (network != p_available) {
		network = p_available;
		emit_signal(SNAME("network_changed"), p_available);
	}
}

Dictionary CgamePlatformBackend::request_text_input(const String &p_prompt, int p_max_len) {
	Dictionary d;
	d["ok"] = false;
	d["text"] = "";
	return d;
}

bool CgamePlatformBackend::is_restricted(const String &p_kind) const {
	HashMap<String, bool>::ConstIterator it = restrictions.find(p_kind);
	return it != restrictions.end() && it->value;
}

void CgamePlatformBackend::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_quota_bytes", "bytes"), &CgamePlatformBackend::set_quota_bytes);
	ClassDB::bind_method(D_METHOD("get_quota_bytes"), &CgamePlatformBackend::get_quota_bytes);
	ClassDB::bind_method(D_METHOD("set_interrupt_before_commit", "interrupt"), &CgamePlatformBackend::set_interrupt_before_commit);
	ClassDB::bind_method(D_METHOD("get_interrupt_before_commit"), &CgamePlatformBackend::get_interrupt_before_commit);

	ClassDB::bind_method(D_METHOD("backend_name"), &CgamePlatformBackend::backend_name);
	ClassDB::bind_method(D_METHOD("current_user"), &CgamePlatformBackend::current_user);
	ClassDB::bind_method(D_METHOD("is_signed_in"), &CgamePlatformBackend::is_signed_in);
	ClassDB::bind_method(D_METHOD("sign_in", "user_id"), &CgamePlatformBackend::sign_in);
	ClassDB::bind_method(D_METHOD("sign_out"), &CgamePlatformBackend::sign_out);

	ClassDB::bind_method(D_METHOD("write_save", "slot", "bytes"), &CgamePlatformBackend::write_save);
	ClassDB::bind_method(D_METHOD("read_save_main", "slot"), &CgamePlatformBackend::read_save_main);
	ClassDB::bind_method(D_METHOD("read_save_backup", "slot"), &CgamePlatformBackend::read_save_backup);
	ClassDB::bind_method(D_METHOD("delete_save", "slot"), &CgamePlatformBackend::delete_save);
	ClassDB::bind_method(D_METHOD("save_used_bytes"), &CgamePlatformBackend::save_used_bytes);

	ClassDB::bind_method(D_METHOD("unlock_achievement", "id"), &CgamePlatformBackend::unlock_achievement);
	ClassDB::bind_method(D_METHOD("is_achievement_unlocked", "id"), &CgamePlatformBackend::is_achievement_unlocked);
	ClassDB::bind_method(D_METHOD("achievement_ids"), &CgamePlatformBackend::achievement_ids);

	ClassDB::bind_method(D_METHOD("set_presence", "text"), &CgamePlatformBackend::set_presence);
	ClassDB::bind_method(D_METHOD("presence"), &CgamePlatformBackend::presence);
	ClassDB::bind_method(D_METHOD("grant_entitlement", "id"), &CgamePlatformBackend::grant_entitlement);
	ClassDB::bind_method(D_METHOD("has_entitlement", "id"), &CgamePlatformBackend::has_entitlement);

	ClassDB::bind_method(D_METHOD("pair_controller", "device_id", "user_id"), &CgamePlatformBackend::pair_controller);
	ClassDB::bind_method(D_METHOD("controller_owner", "device_id"), &CgamePlatformBackend::controller_owner);
	ClassDB::bind_method(D_METHOD("is_controller_connected", "device_id"), &CgamePlatformBackend::is_controller_connected);
	ClassDB::bind_method(D_METHOD("disconnect_controller", "device_id"), &CgamePlatformBackend::disconnect_controller);
	ClassDB::bind_method(D_METHOD("reconnect_controller", "device_id"), &CgamePlatformBackend::reconnect_controller);

	ClassDB::bind_method(D_METHOD("is_suspended"), &CgamePlatformBackend::is_suspended);
	ClassDB::bind_method(D_METHOD("suspend"), &CgamePlatformBackend::suspend);
	ClassDB::bind_method(D_METHOD("resume"), &CgamePlatformBackend::resume);

	ClassDB::bind_method(D_METHOD("network_available"), &CgamePlatformBackend::network_available);
	ClassDB::bind_method(D_METHOD("set_network", "available"), &CgamePlatformBackend::set_network);

	ClassDB::bind_method(D_METHOD("uses_native_keyboard"), &CgamePlatformBackend::uses_native_keyboard);
	ClassDB::bind_method(D_METHOD("request_text_input", "prompt", "max_len"), &CgamePlatformBackend::request_text_input);

	ClassDB::bind_method(D_METHOD("set_restriction", "kind", "restricted"), &CgamePlatformBackend::set_restriction);
	ClassDB::bind_method(D_METHOD("is_restricted", "kind"), &CgamePlatformBackend::is_restricted);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "quota_bytes", PROPERTY_HINT_RANGE, "0,1000000000000,1,or_greater"), "set_quota_bytes", "get_quota_bytes");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "interrupt_before_commit"), "set_interrupt_before_commit", "get_interrupt_before_commit");

	ADD_SIGNAL(MethodInfo("user_signed_out", PropertyInfo(Variant::STRING, "user_id")));
	ADD_SIGNAL(MethodInfo("user_signed_in", PropertyInfo(Variant::STRING, "user_id")));
	ADD_SIGNAL(MethodInfo("controller_disconnected", PropertyInfo(Variant::INT, "device_id")));
	ADD_SIGNAL(MethodInfo("controller_connected", PropertyInfo(Variant::INT, "device_id")));
	ADD_SIGNAL(MethodInfo("lifecycle_changed", PropertyInfo(Variant::BOOL, "suspended")));
	ADD_SIGNAL(MethodInfo("network_changed", PropertyInfo(Variant::BOOL, "available")));
}

// ---------------------------------------------------------------- Desktop backend

CgameDesktopPlatformBackend::CgameDesktopPlatformBackend() {
	_setup_local_user();
}

void CgameDesktopPlatformBackend::_setup_local_user() {
	user_id = "local";
	pairs[0] = "local";
	connected.insert(0);
}

void CgameDesktopPlatformBackend::set_root(const String &p_root) {
	root = p_root.trim_suffix("/");
	root_ready = false;
	_ensure_root();
}

void CgameDesktopPlatformBackend::_ensure_root() {
	if (!root_ready) {
		DirAccess::make_dir_recursive_absolute(root);
		root_ready = true;
	}
}

Ref<CgameDesktopPlatformBackend> CgameDesktopPlatformBackend::create(const String &p_root) {
	Ref<CgameDesktopPlatformBackend> backend;
	backend.instantiate();
	backend->set_root(p_root);
	return backend;
}

String CgameDesktopPlatformBackend::_path(const String &p_slot, const String &p_suffix) const {
	return vformat("%s/%s.%s", root, p_slot.validate_filename(), p_suffix);
}

int64_t CgameDesktopPlatformBackend::_size_of(const String &p_path) const {
	if (!FileAccess::exists(p_path)) {
		return 0;
	}
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ);
	if (f.is_null()) {
		return 0;
	}
	return (int64_t)f->get_length();
}

int64_t CgameDesktopPlatformBackend::save_used_bytes() {
	int64_t total = 0;
	for (const String &file_name : DirAccess::get_files_at(root)) {
		total += _size_of(root + "/" + file_name);
	}
	return total;
}

int CgameDesktopPlatformBackend::write_save(const String &p_slot, const PackedByteArray &p_bytes) {
	_ensure_root();
	const String main_path = _path(p_slot, "sav");
	const String tmp = _path(p_slot, "tmp");
	const String bak = _path(p_slot, "bak");
	if (quota_bytes > 0 && save_used_bytes() - _size_of(tmp) + p_bytes.size() > quota_bytes) {
		return CODE_QUOTA_EXCEEDED;
	}
	{
		Ref<FileAccess> f = FileAccess::open(tmp, FileAccess::WRITE);
		if (f.is_null()) {
			return CODE_IO_ERROR;
		}
		f->store_buffer(p_bytes);
		f->close();
	}
	if (_size_of(tmp) != p_bytes.size()) {
		return CODE_IO_ERROR;
	}
	if (interrupt_before_commit) {
		return CODE_INTERRUPTED;
	}
	// Commit: keep the last good file as backup, then promote the verified temp file.
	if (FileAccess::exists(main_path)) {
		if (FileAccess::exists(bak)) {
			DirAccess::remove_absolute(bak);
		}
		if (DirAccess::rename_absolute(main_path, bak) != OK) {
			return CODE_IO_ERROR;
		}
	}
	if (DirAccess::rename_absolute(tmp, main_path) != OK) {
		return CODE_IO_ERROR;
	}
	return CODE_OK;
}

PackedByteArray CgameDesktopPlatformBackend::read_save_main(const String &p_slot) {
	const String p = _path(p_slot, "sav");
	if (!FileAccess::exists(p)) {
		return PackedByteArray();
	}
	return FileAccess::get_file_as_bytes(p);
}

PackedByteArray CgameDesktopPlatformBackend::read_save_backup(const String &p_slot) {
	const String p = _path(p_slot, "bak");
	if (!FileAccess::exists(p)) {
		return PackedByteArray();
	}
	return FileAccess::get_file_as_bytes(p);
}

void CgameDesktopPlatformBackend::delete_save(const String &p_slot) {
	static const char *suffixes[3] = { "sav", "tmp", "bak" };
	for (int i = 0; i < 3; i++) {
		const String p = _path(p_slot, suffixes[i]);
		if (FileAccess::exists(p)) {
			DirAccess::remove_absolute(p);
		}
	}
}

void CgameDesktopPlatformBackend::corrupt_main(const String &p_slot) {
	_ensure_root();
	Ref<FileAccess> f = FileAccess::open(_path(p_slot, "sav"), FileAccess::WRITE);
	if (f.is_valid()) {
		f->store_string("garbage-not-a-save");
	}
}

String CgameDesktopPlatformBackend::_ach_path() const {
	return root + "/achievements.json";
}

Dictionary CgameDesktopPlatformBackend::_ach_load() const {
	if (!FileAccess::exists(_ach_path())) {
		return Dictionary();
	}
	const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(_ach_path()));
	if (parsed.get_type() == Variant::DICTIONARY) {
		return parsed;
	}
	return Dictionary();
}

bool CgameDesktopPlatformBackend::unlock_achievement(const String &p_id) {
	_ensure_root();
	Dictionary data = _ach_load();
	if (data.has(p_id)) {
		return false;
	}
	data[p_id] = (int64_t)OS::get_singleton()->get_unix_time();
	const String tmp = _ach_path() + ".tmp";
	{
		Ref<FileAccess> f = FileAccess::open(tmp, FileAccess::WRITE);
		if (f.is_null()) {
			return false;
		}
		f->store_string(JSON::stringify(data));
		f->close();
	}
	return DirAccess::rename_absolute(tmp, _ach_path()) == OK;
}

bool CgameDesktopPlatformBackend::is_achievement_unlocked(const String &p_id) {
	return _ach_load().has(p_id);
}

PackedStringArray CgameDesktopPlatformBackend::achievement_ids() {
	PackedStringArray out;
	for (const Variant &k : _ach_load().keys()) {
		out.push_back(String(k));
	}
	return out;
}

void CgameDesktopPlatformBackend::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_root", "root"), &CgameDesktopPlatformBackend::set_root);
	ClassDB::bind_method(D_METHOD("get_root"), &CgameDesktopPlatformBackend::get_root);
	ClassDB::bind_method(D_METHOD("corrupt_main", "slot"), &CgameDesktopPlatformBackend::corrupt_main);
	ClassDB::bind_static_method("CgameDesktopPlatformBackend", D_METHOD("create", "root"), &CgameDesktopPlatformBackend::create, DEFVAL("user://platform"));

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "root", PROPERTY_HINT_DIR), "set_root", "get_root");
}

// ---------------------------------------------------------------- Mock backend

CgameMockPlatformBackend::CgameMockPlatformBackend() {
	user_id = "user1";
	pair_controller(0, "user1");
}

int64_t CgameMockPlatformBackend::_size(const HashMap<String, PackedByteArray> &p_map, const String &p_slot) {
	HashMap<String, PackedByteArray>::ConstIterator it = p_map.find(p_slot);
	return it == p_map.end() ? 0 : it->value.size();
}

int64_t CgameMockPlatformBackend::save_used_bytes() {
	int64_t total = 0;
	for (const HashMap<String, PackedByteArray> *store : { &main_store, &tmp_store, &bak_store }) {
		for (const KeyValue<String, PackedByteArray> &kv : *store) {
			total += kv.value.size();
		}
	}
	return total;
}

int CgameMockPlatformBackend::write_save(const String &p_slot, const PackedByteArray &p_bytes) {
	if (suspended) {
		return CODE_SUSPENDED;
	}
	// Console save containers are typically charged for the new data on top of what already exists.
	if (quota_bytes > 0 && save_used_bytes() - _size(tmp_store, p_slot) + p_bytes.size() > quota_bytes) {
		return CODE_QUOTA_EXCEEDED;
	}
	tmp_store[p_slot] = p_bytes.duplicate();
	if (interrupt_before_commit) {
		return CODE_INTERRUPTED;
	}
	if (main_store.has(p_slot)) {
		bak_store[p_slot] = main_store[p_slot];
	}
	main_store[p_slot] = tmp_store[p_slot];
	tmp_store.erase(p_slot);
	return CODE_OK;
}

PackedByteArray CgameMockPlatformBackend::read_save_main(const String &p_slot) {
	HashMap<String, PackedByteArray>::ConstIterator it = main_store.find(p_slot);
	return it == main_store.end() ? PackedByteArray() : it->value;
}

PackedByteArray CgameMockPlatformBackend::read_save_backup(const String &p_slot) {
	HashMap<String, PackedByteArray>::ConstIterator it = bak_store.find(p_slot);
	return it == bak_store.end() ? PackedByteArray() : it->value;
}

void CgameMockPlatformBackend::delete_save(const String &p_slot) {
	main_store.erase(p_slot);
	tmp_store.erase(p_slot);
	bak_store.erase(p_slot);
}

void CgameMockPlatformBackend::corrupt_main(const String &p_slot) {
	main_store[p_slot] = String("garbage-not-a-save").to_utf8_buffer();
}

bool CgameMockPlatformBackend::unlock_achievement(const String &p_id) {
	if (achievements.has(p_id) || !is_signed_in()) {
		return false;
	}
	achievements.insert(p_id);
	return true;
}

bool CgameMockPlatformBackend::is_achievement_unlocked(const String &p_id) {
	return achievements.has(p_id);
}

PackedStringArray CgameMockPlatformBackend::achievement_ids() {
	PackedStringArray out;
	for (const String &id : achievements) {
		out.push_back(id);
	}
	return out;
}

void CgameMockPlatformBackend::set_scripted_text(const PackedStringArray &p_text) {
	scripted_text.clear();
	for (const String &s : p_text) {
		scripted_text.push_back(s);
	}
}

PackedStringArray CgameMockPlatformBackend::get_scripted_text() const {
	PackedStringArray out;
	for (const String &s : scripted_text) {
		out.push_back(s);
	}
	return out;
}

Dictionary CgameMockPlatformBackend::request_text_input(const String &p_prompt, int p_max_len) {
	Dictionary d;
	if (scripted_text.is_empty()) {
		d["ok"] = false;
		d["text"] = "";
		return d;
	}
	const String text = scripted_text[0];
	scripted_text.remove_at(0);
	d["ok"] = true;
	d["text"] = text.substr(0, p_max_len);
	return d;
}

void CgameMockPlatformBackend::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_scripted_text", "text"), &CgameMockPlatformBackend::set_scripted_text);
	ClassDB::bind_method(D_METHOD("get_scripted_text"), &CgameMockPlatformBackend::get_scripted_text);
	ClassDB::bind_method(D_METHOD("set_native_keyboard", "native"), &CgameMockPlatformBackend::set_native_keyboard);
	ClassDB::bind_method(D_METHOD("get_native_keyboard"), &CgameMockPlatformBackend::get_native_keyboard);
	ClassDB::bind_method(D_METHOD("corrupt_main", "slot"), &CgameMockPlatformBackend::corrupt_main);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "scripted_text"), "set_scripted_text", "get_scripted_text");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "native_keyboard"), "set_native_keyboard", "get_native_keyboard");
}

// ---------------------------------------------------------------- Facade

const char *const CgamePlatformServices::MAGIC = "CGS1";

CgamePlatformServices *CgamePlatformServices::singleton = nullptr;

// Forwards application pause / resume notifications from the scene tree to the services.
class CgamePlatformServices::LifecycleRelay : public Node {
	GDCLASS(LifecycleRelay, Node);

public:
	CgamePlatformServices *owner = nullptr;

protected:
	void _notification(int p_what) {
		if (owner != nullptr) {
			owner->handle_notification(p_what);
		}
	}
};

CgamePlatformServices::CgamePlatformServices() {
}

CgamePlatformServices::~CgamePlatformServices() {
	_disconnect_backend();
	Object *relay = ObjectDB::get_instance(relay_id);
	if (relay != nullptr) {
		LifecycleRelay *r = static_cast<LifecycleRelay *>(relay);
		r->owner = nullptr;
		if (!r->is_inside_tree()) {
			memdelete(r);
		}
	}
}

void CgamePlatformServices::create_singleton() {
	if (singleton != nullptr) {
		return;
	}
	singleton = memnew(CgamePlatformServices);
	Engine::get_singleton()->add_singleton(Engine::Singleton("CgamePlatformServices", singleton));
}

void CgamePlatformServices::free_singleton() {
	if (singleton == nullptr) {
		return;
	}
	Engine::get_singleton()->remove_singleton("CgamePlatformServices");
	memdelete(singleton);
	singleton = nullptr;
}

void CgamePlatformServices::attach_to_scene_tree() {
	if (ObjectDB::get_instance(relay_id) != nullptr) {
		return;
	}
	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr || tree->get_root() == nullptr) {
		return;
	}
	LifecycleRelay *relay = memnew(LifecycleRelay);
	relay->set_name("CgamePlatformServicesRelay");
	relay->owner = this;
	relay_id = relay->get_instance_id();
	callable_mp(static_cast<Node *>(tree->get_root()), &Node::add_child).call_deferred(relay, false, Node::INTERNAL_MODE_DISABLED);
}

void CgamePlatformServices::handle_notification(int p_what) {
	if (p_what == MainLoop::NOTIFICATION_APPLICATION_PAUSED) {
		get_backend()->suspend();
	} else if (p_what == MainLoop::NOTIFICATION_APPLICATION_RESUMED) {
		get_backend()->resume();
	}
}

void CgamePlatformServices::_connect_backend() {
	if (backend.is_null()) {
		return;
	}
	backend->connect(SNAME("user_signed_out"), callable_mp(this, &CgamePlatformServices::_on_user_signed_out));
	backend->connect(SNAME("controller_disconnected"), callable_mp(this, &CgamePlatformServices::_on_controller_disconnected));
	backend->connect(SNAME("controller_connected"), callable_mp(this, &CgamePlatformServices::_on_controller_connected));
	backend->connect(SNAME("lifecycle_changed"), callable_mp(this, &CgamePlatformServices::_on_lifecycle_changed));
}

void CgamePlatformServices::_disconnect_backend() {
	if (backend.is_null()) {
		return;
	}
	backend->disconnect(SNAME("user_signed_out"), callable_mp(this, &CgamePlatformServices::_on_user_signed_out));
	backend->disconnect(SNAME("controller_disconnected"), callable_mp(this, &CgamePlatformServices::_on_controller_disconnected));
	backend->disconnect(SNAME("controller_connected"), callable_mp(this, &CgamePlatformServices::_on_controller_connected));
	backend->disconnect(SNAME("lifecycle_changed"), callable_mp(this, &CgamePlatformServices::_on_lifecycle_changed));
}

void CgamePlatformServices::set_backend(const Ref<CgamePlatformBackend> &p_backend) {
	ERR_FAIL_COND_MSG(p_backend.is_null(), "CgamePlatformServices: backend must not be null.");
	_disconnect_backend();
	backend = p_backend;
	_connect_backend();
	session_active = backend->is_signed_in();
	if (this == singleton) {
		attach_to_scene_tree();
	}
}

Ref<CgamePlatformBackend> CgamePlatformServices::get_backend() {
	if (backend.is_null()) {
		set_backend(CgameDesktopPlatformBackend::create());
	}
	return backend;
}

bool CgamePlatformServices::start_session(int p_device_id) {
	Ref<CgamePlatformBackend> be = get_backend();
	if (!be->is_signed_in()) {
		return false;
	}
	owner_device = p_device_id;
	session_active = true;
	paused_for_controller = !be->is_controller_connected(p_device_id);
	return true;
}

void CgamePlatformServices::_on_user_signed_out(const String &p_user_id) {
	session_active = false;
	last_session_end_reason = "signed_out:" + p_user_id;
	emit_signal(SNAME("session_ended"), last_session_end_reason);
}

void CgamePlatformServices::_on_controller_disconnected(int p_device_id) {
	if (p_device_id == owner_device && session_active) {
		paused_for_controller = true;
		emit_signal(SNAME("pause_changed"), true, "controller_disconnected");
	}
}

void CgamePlatformServices::_on_controller_connected(int p_device_id) {
	if (p_device_id == owner_device && paused_for_controller) {
		paused_for_controller = false;
		emit_signal(SNAME("pause_changed"), should_pause(), "controller_reconnected");
	}
}

void CgamePlatformServices::_on_lifecycle_changed(bool p_suspended) {
	paused_for_suspend = p_suspended;
	emit_signal(SNAME("pause_changed"), should_pause(), p_suspended ? "suspend" : "resume");
}

PackedByteArray CgamePlatformServices::encode_save(const Dictionary &p_data) {
	const String body = JSON::stringify(p_data);
	const String text = vformat("%s:%d:%s", MAGIC, (int64_t)body.hash(), body);
	const CharString utf8 = text.utf8();
	PackedByteArray out;
	out.resize(utf8.length());
	if (utf8.length() > 0) {
		memcpy(out.ptrw(), utf8.get_data(), utf8.length());
	}
	return out;
}

Dictionary CgamePlatformServices::decode_save(const PackedByteArray &p_bytes) {
	if (p_bytes.is_empty()) {
		return Dictionary();
	}
	const String text = String::utf8((const char *)p_bytes.ptr(), p_bytes.size());
	const Vector<String> parts = text.split(":", true, 2);
	if (parts.size() != 3 || parts[0] != MAGIC || !parts[1].is_valid_int()) {
		return Dictionary();
	}
	if ((int64_t)parts[2].hash() != parts[1].to_int()) {
		return Dictionary();
	}
	const Variant parsed = JSON::parse_string(parts[2]);
	if (parsed.get_type() == Variant::DICTIONARY) {
		return parsed;
	}
	return Dictionary();
}

int CgamePlatformServices::save_game(const String &p_slot, const Dictionary &p_data) {
	Ref<CgamePlatformBackend> be = get_backend();
	if (!be->is_signed_in()) {
		return SAVE_NO_USER;
	}
	if (be->is_suspended()) {
		return SAVE_SUSPENDED;
	}
	return be->write_save(p_slot, encode_save(p_data));
}

Dictionary CgamePlatformServices::load_game(const String &p_slot) {
	last_recover_source = RECOVER_NONE;
	Dictionary res;
	res["data"] = Dictionary();
	res["source"] = RECOVER_NONE;
	Ref<CgamePlatformBackend> be = get_backend();
	if (!be->is_signed_in()) {
		res["result"] = SAVE_NO_USER;
		return res;
	}
	if (be->is_suspended()) {
		res["result"] = SAVE_SUSPENDED;
		return res;
	}
	const PackedByteArray main_bytes = be->read_save_main(p_slot);
	Dictionary data = decode_save(main_bytes);
	if (!data.is_empty()) {
		last_recover_source = RECOVER_MAIN;
		res["result"] = SAVE_OK;
		res["data"] = data;
		res["source"] = RECOVER_MAIN;
		return res;
	}
	const PackedByteArray backup_bytes = be->read_save_backup(p_slot);
	data = decode_save(backup_bytes);
	if (!data.is_empty()) {
		last_recover_source = RECOVER_BACKUP;
		res["result"] = SAVE_OK;
		res["data"] = data;
		res["source"] = RECOVER_BACKUP;
		return res;
	}
	const bool missing = main_bytes.is_empty() && backup_bytes.is_empty();
	res["result"] = missing ? SAVE_NOT_FOUND : SAVE_CORRUPT;
	return res;
}

bool CgamePlatformServices::unlock_achievement(const String &p_id) {
	const bool fresh = get_backend()->unlock_achievement(p_id);
	if (fresh) {
		emit_signal(SNAME("achievement_unlocked"), p_id);
	}
	return fresh;
}

void CgamePlatformServices::set_presence(const String &p_text) {
	get_backend()->set_presence(p_text);
}

bool CgamePlatformServices::has_entitlement(const String &p_id) {
	return get_backend()->has_entitlement(p_id);
}

bool CgamePlatformServices::network_available() {
	return get_backend()->network_available();
}

bool CgamePlatformServices::can_use_chat() {
	Ref<CgamePlatformBackend> be = get_backend();
	return !be->is_restricted("chat") && be->network_available();
}

bool CgamePlatformServices::can_use_online() {
	Ref<CgamePlatformBackend> be = get_backend();
	return !be->is_restricted("online") && be->network_available();
}

Dictionary CgamePlatformServices::request_text(const String &p_prompt, int p_max_len) {
	return get_backend()->request_text_input(p_prompt, p_max_len);
}

void CgamePlatformServices::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach_to_scene_tree"), &CgamePlatformServices::attach_to_scene_tree);
	ClassDB::bind_method(D_METHOD("handle_notification", "what"), &CgamePlatformServices::handle_notification);
	ClassDB::bind_method(D_METHOD("set_backend", "backend"), &CgamePlatformServices::set_backend);
	ClassDB::bind_method(D_METHOD("get_backend"), &CgamePlatformServices::get_backend);

	ClassDB::bind_method(D_METHOD("start_session", "device_id"), &CgamePlatformServices::start_session, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("should_pause"), &CgamePlatformServices::should_pause);
	ClassDB::bind_method(D_METHOD("is_session_active"), &CgamePlatformServices::is_session_active);
	ClassDB::bind_method(D_METHOD("is_paused_for_controller"), &CgamePlatformServices::is_paused_for_controller);
	ClassDB::bind_method(D_METHOD("is_paused_for_suspend"), &CgamePlatformServices::is_paused_for_suspend);
	ClassDB::bind_method(D_METHOD("get_last_session_end_reason"), &CgamePlatformServices::get_last_session_end_reason);
	ClassDB::bind_method(D_METHOD("get_last_recover_source"), &CgamePlatformServices::get_last_recover_source);

	ClassDB::bind_static_method("CgamePlatformServices", D_METHOD("encode_save", "data"), &CgamePlatformServices::encode_save);
	ClassDB::bind_static_method("CgamePlatformServices", D_METHOD("decode_save", "bytes"), &CgamePlatformServices::decode_save);
	ClassDB::bind_method(D_METHOD("save_game", "slot", "data"), &CgamePlatformServices::save_game);
	ClassDB::bind_method(D_METHOD("load_game", "slot"), &CgamePlatformServices::load_game);

	ClassDB::bind_method(D_METHOD("unlock_achievement", "id"), &CgamePlatformServices::unlock_achievement);
	ClassDB::bind_method(D_METHOD("set_presence", "text"), &CgamePlatformServices::set_presence);
	ClassDB::bind_method(D_METHOD("has_entitlement", "id"), &CgamePlatformServices::has_entitlement);
	ClassDB::bind_method(D_METHOD("network_available"), &CgamePlatformServices::network_available);
	ClassDB::bind_method(D_METHOD("can_use_chat"), &CgamePlatformServices::can_use_chat);
	ClassDB::bind_method(D_METHOD("can_use_online"), &CgamePlatformServices::can_use_online);
	ClassDB::bind_method(D_METHOD("request_text", "prompt", "max_len"), &CgamePlatformServices::request_text);

	ADD_SIGNAL(MethodInfo("session_ended", PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("pause_changed", PropertyInfo(Variant::BOOL, "paused"), PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("achievement_unlocked", PropertyInfo(Variant::STRING, "id")));

	BIND_ENUM_CONSTANT(SAVE_OK);
	BIND_ENUM_CONSTANT(SAVE_QUOTA_EXCEEDED);
	BIND_ENUM_CONSTANT(SAVE_IO_ERROR);
	BIND_ENUM_CONSTANT(SAVE_NOT_FOUND);
	BIND_ENUM_CONSTANT(SAVE_CORRUPT);
	BIND_ENUM_CONSTANT(SAVE_NO_USER);
	BIND_ENUM_CONSTANT(SAVE_INTERRUPTED);
	BIND_ENUM_CONSTANT(SAVE_SUSPENDED);

	BIND_ENUM_CONSTANT(RECOVER_NONE);
	BIND_ENUM_CONSTANT(RECOVER_MAIN);
	BIND_ENUM_CONSTANT(RECOVER_BACKUP);
}
