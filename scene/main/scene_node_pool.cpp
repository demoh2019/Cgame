/**************************************************************************/
/*  scene_node_pool.h                                                     */
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

#include "scene_node_pool.h"

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/variant/dictionary.h"


void SceneNodePool::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY && prewarm_on_ready) {
		prewarm(prewarm_count);
	}
}

SceneNodePool::~SceneNodePool() {
	clear_idle();
}

void SceneNodePool::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_template_scene", "scene"), &SceneNodePool::set_template_scene);
	ClassDB::bind_method(D_METHOD("get_template_scene"), &SceneNodePool::get_template_scene);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "template", PROPERTY_HINT_RESOURCE_TYPE, "PackedScene"), "set_template_scene", "get_template_scene");

	ClassDB::bind_method(D_METHOD("set_prewarm_count", "count"), &SceneNodePool::set_prewarm_count);
	ClassDB::bind_method(D_METHOD("get_prewarm_count"), &SceneNodePool::get_prewarm_count);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "prewarm_count", PROPERTY_HINT_RANGE, "0,4096,1"), "set_prewarm_count", "get_prewarm_count");

	ClassDB::bind_method(D_METHOD("set_max_idle", "count"), &SceneNodePool::set_max_idle);
	ClassDB::bind_method(D_METHOD("get_max_idle"), &SceneNodePool::get_max_idle);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_idle", PROPERTY_HINT_RANGE, "0,4096,1"), "set_max_idle", "get_max_idle");

	ClassDB::bind_method(D_METHOD("set_max_active", "count"), &SceneNodePool::set_max_active);
	ClassDB::bind_method(D_METHOD("get_max_active"), &SceneNodePool::get_max_active);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_active", PROPERTY_HINT_RANGE, "0,4096,1"), "set_max_active", "get_max_active");

	ClassDB::bind_method(D_METHOD("set_prewarm_on_ready", "enabled"), &SceneNodePool::set_prewarm_on_ready);
	ClassDB::bind_method(D_METHOD("is_prewarm_on_ready"), &SceneNodePool::is_prewarm_on_ready);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "prewarm_on_ready"), "set_prewarm_on_ready", "is_prewarm_on_ready");

	ClassDB::bind_method(D_METHOD("prewarm", "count"), &SceneNodePool::prewarm);
	ClassDB::bind_method(D_METHOD("acquire", "parent"), &SceneNodePool::acquire);
	ClassDB::bind_method(D_METHOD("release", "instance"), &SceneNodePool::release);
	ClassDB::bind_method(D_METHOD("release_deferred", "instance"), &SceneNodePool::release_deferred);
	ClassDB::bind_method(D_METHOD("clear_idle"), &SceneNodePool::clear_idle);
	ClassDB::bind_method(D_METHOD("get_active_count"), &SceneNodePool::get_active_count);
	ClassDB::bind_method(D_METHOD("get_idle_count"), &SceneNodePool::get_idle_count);
	ClassDB::bind_method(D_METHOD("get_stats"), &SceneNodePool::get_stats);

	ADD_SIGNAL(MethodInfo("capacity_exhausted"));
	ADD_SIGNAL(MethodInfo("instance_acquired", PropertyInfo(Variant::OBJECT, "instance", PROPERTY_HINT_NODE_TYPE, "Node")));
	ADD_SIGNAL(MethodInfo("instance_released", PropertyInfo(Variant::OBJECT, "instance", PROPERTY_HINT_NODE_TYPE, "Node")));
}

void SceneNodePool::set_template_scene(const Ref<PackedScene> &p_scene) {
	if (template_scene == p_scene) {
		return;
	}
	_prune_active();
	ERR_FAIL_COND_MSG(!active.is_empty(), "Cannot change a SceneNodePool template with active instances.");
	clear_idle();
	template_scene = p_scene;
}

void SceneNodePool::set_max_idle(int p_count) {
	max_idle = CLAMP(p_count, 0, 4096);
	_prune_idle();
	while (idle.size() > max_idle) {
		const ObjectID id = idle[idle.size() - 1];
		idle.remove_at(idle.size() - 1);
		Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(id));
		if (instance != nullptr && !instance->is_queued_for_deletion()) {
			memdelete(instance);
			disposed_total++;
		}
	}
}

void SceneNodePool::_prune_active() {
	Vector<ObjectID> stale;
	for (const ObjectID &id : active) {
		Object *object = ObjectDB::get_instance(id);
		Node *node = Object::cast_to<Node>(object);
		if (node == nullptr || node->is_queued_for_deletion()) {
			stale.push_back(id);
		}
	}
	for (const ObjectID &id : stale) {
		active.erase(id);
	}
}

void SceneNodePool::_prune_idle() {
	for (int i = idle.size() - 1; i >= 0; i--) {
		Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(idle[i]));
		if (instance == nullptr || instance->is_queued_for_deletion()) {
			idle.remove_at(i);
		}
	}
}

Node *SceneNodePool::_new_instance() {
	if (template_scene.is_null()) {
		return nullptr;
	}
	Node *instance = template_scene->instantiate();
	if (instance != nullptr) {
		created_total++;
		if (instance->has_method(SNAME("on_pool_created"))) {
			instance->call(SNAME("on_pool_created"));
		}
	}
	return instance;
}

int SceneNodePool::prewarm(int p_target) {
	if (template_scene.is_null()) {
		return 0;
	}
	_prune_idle();
	const int target = MIN(MAX(0, p_target), max_idle);
	int added = 0;
	while (idle.size() < target) {
		Node *instance = _new_instance();
		if (instance == nullptr) {
			break;
		}
		idle.push_back(instance->get_instance_id());
		added++;
	}
	return added;
}

Node *SceneNodePool::acquire(Node *p_parent) {
	if (template_scene.is_null() || p_parent == nullptr || p_parent->is_queued_for_deletion()) {
		return nullptr;
	}
	_prune_active();
	if (max_active > 0 && int(active.size()) >= max_active) {
		rejected_total++;
		emit_signal(SNAME("capacity_exhausted"));
		return nullptr;
	}
	Node *instance = nullptr;
	while (!idle.is_empty()) {
		const ObjectID cached_id = idle[idle.size() - 1];
		idle.remove_at(idle.size() - 1);
		instance = Object::cast_to<Node>(ObjectDB::get_instance(cached_id));
		if (instance != nullptr && !instance->is_queued_for_deletion()) {
			reused_total++;
			break;
		}
		instance = nullptr;
	}
	if (instance == nullptr) {
		instance = _new_instance();
	}
	if (instance == nullptr) {
		return nullptr;
	}
	const ObjectID id = instance->get_instance_id();
	p_parent->add_child(instance);
	// add_child() may run user scripts that queue a child for deletion.
	if (ObjectDB::get_instance(id) != instance || instance->is_queued_for_deletion()) {
		return nullptr;
	}
	active.insert(id);
	peak_active = MAX(peak_active, int(active.size()));
	if (instance->has_method(SNAME("on_pool_acquired"))) {
		instance->call(SNAME("on_pool_acquired"), this);
	}
	emit_signal(SNAME("instance_acquired"), instance);
	return ObjectDB::get_instance(id) == instance && !instance->is_queued_for_deletion() ? instance : nullptr;
}

bool SceneNodePool::release(Node *p_instance) {
	if (p_instance == nullptr || p_instance->is_queued_for_deletion()) {
		return false;
	}
	const ObjectID id = p_instance->get_instance_id();
	if (!active.has(id) || ObjectDB::get_instance(id) != p_instance) {
		return false;
	}
	active.erase(id);
	if (p_instance->has_method(SNAME("on_pool_released"))) {
		p_instance->call(SNAME("on_pool_released"));
	}
	Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(id));
	if (instance == nullptr || instance->is_queued_for_deletion()) {
		return true;
	}
	if (instance->get_parent() != nullptr) {
		instance->get_parent()->remove_child(instance);
	}
	released_total++;
	_prune_idle();
	if (idle.size() < max_idle) {
		idle.push_back(id);
	} else {
		instance->queue_free();
		disposed_total++;
	}
	// Signals fire after registration, so handlers can immediately acquire
	// the just-released object without racing the pool's bookkeeping.
	emit_signal(SNAME("instance_released"), instance);
	return true;
}

void SceneNodePool::release_deferred(Node *p_instance) {
	call_deferred(SNAME("release"), p_instance);
}

void SceneNodePool::clear_idle() {
	for (const ObjectID &id : idle) {
		Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(id));
		if (instance != nullptr && !instance->is_queued_for_deletion()) {
			memdelete(instance);
			disposed_total++;
		}
	}
	idle.clear();
}

int SceneNodePool::get_active_count() {
	_prune_active();
	return active.size();
}

int SceneNodePool::get_idle_count() {
	_prune_idle();
	return idle.size();
}

Dictionary SceneNodePool::get_stats() {
	_prune_active();
	_prune_idle();
	Dictionary stats;
	stats["active"] = active.size();
	stats["idle"] = idle.size();
	stats["created_total"] = created_total;
	stats["reused_total"] = reused_total;
	stats["released_total"] = released_total;
	stats["disposed_total"] = disposed_total;
	stats["rejected_total"] = rejected_total;
	stats["peak_active"] = peak_active;
	return stats;
}
