/**************************************************************************/
/*  test_render_dependency_hash_map.cpp                                   */
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

TEST_FORCE_LINK(test_render_dependency_hash_map)

#include "core/templates/a_hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/rid.h"

namespace TestRenderDependencyHashMap {

static RID fake_rid(uint64_t p_id) {
	return RID::from_uint64(p_id + 1);
}

struct DependencyGraph {
	AHashMap<RID, HashSet<RID>> dependencies;
	AHashMap<RID, HashSet<RID>> reverse;

	void add(RID p_dependent, RID p_dependency) {
		dependencies[p_dependency].insert(p_dependent);
		reverse[p_dependent].insert(p_dependency);
	}

	void replace(RID p_dependent, RID p_old, RID p_new) {
		HashSet<RID> *set = dependencies.getptr(p_old);
		if (set) {
			set->erase(p_dependent);
		}
		set = reverse.getptr(p_dependent);
		if (set) {
			set->erase(p_old);
		}
		add(p_dependent, p_new);
	}

	// Mirror RenderingDevice's relookup: recursive frees can relocate AHashMap entries.
	void free_node(RID p_id) {
		while (true) {
			AHashMap<RID, HashSet<RID>>::Iterator E = dependencies.find(p_id);
			if (!E) {
				break;
			}
			if (E->value.is_empty()) {
				dependencies.erase(p_id);
				break;
			}
			RID dependent = *E->value.begin();
			free_node(dependent);
		}

		AHashMap<RID, HashSet<RID>>::Iterator E = reverse.find(p_id);
		if (E) {
			for (RID dependency : E->value) {
				AHashMap<RID, HashSet<RID>>::Iterator G = dependencies.find(dependency);
				if (G) {
					G->value.erase(p_id);
				}
			}
			reverse.remove(E);
		}
	}
};

TEST_CASE("[RenderDependencyMap] Nested dependency sets preserve keys through growth") {
	AHashMap<RID, HashSet<RID>> map;
	for (int i = 0; i < 2048; ++i) {
		map[fake_rid(i)].insert(fake_rid(i + 10000));
	}
	REQUIRE_EQ(map.size(), 2048);
	for (int i = 0; i < 2048; ++i) {
		const HashSet<RID> *set = map.getptr(fake_rid(i));
		REQUIRE(set != nullptr);
		CHECK(set->has(fake_rid(i + 10000)));
	}
}

TEST_CASE("[RenderDependencyMap] Erasing map keys preserves relocated nested sets") {
	AHashMap<RID, HashSet<RID>> map;
	for (int i = 0; i < 1024; i++) {
		map[fake_rid(i)].insert(fake_rid(i + 5000));
	}
	for (int i = 0; i < 1024; i += 2) {
		CHECK(map.erase(fake_rid(i)));
	}
	CHECK_EQ(map.size(), 512);
	for (int i = 1; i < 1024; i += 2) {
		const HashSet<RID> *set = map.getptr(fake_rid(i));
		REQUIRE(set != nullptr);
		CHECK(set->has(fake_rid(i + 5000)));
	}
}

TEST_CASE("[RenderDependencyMap] Recursive freeing relooks up after container relocation") {
	DependencyGraph graph;
	const RID root = fake_rid(1);
	for (int i = 0; i < 64; ++i) {
		const RID child = fake_rid(200 + i);
		const RID leaf = fake_rid(1000 + i);
		graph.add(child, root);
		graph.add(leaf, child);
	}
	graph.free_node(root);
	CHECK(graph.dependencies.is_empty());
	CHECK(graph.reverse.is_empty());
}

TEST_CASE("[RenderDependencyMap] Replacing a dependency preserves both directions") {
	DependencyGraph graph;
	const RID child = fake_rid(7);
	const RID old_parent = fake_rid(8);
	const RID new_parent = fake_rid(9);
	graph.add(child, old_parent);
	graph.replace(child, old_parent, new_parent);
	CHECK_FALSE(graph.dependencies[old_parent].has(child));
	CHECK(graph.dependencies[new_parent].has(child));
	CHECK(graph.reverse[child].has(new_parent));
	CHECK_FALSE(graph.reverse[child].has(old_parent));
	graph.free_node(new_parent);
	CHECK(graph.reverse.is_empty());
	CHECK(graph.dependencies[old_parent].is_empty());
}

TEST_CASE("[RenderDependencyMap] Duplicate edges are idempotent") {
	DependencyGraph graph;
	RID dependent = fake_rid(99);
	RID owner = fake_rid(100);
	graph.add(dependent, owner);
	graph.add(dependent, owner);
	CHECK_EQ(graph.dependencies[owner].size(), 1);
	CHECK_EQ(graph.reverse[dependent].size(), 1);
	graph.free_node(owner);
	CHECK(graph.dependencies.is_empty());
	CHECK(graph.reverse.is_empty());
}

TEST_CASE("[RenderDependencyMap] Clear and reserve allow repeated resource lifecycles") {
	AHashMap<RID, HashSet<RID>> map;
	map.reserve(1024);
	for (int i = 0; i < 1024; i++) {
		map[fake_rid(i)].insert(fake_rid(i + 2048));
	}
	CHECK_EQ(map.size(), 1024);
	map.clear();
	CHECK(map.is_empty());
	for (int i = 0; i < 1024; i++) {
		map[fake_rid(i)].insert(fake_rid(i + 4096));
	}
	CHECK_EQ(map.size(), 1024);
	for (int i = 0; i < 1024; i++) {
		CHECK(map[fake_rid(i)].has(fake_rid(i + 4096)));
	}
}

} // namespace TestRenderDependencyHashMap
