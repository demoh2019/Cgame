public:
// cull parameters is a convenient way of passing a bunch
// of arguments through the culling functions without
// writing loads of code. Not all members are used for some cull checks
struct CullParams {
	int result_count_overall; // both trees
	int result_count; // this tree only
	int result_max;
	T **result_array;
	int *subindex_array;

	// We now process masks etc in a user template function,
	// and these for simplicity assume even for cull tests there is a
	// testing object (which has masks etc) for the user cull checks.
	// This means for cull tests on their own, the client will usually
	// want to create a dummy object, just in order to specify masks etc.
	const T *tester;

	// optional components for different tests
	POINT point;
	BVHABB_CLASS abb;
	typename BVHABB_CLASS::ConvexHull hull;
	typename BVHABB_CLASS::Segment segment;

	// When collision testing, we can specify which tree ids
	// to collide test against with the tree_collision_mask.
	uint32_t tree_collision_mask;
};

private:
void _cull_translate_hits(CullParams &r_params) {
	int num_hits = _cull_hits.size();
	int left = r_params.result_max - r_params.result_count_overall;

	if (num_hits > left) {
		num_hits = left;
	}

	int out_n = r_params.result_count_overall;

	for (int n = 0; n < num_hits; n++) {
		uint32_t ref_id = _cull_hits[n];

		const ItemExtra &ex = _extra[ref_id];
		r_params.result_array[out_n] = ex.userdata;

		if (r_params.subindex_array) {
			r_params.subindex_array[out_n] = ex.subindex;
		}

		out_n++;
	}

	r_params.result_count = num_hits;
	r_params.result_count_overall += num_hits;
}

public:
int cull_convex(CullParams &r_params, bool p_translate_hits = true) {
	_cull_hits.clear();
	r_params.result_count = 0;
	// No matching tree or no output capacity: avoid traversing the BVH.
	if (r_params.tree_collision_mask == 0 || r_params.result_max <= 0) {
		return 0;
	}

	for (int n = 0; n < NUM_TREES; n++) {
		const uint32_t tree_test_mask = uint32_t(1) << n;

		if (_root_node_id[n] == BVHCommon::INVALID) {
			continue;
		}

		if (!(r_params.tree_collision_mask & tree_test_mask)) {
			continue;
		}

		_cull_convex_iterative(_root_node_id[n], r_params);
		if (_cull_hits_full(r_params)) {
			break;
		}
	}

	if (p_translate_hits) {
		_cull_translate_hits(r_params);
	}

	return r_params.result_count;
}

int cull_segment(CullParams &r_params, bool p_translate_hits = true) {
	_cull_hits.clear();
	r_params.result_count = 0;
	// No matching tree or no output capacity: avoid traversing the BVH.
	if (r_params.tree_collision_mask == 0 || r_params.result_max <= 0) {
		return 0;
	}

	for (int n = 0; n < NUM_TREES; n++) {
		const uint32_t tree_test_mask = uint32_t(1) << n;

		if (_root_node_id[n] == BVHCommon::INVALID) {
			continue;
		}

		if (!(r_params.tree_collision_mask & tree_test_mask)) {
			continue;
		}

		_cull_segment_iterative(_root_node_id[n], r_params);
		if (_cull_hits_full(r_params)) {
			break;
		}
	}

	if (p_translate_hits) {
		_cull_translate_hits(r_params);
	}

	return r_params.result_count;
}

// Walk the BVH without accumulating candidates into _cull_hits. The exact
// shape callback can shorten the ray; both inner nodes and leaves recheck the
// clipped segment as they are reached. This prevents false nearest hits when
// a segment crosses more than INTERSECTION_QUERY_MAX physics shapes.
using SegmentCastCallback = real_t (*)(T *, int, real_t, void *);
void cast_segment(const POINT &p_from, const POINT &p_to, SegmentCastCallback p_callback, void *p_userdata, uint32_t p_tree_collision_mask, const T *p_tester = nullptr) {
	if (!p_callback || p_tree_collision_mask == 0) {
		return;
	}

	// Visit the tree whose bounds are nearest to the ray origin first.
	// A near hit can clip away the other tree before any narrowphase work.
	typename BVHABB_CLASS::Segment segment;
	segment.from = p_from;
	segment.to = p_to;
	uint32_t roots[NUM_TREES];
	real_t entry_fractions[NUM_TREES];
	int root_count = 0;
	for (int n = 0; n < NUM_TREES; n++) {
		const uint32_t tree_test_mask = uint32_t(1) << n;
		const uint32_t root_id = _root_node_id[n];
		if (root_id == BVHCommon::INVALID || !(p_tree_collision_mask & tree_test_mask)) {
			continue;
		}
		real_t entry_fraction;
		if (!_nodes[root_id].aabb.intersects_segment(segment, &entry_fraction)) {
			continue;
		}
		// NUM_TREES is tiny (two for physics), so insertion sort is cheaper
		// than allocating a priority queue for a single ray cast.
		int insertion = root_count;
		while (insertion > 0 && entry_fractions[insertion - 1] > entry_fraction) {
			roots[insertion] = roots[insertion - 1];
			entry_fractions[insertion] = entry_fractions[insertion - 1];
			insertion--;
		}
		roots[insertion] = root_id;
		entry_fractions[insertion] = entry_fraction;
		root_count++;
	}

	real_t max_fraction = 1.0;
	for (int n = 0; n < root_count; n++) {
		_cast_segment_iterative(roots[n], p_from, p_to, p_callback, p_userdata, p_tester, max_fraction);
		if (max_fraction <= 0.0) {
			return;
		}
	}
}

// Stream query candidates directly to a caller-supplied narrowphase filter.
// Unlike cull_point/cull_aabb these visitors cannot discard valid results
// when a fixed-size candidate buffer is filled by filtered-out objects.
// Return false from a visitor to stop traversal once enough actual hits exist.
using QueryVisitor = bool (*)(T *, int, void *);

bool visit_point(const POINT &p_point, QueryVisitor p_visitor, void *p_userdata, uint32_t p_tree_collision_mask = 0xFFFFFFFF, const T *p_tester = nullptr) {
	if (!p_visitor || !p_tree_collision_mask) {
		return true;
	}
	for (int tree_index = 0; tree_index < NUM_TREES; ++tree_index) {
		if (!(p_tree_collision_mask & (uint32_t(1) << tree_index))) {
			continue;
		}
		const uint32_t root = _root_node_id[tree_index];
		if (root != BVHCommon::INVALID && !_visit_point_iterative(root, p_point, p_visitor, p_userdata, p_tester)) {
			return false;
		}
	}
	return true;
}

bool visit_aabb(const BOUNDS &p_aabb, QueryVisitor p_visitor, void *p_userdata, uint32_t p_tree_collision_mask = 0xFFFFFFFF, const T *p_tester = nullptr) {
	if (!p_visitor || !p_tree_collision_mask) {
		return true;
	}
	BVHABB_CLASS query;
	query.from(p_aabb);
	for (int tree_index = 0; tree_index < NUM_TREES; ++tree_index) {
		if (!(p_tree_collision_mask & (uint32_t(1) << tree_index))) {
			continue;
		}
		const uint32_t root = _root_node_id[tree_index];
		if (root != BVHCommon::INVALID && !_visit_aabb_iterative(root, query, p_visitor, p_userdata, p_tester)) {
			return false;
		}
	}
	return true;
}

private:
// Unlike the fixed-capacity cull variants, these routines apply the callback
// immediately, without storing any candidate ids or making heap allocations.
bool _visit_point_iterative(uint32_t p_node_id, const POINT &p_point, QueryVisitor p_visitor, void *p_userdata, const T *p_tester) {
	struct StackItem {
		uint32_t node_id;
	};
	BVH_IterativeInfo<StackItem> stack;
	stack.stack = (StackItem *)alloca(stack.get_alloca_stacksize());
	stack.get_first()->node_id = p_node_id;

	StackItem next;
	while (stack.pop(next)) {
		TNode &node = _nodes[next.node_id];
		if (!node.aabb.intersects_point(p_point)) {
			continue;
		}
		if (node.is_leaf()) {
			TLeaf &leaf = _node_get_leaf(node);
			for (int i = 0; i < leaf.num_items; ++i) {
				if (!leaf.get_aabb(i).intersects_point(p_point)) {
					continue;
				}
				const ItemExtra &extra = _extra[leaf.get_item_ref_id(i)];
				if (USE_PAIRS && !USER_CULL_TEST_FUNCTION::user_cull_check(p_tester, extra.userdata)) {
					continue;
				}
				if (!p_visitor(extra.userdata, extra.subindex, p_userdata)) {
					return false;
				}
			}
		} else {
			for (int i = 0; i < node.num_children; ++i) {
				const uint32_t child_id = node.children[i];
				if (_nodes[child_id].aabb.intersects_point(p_point)) {
					stack.request()->node_id = child_id;
				}
			}
		}
	}
	return true;
}

bool _visit_aabb_iterative(uint32_t p_node_id, const BVHABB_CLASS &p_query, QueryVisitor p_visitor, void *p_userdata, const T *p_tester) {
	// Mirror bounded cull_aabb's fully-within shortcut for streaming queries.
	// Once a subtree is contained in the query, none of its descendants need
	// per-proxy AABB tests; keep invoking the visitor to honor exact filters.
	const BVHABB_CLASS &root_bounds = _nodes[p_node_id].aabb;
	if (!root_bounds.intersects(p_query)) {
		return true;
	}

	struct StackItem {
		uint32_t node_id;
		bool fully_within;
	};
	BVH_IterativeInfo<StackItem> stack;
	stack.stack = (StackItem *)alloca(stack.get_alloca_stacksize());
	stack.get_first()->node_id = p_node_id;
	stack.get_first()->fully_within = p_query.is_other_within(root_bounds);

	// Pre-swizzling the query avoids two negations for each partially
	// intersecting item in dense leaves. Fully covered leaves skip this test.
	BVHABB_CLASS swizzled_query;
	swizzled_query.min = -p_query.neg_max;
	swizzled_query.neg_max = -p_query.min;

	StackItem next;
	while (stack.pop(next)) {
		TNode &node = _nodes[next.node_id];
		if (node.is_leaf()) {
			TLeaf &leaf = _node_get_leaf(node);
			for (int i = 0; i < leaf.num_items; ++i) {
				if (!next.fully_within && !swizzled_query.intersects_swizzled(leaf.get_aabb(i))) {
					continue;
				}
				const ItemExtra &extra = _extra[leaf.get_item_ref_id(i)];
				if (USE_PAIRS && !USER_CULL_TEST_FUNCTION::user_cull_check(p_tester, extra.userdata)) {
					continue;
				}
				if (!p_visitor(extra.userdata, extra.subindex, p_userdata)) {
					return false;
				}
			}
		} else {
			for (int i = 0; i < node.num_children; ++i) {
				const uint32_t child_id = node.children[i];
				const BVHABB_CLASS &child_bounds = _nodes[child_id].aabb;
				if (!next.fully_within && !child_bounds.intersects(p_query)) {
					continue;
				}
				StackItem *child = stack.request();
				child->node_id = child_id;
				child->fully_within = next.fully_within || p_query.is_other_within(child_bounds);
			}
		}
	}
	return true;
}

public:
int cull_point(CullParams &r_params, bool p_translate_hits = true) {
	_cull_hits.clear();
	r_params.result_count = 0;
	// No matching tree or no output capacity: avoid traversing the BVH.
	if (r_params.tree_collision_mask == 0 || r_params.result_max <= 0) {
		return 0;
	}

	for (int n = 0; n < NUM_TREES; n++) {
		const uint32_t tree_test_mask = uint32_t(1) << n;

		if (_root_node_id[n] == BVHCommon::INVALID) {
			continue;
		}

		if (!(r_params.tree_collision_mask & tree_test_mask)) {
			continue;
		}

		_cull_point_iterative(_root_node_id[n], r_params);
		if (_cull_hits_full(r_params)) {
			break;
		}
	}

	if (p_translate_hits) {
		_cull_translate_hits(r_params);
	}

	return r_params.result_count;
}

int cull_aabb(CullParams &r_params, bool p_translate_hits = true) {
	_cull_hits.clear();
	r_params.result_count = 0;
	// No matching tree or no output capacity: avoid traversing the BVH.
	if (r_params.tree_collision_mask == 0 || r_params.result_max <= 0) {
		return 0;
	}

	for (int n = 0; n < NUM_TREES; n++) {
		const uint32_t tree_test_mask = uint32_t(1) << n;

		if (_root_node_id[n] == BVHCommon::INVALID) {
			continue;
		}

		// the tree collision mask determines which trees to collide test against
		if (!(r_params.tree_collision_mask & tree_test_mask)) {
			continue;
		}

		_cull_aabb_iterative(_root_node_id[n], r_params);
		if (_cull_hits_full(r_params)) {
			break;
		}
	}

	if (p_translate_hits) {
		_cull_translate_hits(r_params);
	}

	return r_params.result_count;
}

bool _cull_hits_full(const CullParams &p_params) {
	// instead of checking every hit, we can do a lazy check for this condition.
	// it isn't a problem if we write too much _cull_hits because they only the
	// result_max amount will be translated and outputted. But we might as
	// well stop our cull checks after the maximum has been reached.
	return (int)_cull_hits.size() >= p_params.result_max;
}

void _cull_hit(uint32_t p_ref_id, CullParams &r_params) {
	// take into account masks etc
	// this would be more efficient to do before plane checks,
	// but done here for ease to get started
	if (USE_PAIRS) {
		const ItemExtra &ex = _extra[p_ref_id];

		// user supplied function (for e.g. pairable types and pairable masks in the render tree)
		if (!USER_CULL_TEST_FUNCTION::user_cull_check(r_params.tester, ex.userdata)) {
			return;
		}
	}

	_cull_hits.push_back(p_ref_id);
}

void _cast_segment_iterative(uint32_t p_node_id, const POINT &p_from, const POINT &p_to, SegmentCastCallback p_callback, void *p_userdata, const T *p_tester, real_t &r_max_fraction) {
	struct StackItem {
		uint32_t node_id;
	};
	BVH_IterativeInfo<StackItem> stack;
	stack.stack = (StackItem *)alloca(stack.get_alloca_stacksize());
	stack.get_first()->node_id = p_node_id;

	const POINT motion = p_to - p_from;
	typename BVHABB_CLASS::Segment segment;
	segment.from = p_from;
	segment.to = p_to;

	StackItem next;
	while (stack.pop(next)) {
		TNode &node = _nodes[next.node_id];
		if (!node.aabb.intersects_segment(segment)) {
			continue;
		}

		if (node.is_leaf()) {
			TLeaf &leaf = _node_get_leaf(node);

			// The BVH can store up to MAX_ITEMS shapes in each leaf. On dense
			// leaves, visit the closest *bounding box* first so an exact hit
			// can clip the segment before expensive shape tests on far items.
			// A single scan avoids sorting and allocates no additional memory.
			// Small leaves retain their existing one-pass fast path.
			int nearest_item = -1;
			if (leaf.num_items >= 16) {
				real_t nearest_entry = Math::INF;
				for (int i = 0; i < leaf.num_items; i++) {
					const BVHABB_CLASS &aabb = leaf.get_aabb(i);
					real_t entry;
					if (!aabb.intersects_segment(segment, &entry)) {
						continue;
					}
					if (nearest_item == -1 || entry < nearest_entry) {
						nearest_entry = entry;
						nearest_item = i;
					}
				}
				if (nearest_item == -1) {
					continue;
				}
			}

			// Visit the selected candidate first, then the remaining items
			// in their original order. This is a traversal *hint*, not a
			// correctness filter: every other possible hit is still tested.
			for (int i = nearest_item >= 0 ? -1 : 0; i < leaf.num_items; i++) {
				const int item_index = i < 0 ? nearest_item : i;
				if (i >= 0 && i == nearest_item) {
					continue;
				}
				if (i >= 0 && !leaf.get_aabb(item_index).intersects_segment(segment)) {
					continue;
				}
				const ItemExtra &extra = _extra[leaf.get_item_ref_id(item_index)];
				if (USE_PAIRS && !USER_CULL_TEST_FUNCTION::user_cull_check(p_tester, extra.userdata)) {
					continue;
				}
				const real_t fraction = p_callback(extra.userdata, extra.subindex, r_max_fraction, p_userdata);
				if (fraction >= 0.0 && fraction < r_max_fraction) {
					r_max_fraction = fraction;
					if (r_max_fraction == 0.0) {
						return;
					}
					segment.to = p_from + motion * r_max_fraction;
				}
			}
		} else if (node.num_children == 2) {
			// The stack is LIFO: push the farther intersecting child first,
			// so the nearer child can shorten the ray before it is visited.
			const uint32_t child_a = node.children[0];
			const uint32_t child_b = node.children[1];
			const BVHABB_CLASS &bounds_a = _nodes[child_a].aabb;
			const BVHABB_CLASS &bounds_b = _nodes[child_b].aabb;
			real_t entry_a;
			real_t entry_b;
			const bool hit_a = bounds_a.intersects_segment(segment, &entry_a);
			const bool hit_b = bounds_b.intersects_segment(segment, &entry_b);
			if (hit_a && hit_b) {
				if (entry_a <= entry_b) {
					stack.request()->node_id = child_b;
					stack.request()->node_id = child_a;
				} else {
					stack.request()->node_id = child_a;
					stack.request()->node_id = child_b;
				}
			} else if (hit_a) {
				stack.request()->node_id = child_a;
			} else if (hit_b) {
				stack.request()->node_id = child_b;
			}
		} else {
			// The current BVH has binary nodes; preserve the generic
			// fallback for other MAX_CHILDREN configurations.
			for (int i = 0; i < node.num_children; i++) {
				const uint32_t child_id = node.children[i];
				if (_nodes[child_id].aabb.intersects_segment(segment)) {
					stack.request()->node_id = child_id;
				}
			}
		}
	}
}

bool _cull_segment_iterative(uint32_t p_node_id, CullParams &r_params) {
	// our function parameters to keep on a stack
	struct CullSegParams {
		uint32_t node_id;
	};

	// most of the iterative functionality is contained in this helper class
	BVH_IterativeInfo<CullSegParams> ii;

	// alloca must allocate the stack from this function, it cannot be allocated in the
	// helper class
	ii.stack = (CullSegParams *)alloca(ii.get_alloca_stacksize());

	// seed the stack
	ii.get_first()->node_id = p_node_id;

	CullSegParams csp;

	// while there are still more nodes on the stack
	while (ii.pop(csp)) {
		TNode &tnode = _nodes[csp.node_id];

		if (tnode.is_leaf()) {
			// lazy check for hits full up condition
			if (_cull_hits_full(r_params)) {
				return false;
			}

			TLeaf &leaf = _node_get_leaf(tnode);

			// test children individually
			for (int n = 0; n < leaf.num_items; n++) {
				const BVHABB_CLASS &aabb = leaf.get_aabb(n);

				if (aabb.intersects_segment(r_params.segment)) {
					uint32_t child_id = leaf.get_item_ref_id(n);

					// register hit
					_cull_hit(child_id, r_params);
					if (_cull_hits_full(r_params)) {
						return false;
					}
				}
			}
		} else {
			// test children individually
			for (int n = 0; n < tnode.num_children; n++) {
				uint32_t child_id = tnode.children[n];
				const BVHABB_CLASS &child_abb = _nodes[child_id].aabb;

				if (child_abb.intersects_segment(r_params.segment)) {
					// add to the stack
					CullSegParams *child = ii.request();
					child->node_id = child_id;
				}
			}
		}

	} // while more nodes to pop

	// true indicates results are not full
	return true;
}

bool _cull_point_iterative(uint32_t p_node_id, CullParams &r_params) {
	// our function parameters to keep on a stack
	struct CullPointParams {
		uint32_t node_id;
	};

	// most of the iterative functionality is contained in this helper class
	BVH_IterativeInfo<CullPointParams> ii;

	// alloca must allocate the stack from this function, it cannot be allocated in the
	// helper class
	ii.stack = (CullPointParams *)alloca(ii.get_alloca_stacksize());

	// seed the stack
	ii.get_first()->node_id = p_node_id;

	CullPointParams cpp;

	// while there are still more nodes on the stack
	while (ii.pop(cpp)) {
		TNode &tnode = _nodes[cpp.node_id];
		// no hit with this node?
		if (!tnode.aabb.intersects_point(r_params.point)) {
			continue;
		}

		if (tnode.is_leaf()) {
			// lazy check for hits full up condition
			if (_cull_hits_full(r_params)) {
				return false;
			}

			TLeaf &leaf = _node_get_leaf(tnode);

			// test children individually
			for (int n = 0; n < leaf.num_items; n++) {
				if (leaf.get_aabb(n).intersects_point(r_params.point)) {
					uint32_t child_id = leaf.get_item_ref_id(n);

					// register hit
					_cull_hit(child_id, r_params);
					if (_cull_hits_full(r_params)) {
						return false;
					}
				}
			}
		} else {
			// test children individually
			for (int n = 0; n < tnode.num_children; n++) {
				uint32_t child_id = tnode.children[n];

				// add to the stack
				CullPointParams *child = ii.request();
				child->node_id = child_id;
			}
		}

	} // while more nodes to pop

	// true indicates results are not full
	return true;
}

// Note: This is a very hot loop profiling wise. Take care when changing this and profile.
bool _cull_aabb_iterative(uint32_t p_node_id, CullParams &r_params, bool p_fully_within = false) {
	// our function parameters to keep on a stack
	struct CullAABBParams {
		uint32_t node_id;
		bool fully_within;
	};

	// most of the iterative functionality is contained in this helper class
	BVH_IterativeInfo<CullAABBParams> ii;

	// alloca must allocate the stack from this function, it cannot be allocated in the
	// helper class
	ii.stack = (CullAABBParams *)alloca(ii.get_alloca_stacksize());

	// seed the stack
	ii.get_first()->node_id = p_node_id;
	ii.get_first()->fully_within = p_fully_within;

	CullAABBParams cap;

	// while there are still more nodes on the stack
	while (ii.pop(cap)) {
		TNode &tnode = _nodes[cap.node_id];

		if (tnode.is_leaf()) {
			// lazy check for hits full up condition
			if (_cull_hits_full(r_params)) {
				return false;
			}

			TLeaf &leaf = _node_get_leaf(tnode);

			// if fully within we can just add all items
			// as long as they pass mask checks
			if (cap.fully_within) {
				for (int n = 0; n < leaf.num_items; n++) {
					uint32_t child_id = leaf.get_item_ref_id(n);

					// register hit
					_cull_hit(child_id, r_params);
					if (_cull_hits_full(r_params)) {
						return false;
					}
				}
			} else {
				// This section is the hottest area in profiling, so
				// is optimized highly
				// get this into a local register and preconverted to correct type
				int leaf_num_items = leaf.num_items;

				BVHABB_CLASS swizzled_tester;
				swizzled_tester.min = -r_params.abb.neg_max;
				swizzled_tester.neg_max = -r_params.abb.min;

				for (int n = 0; n < leaf_num_items; n++) {
					const BVHABB_CLASS &aabb = leaf.get_aabb(n);

					if (swizzled_tester.intersects_swizzled(aabb)) {
						uint32_t child_id = leaf.get_item_ref_id(n);

						// register hit
						_cull_hit(child_id, r_params);
						if (_cull_hits_full(r_params)) {
							return false;
						}
					}
				}

			} // not fully within
		} else {
			if (!cap.fully_within) {
				// test children individually
				for (int n = 0; n < tnode.num_children; n++) {
					uint32_t child_id = tnode.children[n];
					const BVHABB_CLASS &child_abb = _nodes[child_id].aabb;

					if (child_abb.intersects(r_params.abb)) {
						// is the node totally within the aabb?
						bool fully_within = r_params.abb.is_other_within(child_abb);

						// add to the stack
						CullAABBParams *child = ii.request();

						// should always return valid child
						child->node_id = child_id;
						child->fully_within = fully_within;
					}
				}
			} else {
				for (int n = 0; n < tnode.num_children; n++) {
					uint32_t child_id = tnode.children[n];

					// add to the stack
					CullAABBParams *child = ii.request();

					// should always return valid child
					child->node_id = child_id;
					child->fully_within = true;
				}
			}
		}

	} // while more nodes to pop

	// true indicates results are not full
	return true;
}

// returns full up with results
bool _cull_convex_iterative(uint32_t p_node_id, CullParams &r_params, bool p_fully_within = false) {
	// our function parameters to keep on a stack
	struct CullConvexParams {
		uint32_t node_id;
		bool fully_within;
	};

	// most of the iterative functionality is contained in this helper class
	BVH_IterativeInfo<CullConvexParams> ii;

	// alloca must allocate the stack from this function, it cannot be allocated in the
	// helper class
	ii.stack = (CullConvexParams *)alloca(ii.get_alloca_stacksize());

	// seed the stack
	ii.get_first()->node_id = p_node_id;
	ii.get_first()->fully_within = p_fully_within;

	// preallocate these as a once off to be reused
	uint32_t max_planes = r_params.hull.num_planes;
	uint32_t *plane_ids = (uint32_t *)alloca(sizeof(uint32_t) * max_planes);

	CullConvexParams ccp;

	// while there are still more nodes on the stack
	while (ii.pop(ccp)) {
		const TNode &tnode = _nodes[ccp.node_id];

		if (!ccp.fully_within) {
			typename BVHABB_CLASS::IntersectResult res = tnode.aabb.intersects_convex(r_params.hull);

			switch (res) {
				default: {
					continue; // miss, just move on to the next node in the stack
				} break;
				case BVHABB_CLASS::IR_PARTIAL: {
				} break;
				case BVHABB_CLASS::IR_FULL: {
					ccp.fully_within = true;
				} break;
			}

		} // if not fully within already

		if (tnode.is_leaf()) {
			// lazy check for hits full up condition
			if (_cull_hits_full(r_params)) {
				return false;
			}

			const TLeaf &leaf = _node_get_leaf(tnode);

			// if fully within, simply add all items to the result
			// (taking into account masks)
			if (ccp.fully_within) {
				for (int n = 0; n < leaf.num_items; n++) {
					uint32_t child_id = leaf.get_item_ref_id(n);

					// register hit
					_cull_hit(child_id, r_params);
					if (_cull_hits_full(r_params)) {
						return false;
					}
				}

			} else {
				// we can either use a naive check of all the planes against the AABB,
				// or an optimized check, which finds in advance which of the planes can possibly
				// cut the AABB, and only tests those. This can be much faster.
#define BVH_CONVEX_CULL_OPTIMIZED
#ifdef BVH_CONVEX_CULL_OPTIMIZED
				// first find which planes cut the aabb
				uint32_t num_planes = tnode.aabb.find_cutting_planes(r_params.hull, plane_ids);
				BVH_ASSERT(num_planes <= max_planes);

//#define BVH_CONVEX_CULL_OPTIMIZED_RIGOR_CHECK
#ifdef BVH_CONVEX_CULL_OPTIMIZED_RIGOR_CHECK
				// rigorous check
				uint32_t results[MAX_ITEMS];
				uint32_t num_results = 0;
#endif

				// test children individually
				for (int n = 0; n < leaf.num_items; n++) {
					//const Item &item = leaf.get_item(n);
					const BVHABB_CLASS &aabb = leaf.get_aabb(n);

					if (aabb.intersects_convex_optimized(r_params.hull, plane_ids, num_planes)) {
						uint32_t child_id = leaf.get_item_ref_id(n);

#ifdef BVH_CONVEX_CULL_OPTIMIZED_RIGOR_CHECK
						results[num_results++] = child_id;
#endif

						// register hit
						_cull_hit(child_id, r_params);
						if (_cull_hits_full(r_params)) {
							return false;
						}
					}
				}

#ifdef BVH_CONVEX_CULL_OPTIMIZED_RIGOR_CHECK
				uint32_t test_count = 0;

				for (int n = 0; n < leaf.num_items; n++) {
					const BVHABB_CLASS &aabb = leaf.get_aabb(n);

					if (aabb.intersects_convex_partial(r_params.hull)) {
						uint32_t child_id = leaf.get_item_ref_id(n);

						CRASH_COND(child_id != results[test_count++]);
						CRASH_COND(test_count > num_results);
					}
				}
#endif

#else
				// not BVH_CONVEX_CULL_OPTIMIZED
				// test children individually
				for (int n = 0; n < leaf.num_items; n++) {
					const BVHABB_CLASS &aabb = leaf.get_aabb(n);

					if (aabb.intersects_convex_partial(r_params.hull)) {
						uint32_t child_id = leaf.get_item_ref_id(n);

						// full up with results? exit early, no point in further testing
						_cull_hit(child_id, r_params);
						if (_cull_hits_full(r_params)) {
							return false;
						}
					}
				}
#endif // BVH_CONVEX_CULL_OPTIMIZED
			} // if not fully within
		} else {
			for (int n = 0; n < tnode.num_children; n++) {
				uint32_t child_id = tnode.children[n];

				// add to the stack
				CullConvexParams *child = ii.request();

				// should always return valid child
				child->node_id = child_id;
				child->fully_within = ccp.fully_within;
			}
		}

	} // while more nodes to pop

	// true indicates results are not full
	return true;
}
