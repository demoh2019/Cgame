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

#pragma once

#include "core/templates/hash_set.h"
#include "core/templates/vector.h"
#include "scene/main/node.h"
#include "scene/resources/packed_scene.h"

// Native alternative to the game's GDScript RuntimeNodePool: detached idle
// PackedScene instances and weak active IDs, without retaining external nodes.
class SceneNodePool : public Node {
	GDCLASS(SceneNodePool, Node);

	Ref<PackedScene> template_scene;
	Vector<ObjectID> idle; // Cached IDs survive external free()/queue_free().
	HashSet<ObjectID> active;
	int prewarm_count = 0;
	int max_idle = 32;
	int max_active = 0; // Zero means no cap.
	bool prewarm_on_ready = true;

	uint64_t created_total = 0;
	uint64_t reused_total = 0;
	uint64_t released_total = 0;
	uint64_t disposed_total = 0;
	uint64_t rejected_total = 0;
	int peak_active = 0;
	// Last *explicit* residency maintenance invocation (not acquire/release).
	int64_t last_maintenance_work_usec = 0;
	int last_maintenance_change_count = 0; // Signed: created +, disposed -.
	int last_maintenance_pending_count = 0;

	Node *_new_instance();
	void _prune_active();
	void _prune_idle();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_template_scene(const Ref<PackedScene> &p_scene);
	Ref<PackedScene> get_template_scene() const { return template_scene; }

	void set_prewarm_count(int p_count) { prewarm_count = CLAMP(p_count, 0, 4096); }
	int get_prewarm_count() const { return prewarm_count; }
	void set_max_idle(int p_count);
	int get_max_idle() const { return max_idle; }
	void set_max_active(int p_count) { max_active = CLAMP(p_count, 0, 4096); }
	int get_max_active() const { return max_active; }
	void set_prewarm_on_ready(bool p_enabled) { prewarm_on_ready = p_enabled; }
	bool is_prewarm_on_ready() const { return prewarm_on_ready; }

	int prewarm(int p_target);
	// Signed number of instances created (+) or idle instances disposed (-).
	// Target applies to all live leases + idle cache; never evicts checked-out
	// instances. Work is bounded to at most 64 changes per invocation.
	int maintain_residency(int p_target_total, int p_max_changes = 2, int p_max_work_usec = 0);
	int64_t get_last_maintenance_work_usec() const { return last_maintenance_work_usec; }
	int get_last_maintenance_change_count() const { return last_maintenance_change_count; }
	int get_last_maintenance_pending_count() const { return last_maintenance_pending_count; }
	// A positive CPU cap is soft: the first indivisible scene operation
	// always progresses; later operations stop after the deadline.
	static bool should_stop_maintenance(int p_work_usec, int p_completed_changes, int64_t p_elapsed_usec);
	Node *acquire(Node *p_parent);
	bool release(Node *p_instance);
	void release_deferred(Node *p_instance);
	void clear_idle();
	int get_active_count();
	int get_idle_count();
	Dictionary get_stats();

	~SceneNodePool();
};
