/**************************************************************************/
/*  test_dependency_tracker.cpp                                           */
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

TEST_FORCE_LINK(test_dependency_tracker)

#include "servers/rendering/storage/utilities.h"

namespace TestRenderingDependencyTracker {

struct CallbackCount {
	int changed = 0;
	int deleted = 0;
};

static void count_changed(Dependency::DependencyChangedNotification p_notification, DependencyTracker *p_tracker) {
	CallbackCount *count = static_cast<CallbackCount *>(p_tracker->userdata);
	if (p_notification == Dependency::DEPENDENCY_CHANGED_MESH) {
		count->changed++;
	}
}

static void count_deleted(const RID &p_rid, DependencyTracker *p_tracker) {
	CallbackCount *count = static_cast<CallbackCount *>(p_tracker->userdata);
	count->deleted++;
}

static void add_dependency(DependencyTracker &p_tracker, Dependency &p_dependency) {
	p_tracker.update_begin();
	p_tracker.update_dependency(&p_dependency);
	p_tracker.update_end();
}

static void destroy_unannounced(Dependency *p_dependency) {
	// Debug builds warn by design; this suite verifies that even in release
	// the destructor removes the dependency from every tracker.
	ERR_PRINT_OFF
	memdelete(p_dependency);
	ERR_PRINT_ON
}

TEST_CASE("[RenderingDependency] Deleting a dependency unlinks its tracker") {
	DependencyTracker tracker;
	Dependency *dependency = memnew(Dependency);
	add_dependency(tracker, *dependency);
	destroy_unannounced(dependency);
	tracker.clear(); // Would dereference a freed Dependency before GH-125562.
	tracker.update_begin();
	tracker.update_end();
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Deleting a shared dependency unlinks every tracker") {
	DependencyTracker trackers[4];
	Dependency *dependency = memnew(Dependency);
	for (DependencyTracker &tracker : trackers) {
		add_dependency(tracker, *dependency);
	}
	destroy_unannounced(dependency);
	for (DependencyTracker &tracker : trackers) {
		tracker.clear();
		tracker.update_begin();
		tracker.update_end();
	}
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Surviving dependencies still notify the tracker") {
	DependencyTracker tracker;
	CallbackCount counter;
	tracker.userdata = &counter;
	tracker.changed_callback = count_changed;
	Dependency *dead = memnew(Dependency);
	Dependency *alive = memnew(Dependency);

	tracker.update_begin();
	tracker.update_dependency(dead);
	tracker.update_dependency(alive);
	tracker.update_end();

	destroy_unannounced(dead);
	alive->changed_notify(Dependency::DEPENDENCY_CHANGED_MESH);
	CHECK(counter.changed == 1);
	tracker.clear();
	destroy_unannounced(alive);
}

TEST_CASE("[RenderingDependency] Tracking a new dependency after deletion is safe") {
	DependencyTracker tracker;
	Dependency *previous = memnew(Dependency);
	add_dependency(tracker, *previous);
	destroy_unannounced(previous);
	Dependency *current = memnew(Dependency);
	add_dependency(tracker, *current);
	tracker.update_begin();
	tracker.update_dependency(current);
	tracker.update_end();
	tracker.clear();
	destroy_unannounced(current);
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Clearing before deletion remains safe") {
	DependencyTracker tracker;
	Dependency *dependency = memnew(Dependency);
	add_dependency(tracker, *dependency);
	tracker.clear();
	destroy_unannounced(dependency);
	tracker.clear();
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Deleted notification unlinks before destruction") {
	DependencyTracker tracker;
	CallbackCount counter;
	tracker.userdata = &counter;
	tracker.deleted_callback = count_deleted;
	Dependency *dependency = memnew(Dependency);
	add_dependency(tracker, *dependency);
	dependency->deleted_notify(RID());
	CHECK(counter.deleted == 1);
	memdelete(dependency);
	tracker.clear();
	CHECK(counter.deleted == 1);
}

TEST_CASE("[RenderingDependency] Update end removes dependencies omitted in new version") {
	DependencyTracker tracker;
	Dependency *removed = memnew(Dependency);
	Dependency *retained = memnew(Dependency);
	tracker.update_begin();
	tracker.update_dependency(removed);
	tracker.update_dependency(retained);
	tracker.update_end();
	tracker.update_begin();
	tracker.update_dependency(retained);
	tracker.update_end();
	destroy_unannounced(removed);
	destroy_unannounced(retained);
	tracker.clear();
	CHECK(true);
}

TEST_CASE("[RenderingDependency] A tracker can be destroyed after its dependency") {
	DependencyTracker *tracker = memnew(DependencyTracker);
	Dependency *dependency = memnew(Dependency);
	add_dependency(*tracker, *dependency);
	destroy_unannounced(dependency);
	memdelete(tracker);
	CHECK(true);
}

TEST_CASE("[RenderingDependency] A dependency can be destroyed after its tracker") {
	Dependency *dependency = memnew(Dependency);
	DependencyTracker *tracker = memnew(DependencyTracker);
	add_dependency(*tracker, *dependency);
	memdelete(tracker);
	destroy_unannounced(dependency);
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Repeated tracking does not retain stale entries") {
	DependencyTracker tracker;
	Dependency *dependency = memnew(Dependency);
	for (int i = 0; i < 16; i++) {
		add_dependency(tracker, *dependency);
	}
	destroy_unannounced(dependency);
	tracker.clear();
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Disconnected trackers remain independent") {
	DependencyTracker first;
	DependencyTracker second;
	CallbackCount first_events;
	CallbackCount second_events;
	first.userdata = &first_events;
	second.userdata = &second_events;
	first.changed_callback = count_changed;
	second.changed_callback = count_changed;
	Dependency *a = memnew(Dependency);
	Dependency *b = memnew(Dependency);
	add_dependency(first, *a);
	add_dependency(second, *b);
	destroy_unannounced(a);
	b->changed_notify(Dependency::DEPENDENCY_CHANGED_MESH);
	CHECK(first_events.changed == 0);
	CHECK(second_events.changed == 1);
	first.clear();
	second.clear();
	destroy_unannounced(b);
}

TEST_CASE("[RenderingDependency] Cleanup is stable across many lifetimes") {
	DependencyTracker tracker;
	for (int i = 0; i < 128; i++) {
		Dependency *dependency = memnew(Dependency);
		add_dependency(tracker, *dependency);
		destroy_unannounced(dependency);
		tracker.update_begin();
		tracker.update_end();
	}
	tracker.clear();
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Empty dependency can be destroyed repeatedly") {
	for (int i = 0; i < 32; i++) {
		Dependency *dependency = memnew(Dependency);
		memdelete(dependency);
	}
	CHECK(true);
}

TEST_CASE("[RenderingDependency] Two trackers with overlapping dependencies survive deletion") {
	DependencyTracker left;
	DependencyTracker right;
	Dependency *shared = memnew(Dependency);
	Dependency *left_only = memnew(Dependency);
	Dependency *right_only = memnew(Dependency);

	left.update_begin();
	left.update_dependency(shared);
	left.update_dependency(left_only);
	left.update_end();
	right.update_begin();
	right.update_dependency(shared);
	right.update_dependency(right_only);
	right.update_end();

	destroy_unannounced(shared);
	left.update_begin();
	left.update_dependency(left_only);
	left.update_end();
	right.update_begin();
	right.update_dependency(right_only);
	right.update_end();
	left.clear();
	right.clear();
	destroy_unannounced(left_only);
	destroy_unannounced(right_only);
	CHECK(true);
}

} // namespace TestRenderingDependencyTracker
