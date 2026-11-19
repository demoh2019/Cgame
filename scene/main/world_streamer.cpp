/**************************************************************************/
/*  world_streamer.cpp                                             */
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

#include "world_streamer.h"

#include "core/config/engine.h"
#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "scene/2d/node_2d.h"
#include "scene/3d/node_3d.h"
#include "scene/resources/packed_scene.h"

bool WorldStreamer::_get_focus_position(Vector3 &r_position) const {
	if (is_inside_tree() && !focus.is_empty()) {
		Node *node = get_node_or_null(focus);
		Node *parent = _get_parent_for_chunks();
		if (Node3D *node_3d = Object::cast_to<Node3D>(node)) {
			if (node_3d->is_inside_tree()) {
				r_position = node_3d->get_global_position();
				// Measure in the frame of the chunk parent. If that parent is moved by something like
				// FloatingOrigin3D, the chunk grid then stays in absolute world coordinates.
				Node3D *parent_3d = Object::cast_to<Node3D>(parent);
				if (parent_3d && parent_3d->is_inside_tree()) {
					r_position = parent_3d->to_local(r_position);
				}
				return r_position.is_finite();
			}
		} else if (Node2D *node_2d = Object::cast_to<Node2D>(node)) {
			if (node_2d->is_inside_tree()) {
				Vector2 position = node_2d->get_global_position();
				Node2D *parent_2d = Object::cast_to<Node2D>(parent);
				if (parent_2d && parent_2d->is_inside_tree()) {
					position = parent_2d->to_local(position);
				}
				r_position = Vector3(position.x, position.y, 0.0);
				return r_position.is_finite();
			}
		}
	}
	r_position = focus_position;
	return r_position.is_finite();
}

String WorldStreamer::_path_for_cell(const Vector3i &p_cell) const {
	if (chunk_provider.is_valid()) {
		Variant cell = p_cell;
		const Variant *args[1] = { &cell };
		Variant result;
		Callable::CallError error;
		chunk_provider.callp(args, 1, result, error);
		if (error.error != Callable::CallError::CALL_OK) {
			return String();
		}
		return result.get_type() == Variant::STRING || result.get_type() == Variant::STRING_NAME ? String(result) : String();
	}
	if (chunk_path_template.is_empty()) {
		return String();
	}
	String path = chunk_path_template;
	path = path.replace("{x}", itos(p_cell.x));
	path = path.replace("{y}", itos(p_cell.y));
	path = path.replace("{z}", itos(p_cell.z));
	return path;
}

Node *WorldStreamer::_get_parent_for_chunks() const {
	if (!chunk_parent.is_empty() && is_inside_tree()) {
		Node *node = get_node_or_null(chunk_parent);
		if (node) {
			return node;
		}
	}
	return const_cast<WorldStreamer *>(this);
}

void WorldStreamer::_forget_dead_chunks() {
	// A chunk may be freed by game code; stop tracking it so the cell can load again.
	LocalVector<Vector3i> dead;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		if (!ObjectDB::get_instance(entry.value)) {
			dead.push_back(entry.key);
		}
	}
	for (const Vector3i &cell : dead) {
		loaded.erase(cell);
		emit_signal(SNAME("chunk_unloaded"), cell);
	}
}

void WorldStreamer::_unload_cell(const Vector3i &p_cell) {
	HashMap<Vector3i, ObjectID>::Iterator it = loaded.find(p_cell);
	if (!it) {
		return;
	}
	Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(it->value));
	loaded.remove(it);
	if (chunk) {
		if (chunk->get_parent()) {
			chunk->get_parent()->remove_child(chunk);
		}
		chunk->queue_free();
	}
	emit_signal(SNAME("chunk_unloaded"), p_cell);
}

bool WorldStreamer::_adopt_chunk(const Vector3i &p_cell, Node *p_chunk) {
	if (!p_chunk) {
		return false;
	}
	p_chunk->set_name(vformat("Chunk_%d_%d_%d", p_cell.x, p_cell.y, p_cell.z));
	if (position_chunks) {
		const Vector3 origin = WorldStreamingGrid::cell_origin(p_cell, cell_size);
		if (Node3D *chunk_3d = Object::cast_to<Node3D>(p_chunk)) {
			chunk_3d->set_position(origin);
		} else if (Node2D *chunk_2d = Object::cast_to<Node2D>(p_chunk)) {
			chunk_2d->set_position(Vector2(origin.x, origin.y));
		}
	}
	Node *parent = _get_parent_for_chunks();
	parent->add_child(p_chunk);
	loaded[p_cell] = p_chunk->get_instance_id();
	emit_signal(SNAME("chunk_loaded"), p_cell, p_chunk);
	return true;
}

bool WorldStreamer::_finalize_chunk(const Vector3i &p_cell, const String &p_path) {
	Error error = OK;
	Ref<PackedScene> scene = ResourceLoader::load_threaded_get(p_path, &error);
	if (scene.is_null()) {
		return false;
	}
	Node *chunk = scene->instantiate();
	if (!chunk) {
		return false;
	}
	return _adopt_chunk(p_cell, chunk);
}

// Generates queued cells on the main thread, a bounded number per call.
void WorldStreamer::_run_generator_queue() {
	if (generate_queue.is_empty() || !chunk_generator.is_valid()) {
		return;
	}
	Vector3 position;
	const bool have_focus = _get_focus_position(position);
	const real_t keep_radius = MAX(unload_radius, load_radius);
	int budget = MAX(max_instantiations_per_frame, 1);
	uint32_t consumed = 0;
	while (consumed < generate_queue.size() && budget > 0) {
		const Vector3i cell = generate_queue[consumed++];
		if (loaded.has(cell)) {
			continue;
		}
		// The focus may have moved on while the cell waited in the queue.
		if (!have_focus || WorldStreamingGrid::distance_to_cell(position, cell, cell_size, _grid_axes()) > keep_radius) {
			continue;
		}
		budget--;
		Variant cell_variant = cell;
		const Variant *args[1] = { &cell_variant };
		Variant result;
		Callable::CallError error;
		chunk_generator.callp(args, 1, result, error);
		if (error.error != Callable::CallError::CALL_OK) {
			failed.insert(cell);
			emit_signal(SNAME("chunk_load_failed"), cell, String("generator call failed"));
			continue;
		}
		Node *chunk = Object::cast_to<Node>(result.get_validated_object());
		if (!chunk) {
			missing.insert(cell); // The generator says there is nothing here.
			continue;
		}
		if (!_adopt_chunk(cell, chunk)) {
			memdelete(chunk);
			failed.insert(cell);
			emit_signal(SNAME("chunk_load_failed"), cell, String("generator returned an unusable node"));
		}
	}
	if (consumed > 0) {
		LocalVector<Vector3i> rest;
		for (uint32_t i = consumed; i < generate_queue.size(); i++) {
			rest.push_back(generate_queue[i]);
		}
		generate_queue = rest;
	}
}

void WorldStreamer::_poll_loading() {
	_run_generator_queue();
	if (loading.is_empty()) {
		return;
	}
	Vector3 position;
	const bool have_focus = _get_focus_position(position);
	const real_t keep_radius = MAX(unload_radius, load_radius);

	struct Ready {
		Vector3i cell;
		real_t distance;
	};
	LocalVector<Ready> ready;
	LocalVector<Vector3i> finished_failed;
	for (const KeyValue<Vector3i, String> &entry : loading) {
		const ResourceLoader::ThreadLoadStatus status = ResourceLoader::load_threaded_get_status(entry.value);
		if (status == ResourceLoader::THREAD_LOAD_LOADED) {
			ready.push_back({ entry.key, have_focus ? WorldStreamingGrid::distance_to_cell(position, entry.key, cell_size, _grid_axes()) : real_t(0.0) });
		} else if (status != ResourceLoader::THREAD_LOAD_IN_PROGRESS) {
			finished_failed.push_back(entry.key);
		}
	}

	for (const Vector3i &cell : finished_failed) {
		const String path = loading[cell];
		loading.erase(cell);
		failed.insert(cell);
		emit_signal(SNAME("chunk_load_failed"), cell, path);
	}

	// Nearest first, and only a few instantiations per frame to avoid hitches.
	for (uint32_t i = 1; i < ready.size(); i++) { // Insertion sort: the list is tiny.
		Ready item = ready[i];
		int32_t j = int32_t(i) - 1;
		while (j >= 0 && ready[j].distance > item.distance) {
			ready[j + 1] = ready[j];
			j--;
		}
		ready[j + 1] = item;
	}
	int budget = MAX(max_instantiations_per_frame, 1);
	for (const Ready &item : ready) {
		const String path = loading[item.cell];
		const bool still_wanted = have_focus && item.distance <= keep_radius && !loaded.has(item.cell);
		if (!still_wanted) {
			// The focus moved on while loading: release the result and drop it.
			loading.erase(item.cell);
			ResourceLoader::load_threaded_get(path);
			continue;
		}
		if (budget <= 0) {
			continue; // Stays ready for the next frame.
		}
		budget--;
		loading.erase(item.cell);
		if (!_finalize_chunk(item.cell, path)) {
			failed.insert(item.cell);
			emit_signal(SNAME("chunk_load_failed"), item.cell, path);
		}
	}
}

void WorldStreamer::_update_streaming() {
	_forget_dead_chunks();

	Vector3 position;
	if (!enabled || !_get_focus_position(position)) {
		return;
	}
	const real_t keep_radius = MAX(unload_radius, load_radius);

	LocalVector<Vector3i> to_unload;
	HashSet<Vector3i> loaded_cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		loaded_cells.insert(entry.key);
	}
	WorldStreamingGrid::cells_to_unload(position, keep_radius, cell_size, _grid_axes(), loaded_cells, to_unload);
	for (const Vector3i &cell : to_unload) {
		_unload_cell(cell);
	}

	LocalVector<Vector3i> wanted;
	bool truncated = false;
	WorldStreamingGrid::cells_in_radius(position, load_radius, cell_size, _grid_axes(), wanted, WorldStreamingGrid::MAX_CELLS, &truncated);
	if (truncated && !truncated_warned) {
		truncated_warned = true;
		WARN_PRINT(vformat("WorldStreamer: load_radius %s with cell_size %s covers more than %d cells; only the nearest are streamed. Increase cell_size or reduce load_radius.", rtos(load_radius), rtos(cell_size), WorldStreamingGrid::MAX_CELLS));
	}

	if (chunk_generator.is_valid()) {
		// Rebuild the queue: nearest wanted cells that are neither loaded nor queued yet.
		HashSet<Vector3i> queued;
		for (const Vector3i &cell : generate_queue) {
			queued.insert(cell);
		}
		for (const Vector3i &cell : wanted) {
			if (!loaded.has(cell) && !queued.has(cell) && !missing.has(cell) && !failed.has(cell)) {
				generate_queue.push_back(cell);
			}
		}
		return;
	}

	for (const Vector3i &cell : wanted) {
		if (int(loading.size()) >= MAX(max_concurrent_loads, 1)) {
			break;
		}
		if (loaded.has(cell) || loading.has(cell) || missing.has(cell) || failed.has(cell)) {
			continue;
		}
		const String path = _path_for_cell(cell);
		if (path.is_empty() || !ResourceLoader::exists(path)) {
			missing.insert(cell);
			continue;
		}
		if (ResourceLoader::load_threaded_request(path, "PackedScene", true) != OK) {
			failed.insert(cell);
			emit_signal(SNAME("chunk_load_failed"), cell, path);
			continue;
		}
		loading[cell] = path;
	}
}

void WorldStreamer::_reset_state() {
	LocalVector<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	for (const Vector3i &cell : cells) {
		_unload_cell(cell);
	}
	// In-flight requests finish on their own; their results are released when polled.
	missing.clear();
	failed.clear();
	generate_queue.clear();
	truncated_warned = false;
	time_since_update = 1e9;
}

void WorldStreamer::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY:
		case NOTIFICATION_ENTER_TREE: {
			if (!Engine::get_singleton()->is_editor_hint()) {
				set_process_internal(true);
			}
		} break;

		case NOTIFICATION_EXIT_TREE: {
			set_process_internal(false);
			if (chunk_parent.is_empty()) {
				// Chunks are our children and go away with us; just forget them.
				loaded.clear();
			} else {
				_reset_state();
			}
			// A finished background load keeps its resource alive until somebody collects it. Collecting
			// here may wait briefly for loads still running, only while the streamer is being torn down.
			for (const KeyValue<Vector3i, String> &entry : loading) {
				ResourceLoader::load_threaded_get(entry.value);
			}
			loading.clear();
		} break;

		case NOTIFICATION_INTERNAL_PROCESS: {
			if (Engine::get_singleton()->is_editor_hint()) {
				return;
			}
			_poll_loading();
			time_since_update += get_process_delta_time();
			if (time_since_update >= update_interval) {
				time_since_update = 0.0;
				_update_streaming();
				_run_generator_queue(); // New cells are built in the same frame they were queued.
			}
		} break;
	}
}

void WorldStreamer::set_focus(const NodePath &p_focus) {
	focus = p_focus;
}

void WorldStreamer::set_focus_position(const Vector3 &p_position) {
	focus_position = p_position;
}

void WorldStreamer::set_axes(Axes p_axes) {
	if (axes == p_axes) {
		return;
	}
	axes = p_axes;
	_reset_state();
}

void WorldStreamer::set_cell_size(real_t p_size) {
	ERR_FAIL_COND_MSG(!(p_size > 0.0) || !Math::is_finite(p_size), "WorldStreamer cell_size must be a positive finite number.");
	if (cell_size == p_size) {
		return;
	}
	cell_size = p_size;
	_reset_state();
}

void WorldStreamer::set_load_radius(real_t p_radius) {
	load_radius = MAX(p_radius, real_t(0.0));
}

void WorldStreamer::set_unload_radius(real_t p_radius) {
	unload_radius = MAX(p_radius, real_t(0.0));
}

void WorldStreamer::set_max_concurrent_loads(int p_count) {
	max_concurrent_loads = MAX(p_count, 1);
}

void WorldStreamer::set_max_instantiations_per_frame(int p_count) {
	max_instantiations_per_frame = MAX(p_count, 1);
}

void WorldStreamer::set_update_interval(double p_seconds) {
	update_interval = MAX(p_seconds, 0.0);
}

void WorldStreamer::set_chunk_path_template(const String &p_template) {
	if (chunk_path_template == p_template) {
		return;
	}
	chunk_path_template = p_template;
	missing.clear();
	failed.clear();
}

void WorldStreamer::set_chunk_provider(const Callable &p_provider) {
	chunk_provider = p_provider;
	missing.clear();
	failed.clear();
}

void WorldStreamer::set_chunk_generator(const Callable &p_generator) {
	chunk_generator = p_generator;
	generate_queue.clear();
	missing.clear();
	failed.clear();
}

void WorldStreamer::set_chunk_parent(const NodePath &p_parent) {
	chunk_parent = p_parent;
}

void WorldStreamer::set_enabled(bool p_enabled) {
	enabled = p_enabled;
}

Vector3i WorldStreamer::world_to_cell(const Vector3 &p_position) const {
	return WorldStreamingGrid::world_to_cell(p_position, cell_size, _grid_axes());
}

Vector3 WorldStreamer::cell_to_world(const Vector3i &p_cell) const {
	return WorldStreamingGrid::cell_origin(p_cell, cell_size);
}

Node *WorldStreamer::get_chunk(const Vector3i &p_cell) const {
	HashMap<Vector3i, ObjectID>::ConstIterator it = loaded.find(p_cell);
	return it ? Object::cast_to<Node>(ObjectDB::get_instance(it->value)) : nullptr;
}

TypedArray<Vector3i> WorldStreamer::get_loaded_cells() const {
	TypedArray<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	return cells;
}

void WorldStreamer::refresh(bool p_retry) {
	if (p_retry) {
		missing.clear();
		failed.clear();
		truncated_warned = false;
	}
	_poll_loading();
	_update_streaming();
	_run_generator_queue();
	time_since_update = 0.0;
}

void WorldStreamer::unload_all() {
	LocalVector<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	for (const Vector3i &cell : cells) {
		_unload_cell(cell);
	}
}

void WorldStreamer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_focus", "focus"), &WorldStreamer::set_focus);
	ClassDB::bind_method(D_METHOD("get_focus"), &WorldStreamer::get_focus);
	ClassDB::bind_method(D_METHOD("set_focus_position", "position"), &WorldStreamer::set_focus_position);
	ClassDB::bind_method(D_METHOD("get_focus_position"), &WorldStreamer::get_focus_position);
	ClassDB::bind_method(D_METHOD("set_axes", "axes"), &WorldStreamer::set_axes);
	ClassDB::bind_method(D_METHOD("get_axes"), &WorldStreamer::get_axes);
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &WorldStreamer::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &WorldStreamer::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_load_radius", "radius"), &WorldStreamer::set_load_radius);
	ClassDB::bind_method(D_METHOD("get_load_radius"), &WorldStreamer::get_load_radius);
	ClassDB::bind_method(D_METHOD("set_unload_radius", "radius"), &WorldStreamer::set_unload_radius);
	ClassDB::bind_method(D_METHOD("get_unload_radius"), &WorldStreamer::get_unload_radius);
	ClassDB::bind_method(D_METHOD("set_max_concurrent_loads", "count"), &WorldStreamer::set_max_concurrent_loads);
	ClassDB::bind_method(D_METHOD("get_max_concurrent_loads"), &WorldStreamer::get_max_concurrent_loads);
	ClassDB::bind_method(D_METHOD("set_max_instantiations_per_frame", "count"), &WorldStreamer::set_max_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_instantiations_per_frame"), &WorldStreamer::get_max_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("set_update_interval", "seconds"), &WorldStreamer::set_update_interval);
	ClassDB::bind_method(D_METHOD("get_update_interval"), &WorldStreamer::get_update_interval);
	ClassDB::bind_method(D_METHOD("set_chunk_path_template", "template"), &WorldStreamer::set_chunk_path_template);
	ClassDB::bind_method(D_METHOD("get_chunk_path_template"), &WorldStreamer::get_chunk_path_template);
	ClassDB::bind_method(D_METHOD("set_chunk_generator", "generator"), &WorldStreamer::set_chunk_generator);
	ClassDB::bind_method(D_METHOD("get_chunk_generator"), &WorldStreamer::get_chunk_generator);
	ClassDB::bind_method(D_METHOD("set_chunk_provider", "provider"), &WorldStreamer::set_chunk_provider);
	ClassDB::bind_method(D_METHOD("get_chunk_provider"), &WorldStreamer::get_chunk_provider);
	ClassDB::bind_method(D_METHOD("set_chunk_parent", "parent"), &WorldStreamer::set_chunk_parent);
	ClassDB::bind_method(D_METHOD("get_chunk_parent"), &WorldStreamer::get_chunk_parent);
	ClassDB::bind_method(D_METHOD("set_position_chunks", "enabled"), &WorldStreamer::set_position_chunks);
	ClassDB::bind_method(D_METHOD("get_position_chunks"), &WorldStreamer::get_position_chunks);
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &WorldStreamer::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &WorldStreamer::is_enabled);

	ClassDB::bind_method(D_METHOD("world_to_cell", "position"), &WorldStreamer::world_to_cell);
	ClassDB::bind_method(D_METHOD("cell_to_world", "cell"), &WorldStreamer::cell_to_world);
	ClassDB::bind_method(D_METHOD("is_cell_loaded", "cell"), &WorldStreamer::is_cell_loaded);
	ClassDB::bind_method(D_METHOD("get_chunk", "cell"), &WorldStreamer::get_chunk);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &WorldStreamer::get_loaded_cells);
	ClassDB::bind_method(D_METHOD("get_loaded_count"), &WorldStreamer::get_loaded_count);
	ClassDB::bind_method(D_METHOD("get_pending_count"), &WorldStreamer::get_pending_count);
	ClassDB::bind_method(D_METHOD("refresh", "retry"), &WorldStreamer::refresh, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("unload_all"), &WorldStreamer::unload_all);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "focus", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node2D,Node3D"), "set_focus", "get_focus");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "focus_position", PROPERTY_HINT_NONE, "suffix:m"), "set_focus_position", "get_focus_position");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "axes", PROPERTY_HINT_ENUM, "XZ (3D ground),XY (2D),XYZ (volume)"), "set_axes", "get_axes");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,100000,0.1,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "load_radius", PROPERTY_HINT_RANGE, "0,100000,0.1,or_greater,suffix:m"), "set_load_radius", "get_load_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "unload_radius", PROPERTY_HINT_RANGE, "0,100000,0.1,or_greater,suffix:m"), "set_unload_radius", "get_unload_radius");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "chunk_path_template", PROPERTY_HINT_NONE, ""), "set_chunk_path_template", "get_chunk_path_template");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "chunk_parent", PROPERTY_HINT_NONE, ""), "set_chunk_parent", "get_chunk_parent");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "position_chunks"), "set_position_chunks", "get_position_chunks");
	ADD_GROUP("Budget", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_loads", PROPERTY_HINT_RANGE, "1,64,1,or_greater"), "set_max_concurrent_loads", "get_max_concurrent_loads");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_instantiations_per_frame", PROPERTY_HINT_RANGE, "1,16,1,or_greater"), "set_max_instantiations_per_frame", "get_max_instantiations_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "update_interval", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater,suffix:s"), "set_update_interval", "get_update_interval");

	ADD_SIGNAL(MethodInfo("chunk_loaded", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::OBJECT, "chunk", PROPERTY_HINT_RESOURCE_TYPE, "Node")));
	ADD_SIGNAL(MethodInfo("chunk_unloaded", PropertyInfo(Variant::VECTOR3I, "cell")));
	ADD_SIGNAL(MethodInfo("chunk_load_failed", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::STRING, "path")));

	BIND_ENUM_CONSTANT(AXES_XZ);
	BIND_ENUM_CONSTANT(AXES_XY);
	BIND_ENUM_CONSTANT(AXES_XYZ);
}
