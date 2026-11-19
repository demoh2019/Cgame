/**************************************************************************/
/*  resource_uid.cpp                                                      */
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

#include "resource_uid.h"

#include "core/config/project_settings.h"
#include "core/crypto/crypto_core.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/marshalls.h"
#include "core/io/resource_loader.h"
#include "core/math/random_pcg.h"
#include "core/object/class_db.h"

#include <climits>
#include <cstring>

// These constants are off by 1, causing the 'z' and '9' characters never to be used.
// This cannot be fixed without breaking compatibility; see GH-83843.
static constexpr uint32_t char_count = ('z' - 'a');
static constexpr uint32_t base = char_count + ('9' - '0');

String ResourceUID::get_cache_file() {
	return ProjectSettings::get_singleton()->get_project_data_path().path_join("uid_cache.bin");
}

static constexpr uint8_t uuid_characters[] = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', '0', '1', '2', '3', '4', '5', '6', '7', '8' };
static constexpr uint32_t uuid_characters_element_count = std_size(uuid_characters);
static constexpr uint8_t max_uuid_number_length = 13; // Max 0x7FFFFFFFFFFFFFFF (uid://d4n4ub6itg400) size is 13 characters.

String ResourceUID::id_to_text(ID p_id) const {
	if (p_id < 0) {
		return "uid://<invalid>";
	}

	char32_t tmp[max_uuid_number_length];
	uint32_t tmp_size = 0;
	do {
		uint32_t c = p_id % uuid_characters_element_count;
		tmp[tmp_size] = uuid_characters[c];
		p_id /= uuid_characters_element_count;
		++tmp_size;
	} while (p_id);

	// tmp_size + uid:// (6) + 1 for null.
	String txt;
	txt.resize_uninitialized(tmp_size + 7);

	char32_t *p = txt.ptrw();
	p[0] = 'u';
	p[1] = 'i';
	p[2] = 'd';
	p[3] = ':';
	p[4] = '/';
	p[5] = '/';
	uint32_t size = 6;

	// The above loop give the number backward, recopy it in the string in the correct order.
	for (uint32_t i = 0; i < tmp_size; ++i) {
		p[size++] = tmp[tmp_size - i - 1];
	}

	p[size] = 0;

	return txt;
}

ResourceUID::ID ResourceUID::text_to_id(const String &p_text) const {
	if (!p_text.begins_with("uid://") || p_text == "uid://<invalid>") {
		return INVALID_ID;
	}

	uint32_t l = p_text.length();
	uint64_t uid = 0;
	for (uint32_t i = 6; i < l; i++) {
		uid *= base;
		uint32_t c = p_text[i];
		if (is_ascii_lower_case(c)) {
			uid += c - 'a';
		} else if (is_digit(c)) {
			uid += c - '0' + char_count;
		} else {
			return INVALID_ID;
		}
	}
	return ID(uid & 0x7FFFFFFFFFFFFFFF);
}

ResourceUID::ID ResourceUID::create_id() {
	while (true) {
		ID id = INVALID_ID;
		MutexLock lock(mutex);
		Error err = CryptoCore::generate_random((uint8_t *)&id, sizeof(id));
		ERR_FAIL_COND_V(err != OK, INVALID_ID);
		id &= 0x7FFFFFFFFFFFFFFF;
		bool exists = unique_ids.has(id);
		if (!exists) {
			return id;
		}
	}
}

ResourceUID::ID ResourceUID::create_id_for_path(const String &p_path) {
	ID id = INVALID_ID;
	RandomPCG rng;

	const String project_name = GLOBAL_GET("application/config/name");
	// Use lowercase file name as random seed.
	// This ensures that case differences don't cause UIDs to shift on case-insensitive filesystems. The downside is that identical files with different case
	// (but otherwise identical name) will run into a hash collision, but this is a very rare scenario.
	rng.seed(project_name.hash64() * p_path.to_lower().hash64() * FileAccess::get_md5(p_path).hash64());

	while (true) {
		int64_t num1 = rng.rand();
		int64_t num2 = ((int64_t)rng.rand()) << 32;
		id = (num1 | num2) & 0x7FFFFFFFFFFFFFFF;

		MutexLock lock(mutex);
		if (!unique_ids.has(id)) {
			break;
		}
	}
	return id;
}

bool ResourceUID::has_id(ID p_id) const {
	MutexLock l(mutex);
	return unique_ids.has(p_id);
}

void ResourceUID::add_id(ID p_id, const String &p_path) {
	MutexLock l(mutex);
	ERR_FAIL_COND(unique_ids.has(p_id));
	Cache c;
	c.cs = p_path.utf8();
	unique_ids[p_id] = c;
	if (use_reverse_cache) {
		reverse_cache[c.cs] = p_id;
	}
	changed = true;
	// The cache was never loaded (probably does not exist), so assume that first ID initializes it.
	cache_initialized = true;
}

void ResourceUID::set_id(ID p_id, const String &p_path) {
	MutexLock l(mutex);
	ERR_FAIL_COND(!unique_ids.has(p_id));
	CharString cs = p_path.utf8();
	const char *update_ptr = cs.ptr();
	const char *cached_ptr = unique_ids[p_id].cs.ptr();
	if (update_ptr == nullptr && cached_ptr == nullptr) {
		return; // Both are empty strings.
	}
	if ((update_ptr == nullptr) != (cached_ptr == nullptr) || strcmp(update_ptr, cached_ptr) != 0) {
		unique_ids[p_id].cs = cs;
		unique_ids[p_id].saved_to_cache = false; //changed
		if (use_reverse_cache) {
			reverse_cache[cs] = p_id;
		}
		changed = true;
	}
}

String ResourceUID::get_id_path(ID p_id) const {
	ERR_FAIL_COND_V_MSG(p_id == INVALID_ID, String(), "Invalid UID.");
	MutexLock l(mutex);
	const ResourceUID::Cache *cache = unique_ids.getptr(p_id);

#if TOOLS_ENABLED
	if (!cache) {
		const ResourceUID::Cache *copy_cache = unique_ids_copy.getptr(p_id);
		if (copy_cache) {
			return String::utf8(copy_cache->cs.ptr());
		}
	}

	// On startup, the scan_for_uid_on_startup callback should be set and will
	// execute EditorFileSystem::scan_for_uid, which scans all project files
	// to reload the UID cache before the first scan.
	// Note: EditorFileSystem::scan_for_uid sets scan_for_uid_on_startup to nullptr
	//       once the first scan_for_uid is complete.
	if (!cache && scan_for_uid_on_startup) {
		scan_for_uid_on_startup();
		cache = unique_ids.getptr(p_id);
	}
#endif

	if (unlikely(!cache)) {
		if (cache_initialized) {
			ERR_PRINT(vformat("Unrecognized UID: \"%s\".", id_to_text(p_id)));
		}
		return String();
	}
	const CharString &cs = cache->cs;
	return String::utf8(cs.ptr());
}

ResourceUID::ID ResourceUID::get_path_id(const String &p_path) const {
	const ID *id = reverse_cache.getptr(p_path.utf8());
	if (id) {
		return *id;
	}
	return INVALID_ID;
}

void ResourceUID::remove_id(ID p_id) {
	MutexLock l(mutex);
	ERR_FAIL_COND(!unique_ids.has(p_id));
	if (use_reverse_cache) {
		reverse_cache.erase(unique_ids[p_id].cs);
	}
	unique_ids.erase(p_id);
}

String ResourceUID::uid_to_path(const String &p_uid) {
	return singleton->get_id_path(singleton->text_to_id(p_uid));
}

String ResourceUID::path_to_uid(const String &p_path) {
	const ID id = ResourceLoader::get_resource_uid(p_path);
	if (id == INVALID_ID) {
		return p_path;
	} else {
		return singleton->id_to_text(id);
	}
}

String ResourceUID::ensure_path(const String &p_uid_or_path) {
	if (p_uid_or_path.begins_with("uid://")) {
		return uid_to_path(p_uid_or_path);
	}
	return p_uid_or_path;
}

String ResourceUID::ensure_path_nocheck(const String &p_uid_or_path) {
	if (p_uid_or_path.begins_with("uid://")) {
		ResourceUID::ID id = singleton->text_to_id(p_uid_or_path);
		if (id == INVALID_ID || !singleton->has_id(id)) {
			return String();
		}
		return singleton->get_id_path(id);
	}
	return p_uid_or_path;
}

Vector<uint8_t> ResourceUID::encode_binary_cache(const Vector<Pair<ID, String>> &p_entries) {
	// The cache is written in little-endian order: entry count, then each UID,
	// UTF-8 byte length and path. Build it directly instead of growing a
	// StreamPeerBuffer with three separate writes per entry.
	Vector<uint8_t> data;
	ERR_FAIL_COND_V(data.resize_uninitialized(4) != OK, Vector<uint8_t>());
	encode_uint32(p_entries.size(), data.ptrw());

	for (const Pair<ID, String> &entry : p_entries) {
		CharString path = entry.second.utf8();
		const uint64_t append_size = 12 + uint64_t(path.length());
		ERR_FAIL_COND_V_MSG(append_size > uint64_t(INT32_MAX - data.size()), Vector<uint8_t>(), "Resource UID cache exceeds maximum vector size.");

		const int offset = data.size();
		ERR_FAIL_COND_V(data.resize_uninitialized(offset + int(append_size)) != OK, Vector<uint8_t>());
		uint8_t *write = data.ptrw() + offset;
		encode_uint64(uint64_t(entry.first), write);
		encode_uint32(path.length(), write + 8);
		if (path.length() > 0) {
			memcpy(write + 12, path.ptr(), path.length());
		}
	}

	return data;
}

Error ResourceUID::save_to_cache() {
	String cache_file = get_cache_file();
	if (!FileAccess::exists(cache_file)) {
		Ref<DirAccess> d = DirAccess::create(DirAccess::ACCESS_RESOURCES);
		d->make_dir_recursive(String(cache_file).get_base_dir()); //ensure base dir exists
	}

	Ref<FileAccess> f = FileAccess::open(cache_file, FileAccess::WRITE);
	if (f.is_null()) {
		return ERR_CANT_OPEN;
	}

	MutexLock l(mutex);

	// Paths are already stored as UTF-8. Writing them directly avoids building
	// a temporary list of Strings and converting every path back to UTF-8.
	uint64_t encoded_size = 4;
	for (const KeyValue<ID, Cache> &E : unique_ids) {
		encoded_size += 12 + uint64_t(E.value.cs.length());
		ERR_FAIL_COND_V_MSG(encoded_size > INT32_MAX, ERR_OUT_OF_MEMORY, "Resource UID cache is too large.");
	}

	Vector<uint8_t> data;
	ERR_FAIL_COND_V(data.resize_uninitialized(int(encoded_size)) != OK, ERR_OUT_OF_MEMORY);
	uint8_t *write = data.ptrw();
	encode_uint32(unique_ids.size(), write);
	write += 4;

	cache_entries = 0;
	for (KeyValue<ID, Cache> &E : unique_ids) {
		const uint32_t path_length = E.value.cs.length();
		encode_uint64(uint64_t(E.key), write);
		encode_uint32(path_length, write + 8);
		if (path_length > 0) {
			memcpy(write + 12, E.value.cs.ptr(), path_length);
		}
		write += 12 + path_length;
		E.value.saved_to_cache = true;
		cache_entries++;
	}

	f->store_buffer(data.ptr(), data.size());

	changed = false;
	return OK;
}

Error ResourceUID::load_from_cache(bool p_reset) {
	Ref<FileAccess> f = FileAccess::open(get_cache_file(), FileAccess::READ);
	if (f.is_null()) {
		return ERR_CANT_OPEN;
	}

	MutexLock l(mutex);
	if (p_reset) {
		if (use_reverse_cache) {
			reverse_cache.clear();
		}
		unique_ids.clear();
	}

	const uint64_t file_length = f->get_length();
	ERR_FAIL_COND_V_MSG(file_length < 4, ERR_FILE_CORRUPT, "Resource UID cache is too short.");

	const uint32_t entry_count = f->get_32();
	// Every entry needs at least an 8-byte ID and a 4-byte path length.
	// Validate the count before allocating hash-table backing storage.
	ERR_FAIL_COND_V_MSG(uint64_t(entry_count) > (file_length - 4) / 12, ERR_FILE_CORRUPT, "Resource UID cache has an invalid entry count.");

	// Pre-size both hash tables once, including any previously loaded entries
	// when p_reset is false. Account for the 75% maximum table occupancy.
	// This avoids repeated rehashes and temporary peak-memory spikes when
	// loading resource-heavy projects with many cache entries.
	const uint64_t target_size = uint64_t(unique_ids.size()) + entry_count;
	if (entry_count > 0 && target_size <= (uint64_t(UINT32_MAX) * 3) / 4) {
		const uint32_t required_capacity = uint32_t((target_size * 4 + 2) / 3);
		unique_ids.reserve(required_capacity);
		if (use_reverse_cache) {
			const uint64_t reverse_size = uint64_t(reverse_cache.size()) + entry_count;
			if (reverse_size <= (uint64_t(UINT32_MAX) * 3) / 4) {
				reverse_cache.reserve(uint32_t((reverse_size * 4 + 2) / 3));
			}
		}
	}
	for (uint32_t i = 0; i < entry_count; i++) {
		int64_t id = f->get_64();
		int32_t len = f->get_32();
		const uint64_t path_position = f->get_position();
		ERR_FAIL_COND_V_MSG(len < 0 || path_position > file_length || uint64_t(len) > file_length - path_position, ERR_FILE_CORRUPT, "Resource UID cache has an invalid path length.");
		Cache c;
		c.cs.resize_uninitialized(len + 1);
		ERR_FAIL_COND_V(c.cs.size() != len + 1, ERR_FILE_CORRUPT); // Out of memory.
		c.cs[len] = 0;
		int32_t rl = f->get_buffer((uint8_t *)c.cs.ptrw(), len);
		ERR_FAIL_COND_V(rl != len, ERR_FILE_CORRUPT);

		c.saved_to_cache = true;
		unique_ids[id] = c;
		if (use_reverse_cache) {
			reverse_cache[c.cs] = id;
		}
	}

	cache_entries = entry_count;
	changed = false;
	cache_initialized = true;
	return OK;
}

Error ResourceUID::update_cache() {
	if (!changed) {
		return OK;
	}

	if (cache_entries == 0) {
		return save_to_cache();
	}
	MutexLock l(mutex);

	Ref<FileAccess> f;
	for (KeyValue<ID, Cache> &E : unique_ids) {
		if (!E.value.saved_to_cache) {
			if (f.is_null()) {
				f = FileAccess::open(get_cache_file(), FileAccess::READ_WRITE); // Append.
				if (f.is_null()) {
					return ERR_CANT_OPEN;
				}
				f->seek_end();
			}
			f->store_64(uint64_t(E.key));
			uint32_t s = E.value.cs.length();
			f->store_32(s);
			f->store_buffer((const uint8_t *)E.value.cs.ptr(), s);
			E.value.saved_to_cache = true;
			cache_entries++;
		}
	}

	if (f.is_valid()) {
		f->seek(0);
		f->store_32(cache_entries); //update amount of entries
	}

	changed = false;

	return OK;
}

String ResourceUID::get_path_from_cache(Ref<FileAccess> &p_cache_file, const String &p_uid_string) {
	const int64_t uid_from_string = singleton->text_to_id(p_uid_string);
	if (uid_from_string != INVALID_ID) {
		const uint32_t entry_count = p_cache_file->get_32();
		for (uint32_t i = 0; i < entry_count; i++) {
			int64_t id = p_cache_file->get_64();
			int32_t len = p_cache_file->get_32();

			if (id == uid_from_string) {
				CharString cs;
				cs.resize_uninitialized(len + 1);
				ERR_FAIL_COND_V(cs.size() != len + 1, String());
				cs[len] = 0;
				int32_t rl = p_cache_file->get_buffer((uint8_t *)cs.ptrw(), len);
				ERR_FAIL_COND_V(rl != len, String());
				return String::utf8(cs.get_data());
			} else {
				p_cache_file->seek(p_cache_file->get_position() + len);
				ERR_FAIL_COND_V(p_cache_file->eof_reached(), String());
			}
		}
	}
	return String();
}

void ResourceUID::clear() {
	MutexLock l(mutex);
	cache_entries = 0;
	if (use_reverse_cache) {
		reverse_cache.clear();
	}
	unique_ids.clear();
	changed = false;
}

#ifdef TOOLS_ENABLED
void ResourceUID::copy_and_clear_cache() {
	MutexLock l(mutex);
	cache_entries = 0;
	unique_ids_copy = std::move(unique_ids);
	changed = false;
}

void ResourceUID::clear_copy() {
	MutexLock l(mutex);
	unique_ids_copy.clear();
}
#endif

void ResourceUID::_bind_methods() {
	ClassDB::bind_method(D_METHOD("id_to_text", "id"), &ResourceUID::id_to_text);
	ClassDB::bind_method(D_METHOD("text_to_id", "text_id"), &ResourceUID::text_to_id);

	ClassDB::bind_method(D_METHOD("create_id"), &ResourceUID::create_id);
	ClassDB::bind_method(D_METHOD("create_id_for_path", "path"), &ResourceUID::create_id_for_path);

	ClassDB::bind_method(D_METHOD("has_id", "id"), &ResourceUID::has_id);
	ClassDB::bind_method(D_METHOD("add_id", "id", "path"), &ResourceUID::add_id);
	ClassDB::bind_method(D_METHOD("set_id", "id", "path"), &ResourceUID::set_id);
	ClassDB::bind_method(D_METHOD("get_id_path", "id"), &ResourceUID::get_id_path);
	ClassDB::bind_method(D_METHOD("remove_id", "id"), &ResourceUID::remove_id);

	ClassDB::bind_static_method("ResourceUID", D_METHOD("uid_to_path", "uid"), &ResourceUID::uid_to_path);
	ClassDB::bind_static_method("ResourceUID", D_METHOD("path_to_uid", "path"), &ResourceUID::path_to_uid);
	ClassDB::bind_static_method("ResourceUID", D_METHOD("ensure_path", "path_or_uid"), &ResourceUID::ensure_path);

	BIND_CONSTANT(INVALID_ID)
}
ResourceUID *ResourceUID::singleton = nullptr;
ResourceUID::ResourceUID() {
	ERR_FAIL_COND(singleton != nullptr);
	singleton = this;
}
