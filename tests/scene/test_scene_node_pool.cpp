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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_scene_node_pool)

#include "scene/main/scene_node_pool.h"
#include "scene/resources/packed_scene.h"

namespace TestSceneNodePool {

TEST_CASE("[SceneNodePool] Prewarm, reuse, overload and eviction") {
	Ref<PackedScene> scene;
	scene.instantiate();
	Node *prototype = memnew(Node);
	CHECK(scene->pack(prototype) == OK);
	memdelete(prototype);

	SceneNodePool pool;
	pool.set_template_scene(scene);
	pool.set_max_idle(2);
	pool.set_max_active(2);
	CHECK(pool.prewarm(20) == 2);
	CHECK(pool.prewarm(2) == 0);
	CHECK(pool.get_idle_count() == 2);

	Node *root = memnew(Node);
	Node *a = pool.acquire(root);
	Node *b = pool.acquire(root);
	REQUIRE(a != nullptr);
	REQUIRE(b != nullptr);
	CHECK(a != b);
	CHECK(pool.get_active_count() == 2);
	CHECK(pool.acquire(root) == nullptr);
	CHECK(pool.get_stats()["rejected_total"] == 1);

	Node *foreign = memnew(Node);
	CHECK_FALSE(pool.release(foreign));
	memdelete(foreign);
	CHECK(pool.release(a));
	CHECK_FALSE(pool.release(a));
	CHECK(pool.acquire(root) == a);
	CHECK(pool.get_stats()["created_total"] == 2);
	CHECK(pool.get_stats()["reused_total"] == 3);

	CHECK(pool.release(a));
	CHECK(pool.release(b));
	CHECK(pool.get_idle_count() == 2);
	CHECK(pool.get_stats()["peak_active"] == 2);

	// External code may still hold the returned pointer and free it:
	// the idle cache must never dereference or resurrect a dangling pointer.
	memdelete(a);
	CHECK(pool.get_idle_count() == 1);
	CHECK(pool.prewarm(2) == 1);
	CHECK(pool.get_idle_count() == 2);

	pool.set_max_idle(1);
	CHECK(pool.get_idle_count() == 1);
	pool.clear_idle();
	CHECK(pool.get_idle_count() == 0);
	pool.set_max_idle(0);
	Node *uncached = pool.acquire(root);
	REQUIRE(uncached != nullptr);
	CHECK(pool.release(uncached));
	CHECK(pool.get_idle_count() == 0);

	Node *external_free = pool.acquire(root);
	REQUIRE(external_free != nullptr);
	memdelete(external_free);
	CHECK(pool.get_active_count() == 0);
	CHECK(pool.get_stats()["disposed_total"] == 3);

	memdelete(root);
}

TEST_CASE("[SceneNodePool] Cannot change template while checked out") {
	Ref<PackedScene> first_scene;
	first_scene.instantiate();
	Node *source = memnew(Node);
	REQUIRE(first_scene->pack(source) == OK);
	memdelete(source);

	SceneNodePool pool;
	pool.set_template_scene(first_scene);
	Node *host = memnew(Node);
	Node *leased = pool.acquire(host);
	REQUIRE(leased != nullptr);
	CHECK(pool.get_active_count() == 1);
	CHECK(pool.get_template_scene() == first_scene);
	CHECK(pool.release(leased));
	pool.clear_idle();
	memdelete(host);
}


TEST_CASE("[SceneNodePool] Incremental residency honors per-frame budget and protects active leases") {
	Ref<PackedScene> scene;
	scene.instantiate();
	Node *source = memnew(Node);
	REQUIRE(scene->pack(source) == OK);
	memdelete(source);

	SceneNodePool pool;
	pool.set_template_scene(scene);
	pool.set_max_idle(6);
	pool.set_max_active(2);
	pool.set_prewarm_on_ready(false);
	CHECK(pool.maintain_residency(-1, 2) == 0);
	CHECK(pool.maintain_residency(4097, 2) == 0);
	CHECK(pool.maintain_residency(6, -1) == 0);
	CHECK(pool.maintain_residency(6, 65) == 0);
	CHECK(pool.maintain_residency(6, 0) == 0);
	CHECK(pool.get_idle_count() == 0);
	CHECK(pool.maintain_residency(6, 2) == 2);
	CHECK(pool.maintain_residency(6, 2) == 2);
	CHECK(pool.maintain_residency(6, 2) == 2);
	CHECK(pool.maintain_residency(6, 2) == 0);
	CHECK(pool.get_idle_count() == 6);
	CHECK(int(pool.get_stats()["created_total"]) == 6);

	Node *host = memnew(Node);
	Node *a = pool.acquire(host);
	Node *b = pool.acquire(host);
	REQUIRE(a != nullptr);
	REQUIRE(b != nullptr);
	CHECK(pool.get_active_count() == 2);
	CHECK(pool.get_idle_count() == 4);
	CHECK(pool.maintain_residency(6, 2) == 0);
	CHECK(int(pool.get_stats()["created_total"]) == 6);
	CHECK(pool.release(a));
	CHECK(pool.release(b));
	CHECK(pool.get_active_count() == 0);
	CHECK(pool.get_idle_count() == 6);

	CHECK(pool.maintain_residency(2, 1) == -1);
	CHECK(pool.maintain_residency(2, 1) == -1);
	CHECK(pool.maintain_residency(2, 2) == -2);
	CHECK(pool.maintain_residency(2, 2) == 0);
	CHECK(pool.get_idle_count() == 2);
	CHECK(int(pool.get_stats()["disposed_total"]) == 4);

	a = pool.acquire(host);
	b = pool.acquire(host);
	REQUIRE(a != nullptr);
	REQUIRE(b != nullptr);
	CHECK(pool.maintain_residency(0, 2) == 0);
	CHECK(pool.get_active_count() == 2); // Never disposes checked-out nodes.
	CHECK(pool.release(a));
	CHECK(pool.maintain_residency(0, 2) == -1);
	CHECK(pool.get_active_count() == 1);
	CHECK(pool.release(b));
	CHECK(pool.maintain_residency(0, 2) == -1);
	CHECK(pool.get_idle_count() == 0);
	CHECK(int(pool.get_stats()["disposed_total"]) == 6);
	memdelete(host);

	// No scene template: a maintenance query cannot spawn anything.
	SceneNodePool empty;
	CHECK(empty.maintain_residency(8, 2) == 0);
}


TEST_CASE("[SceneNodePool] CPU-sliced residency preserves active leases and exposes pending work") {
	Ref<PackedScene> scene;
	scene.instantiate();
	Node *prototype = memnew(Node);
	REQUIRE(scene->pack(prototype) == OK);
	memdelete(prototype);

	CHECK_FALSE(SceneNodePool::should_stop_maintenance(0, 3, 100));
	CHECK_FALSE(SceneNodePool::should_stop_maintenance(1, 0, 100));
	CHECK_FALSE(SceneNodePool::should_stop_maintenance(100, 1, 99));
	CHECK(SceneNodePool::should_stop_maintenance(100, 1, 100));
	CHECK(SceneNodePool::should_stop_maintenance(100, 2, 200));

	SceneNodePool pool;
	pool.set_template_scene(scene);
	pool.set_max_idle(6);
	CHECK(pool.get_last_maintenance_change_count() == 0);
	CHECK(pool.get_last_maintenance_pending_count() == 0);
	CHECK(pool.get_last_maintenance_work_usec() == 0);
	CHECK(pool.maintain_residency(6, 2, -1) == 0);
	CHECK(pool.maintain_residency(6, 2, 1000001) == 0);
	CHECK(pool.get_idle_count() == 0);
	const int first = pool.maintain_residency(6, 2, 1);
	CHECK(first >= 1);
	CHECK(first <= 2);
	CHECK(pool.get_last_maintenance_change_count() == first);
	CHECK(pool.get_last_maintenance_pending_count() == 6 - first);
	CHECK(pool.get_last_maintenance_work_usec() >= 0);
	CHECK(int(pool.get_stats()["maintenance_pending"]) == 6 - first);
	while (pool.get_idle_count() < 6) {
		CHECK(pool.maintain_residency(6, 2, 0) > 0);
	}
	CHECK(pool.get_last_maintenance_pending_count() == 0);
	Node *host = memnew(Node);
	Node *checked_out = pool.acquire(host);
	REQUIRE(checked_out != nullptr);
	const int retired = pool.maintain_residency(0, 2, 1);
	CHECK(retired <= -1);
	CHECK(retired >= -2);
	CHECK(pool.get_active_count() == 1);
	CHECK(pool.get_last_maintenance_change_count() == retired);
	CHECK(pool.get_last_maintenance_pending_count() == pool.get_idle_count());
	CHECK(pool.release(checked_out));
	while (pool.get_idle_count() > 0) {
		CHECK(pool.maintain_residency(0, 2, 0) < 0);
	}
	CHECK(pool.get_last_maintenance_pending_count() == 0);
	CHECK(pool.maintain_residency(0, 2, 0) == 0);
	CHECK(pool.get_last_maintenance_change_count() == 0);
	memdelete(host);
}

} // namespace TestSceneNodePool
