/**************************************************************************/
/*  bvh.h                                                                 */
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

// BVH
// This class provides a wrapper around BVH tree, which contains most of the functionality
// for a dynamic BVH with templated leaf size.
// However BVH also adds facilities for pairing, to maintain compatibility with Godot 3.2.
// Pairing is a collision pairing system, on top of the basic BVH.

// Some notes on the use of BVH / Octree from Godot 3.2.
// This is not well explained elsewhere.
// The rendering tree mask and types that are sent to the BVH are NOT layer masks.
// They are INSTANCE_TYPES (defined in visual_server.h), e.g. MESH, MULTIMESH, PARTICLES etc.
// Thus the lights do no cull by layer mask in the BVH.

// Layer masks are implemented in the renderers as a later step, and light_cull_mask appears to be
// implemented in GLES3 but not GLES2. Layer masks are not yet implemented for directional lights.

// In the physics, the pairable_type is based on 1 << p_object->get_type() where:
// TYPE_AREA,
// TYPE_BODY
// and pairable_mask is either 0 if static, or set to all if non static

#include "core/math/bvh_tree.h"
#include "core/math/geometry_3d.h"
#include "core/os/mutex.h"
#include "core/templates/hash_set.h"


#define BVHTREE_CLASS BVH_Tree<T, NUM_TREES, 2, MAX_ITEMS, USER_PAIR_TEST_FUNCTION, USER_CULL_TEST_FUNCTION, USE_PAIRS, BOUNDS, POINT>
#define BVH_LOCKED_FUNCTION BVHLockedFunction _lock_guard(&_mutex, BVH_THREAD_SAFE &&_thread_safe);

template <typename T, int NUM_TREES = 1, bool USE_PAIRS = false, int MAX_ITEMS = 32, typename USER_PAIR_TEST_FUNCTION = BVH_DummyPairTestFunction<T>, typename USER_CULL_TEST_FUNCTION = BVH_DummyCullTestFunction<T>, typename BOUNDS = AABB, typename POINT = Vector3, bool BVH_THREAD_SAFE = true>
class BVH_Manager {
public:
	// note we are using uint32_t instead of BVHHandle, losing type safety, but this
	// is for compatibility with octree
	typedef void *(*PairCallback)(void *, uint32_t, T *, int, uint32_t, T *, int);
	typedef void (*UnpairCallback)(void *, uint32_t, T *, int, uint32_t, T *, int, void *);
	typedef void *(*CheckPairCallback)(void *, uint32_t, T *, int, uint32_t, T *, int, void *);

	// allow locally toggling thread safety if the template has been compiled with BVH_THREAD_SAFE
	void params_set_thread_safe(bool p_enable) {
		_thread_safe = p_enable;
	}

	// these 2 are crucial for fine tuning, and can be applied manually
	// see the variable declarations for more info.
	void params_set_node_expansion(real_t p_value) {
		BVH_LOCKED_FUNCTION
		if (p_value >= 0.0) {
			tree._node_expansion = p_value;
			tree._auto_node_expansion = false;
		} else {
			tree._auto_node_expansion = true;
		}
	}

	void params_set_pairing_expansion(real_t p_value) {
		BVH_LOCKED_FUNCTION
		tree.params_set_pairing_expansion(p_value);
	}

	void set_pair_callback(PairCallback p_callback, void *p_userdata) {
		BVH_LOCKED_FUNCTION
		pair_callback = p_callback;
		pair_callback_userdata = p_userdata;
	}
	void set_unpair_callback(UnpairCallback p_callback, void *p_userdata) {
		BVH_LOCKED_FUNCTION
		unpair_callback = p_callback;
		unpair_callback_userdata = p_userdata;
	}
	void set_check_pair_callback(CheckPairCallback p_callback, void *p_userdata) {
		BVH_LOCKED_FUNCTION
		check_pair_callback = p_callback;
		check_pair_callback_userdata = p_userdata;
	}

	BVHHandle create(T *p_userdata, bool p_active = true, uint32_t p_tree_id = 0, uint32_t p_tree_collision_mask = 1, const BOUNDS &p_aabb = BOUNDS(), int p_subindex = 0, bool p_defer_pairing = false) {
		BVH_LOCKED_FUNCTION

		// not sure if absolutely necessary to flush collisions here. It will cost performance to, instead
		// of waiting for update, so only uncomment this if there are bugs.
		if (USE_PAIRS) {
			//_check_for_collisions();
		}

		BVHHandle h = tree.item_add(p_userdata, p_active, p_aabb, p_subindex, p_tree_id, p_tree_collision_mask);

		if (USE_PAIRS) {
			// for safety initialize the expanded AABB
			BOUNDS &expanded_aabb = tree._pairs[h.id()].expanded_aabb;
			expanded_aabb = p_aabb;
			expanded_aabb.grow_by(tree._pairing_expansion);

			// force a collision check no matter the AABB
			if (p_active) {
				_add_changed_item(h, p_aabb, false);
				if (!p_defer_pairing) {
					_check_for_collisions(true);
				}
			}
		}

		return h;
	}

	// Flush explicitly deferred insertions once all shapes in a batch are
	// registered. Existing pairs need only geometric checks here: set_tree()
	// and force_collision_check() already validate changed collision filters.
	// New pairs are filtered by _collide() when they are created.
	void flush_pending_pairs() {
		BVH_LOCKED_FUNCTION
		if (USE_PAIRS) {
			_check_for_collisions();
		}
	}

	////////////////////////////////////////////////////
	// wrapper versions that use uint32_t instead of handle
	// for backward compatibility. Less type safe
	void move(uint32_t p_handle, const BOUNDS &p_aabb) {
		BVHHandle h;
		h.set(p_handle);
		move(h, p_aabb);
	}

	void recheck_pairs(uint32_t p_handle) {
		BVHHandle h;
		h.set(p_handle);
		recheck_pairs(h);
	}

	void erase(uint32_t p_handle) {
		BVHHandle h;
		h.set(p_handle);
		erase(h);
	}

	void force_collision_check(uint32_t p_handle) {
		BVHHandle h;
		h.set(p_handle);
		force_collision_check(h);
	}

	bool activate(uint32_t p_handle, const BOUNDS &p_aabb, bool p_delay_collision_check = false) {
		BVHHandle h;
		h.set(p_handle);
		return activate(h, p_aabb, p_delay_collision_check);
	}

	bool deactivate(uint32_t p_handle) {
		BVHHandle h;
		h.set(p_handle);
		return deactivate(h);
	}

	void set_tree(uint32_t p_handle, uint32_t p_tree_id, uint32_t p_tree_collision_mask, bool p_force_collision_check = true) {
		BVHHandle h;
		h.set(p_handle);
		set_tree(h, p_tree_id, p_tree_collision_mask, p_force_collision_check);
	}

	uint32_t get_tree_id(uint32_t p_handle) const {
		BVHHandle h;
		h.set(p_handle);
		BVH_LOCKED_FUNCTION
		return item_get_tree_id(h);
	}
	int get_subindex(uint32_t p_handle) const {
		BVHHandle h;
		h.set(p_handle);
		BVH_LOCKED_FUNCTION
		return item_get_subindex(h);
	}

	T *get(uint32_t p_handle) const {
		BVHHandle h;
		h.set(p_handle);
		BVH_LOCKED_FUNCTION
		return item_get_userdata(h);
	}

	////////////////////////////////////////////////////

	void move(BVHHandle p_handle, const BOUNDS &p_aabb) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		if (tree.item_move(p_handle, p_aabb)) {
			if (USE_PAIRS) {
				_add_changed_item(p_handle, p_aabb);
			}
		}
	}

	void recheck_pairs(BVHHandle p_handle) {
		DEV_ASSERT(!p_handle.is_invalid());
		force_collision_check(p_handle);
	}

	// Refresh cached pair metadata without recreating contacts or changing
	// collision filters. Pair-check callbacks may replace userdata; both
	// endpoints are kept synchronized through their reciprocal indices.
	void refresh_pair_userdata(BVHHandle p_handle) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		if (USE_PAIRS && check_pair_callback) {
			_recheck_pairs(p_handle);
		}
	}

	void erase(BVHHandle p_handle) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		// call unpair and remove all references to the item
		// before deleting from the tree
		if (USE_PAIRS) {
			_remove_changed_item(p_handle);
		}

		tree.item_remove(p_handle);

		_check_for_collisions(true);
	}

	// use in conjunction with activate if you have deferred the collision check, and
	// set pairable has never been called.
	// (deferred collision checks are a workaround for visual server for historical reasons)
	void force_collision_check(BVHHandle p_handle) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		if (USE_PAIRS) {
			// the aabb should already be up to date in the BVH
			BOUNDS aabb;
			item_get_AABB(p_handle, aabb);

			// add it as changed even if aabb not different
			_add_changed_item(p_handle, aabb, false);

			// force an immediate full collision check, much like calls to set_pairable
			_check_for_collisions(true);
		}
	}

	// these should be read as set_visible for render trees,
	// but generically this makes items add or remove from the
	// tree internally, to speed things up by ignoring inactive items
	bool activate(BVHHandle p_handle, const BOUNDS &p_aabb, bool p_delay_collision_check = false) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		// sending the aabb here prevents the need for the BVH to maintain
		// a redundant copy of the aabb.
		// returns success
		if (tree.item_activate(p_handle, p_aabb)) {
			if (USE_PAIRS) {
				// in the special case of the render tree, when setting visibility we are using the combination of
				// activate then set_pairable. This would case 2 sets of collision checks. For efficiency here we allow
				// deferring to have a single collision check at the set_pairable call.
				// Watch for bugs! This may cause bugs if set_pairable is not called.
				if (!p_delay_collision_check) {
					_add_changed_item(p_handle, p_aabb, false);

					// force an immediate collision check, much like calls to set_pairable
					_check_for_collisions(true);
				}
			}
			return true;
		}

		return false;
	}

	bool deactivate(BVHHandle p_handle) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		// returns success
		if (tree.item_deactivate(p_handle)) {
			// call unpair and remove all references to the item
			// before deleting from the tree
			if (USE_PAIRS) {
				_remove_changed_item(p_handle);

				// force check for collisions, much like an erase was called
				_check_for_collisions(true);
			}
			return true;
		}

		return false;
	}

	bool get_active(BVHHandle p_handle) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		return tree.item_get_active(p_handle);
	}

	// call e.g. once per frame (this does a trickle optimize)
	void update() {
		BVH_LOCKED_FUNCTION
		tree.update();
		_check_for_collisions();
#ifdef BVH_INTEGRITY_CHECKS
		tree._integrity_check_all();
#endif
	}

	// this can be called more frequently than per frame if necessary
	void update_collisions() {
		BVH_LOCKED_FUNCTION
		_check_for_collisions();
	}

	// prefer calling this directly as type safe
	void set_tree(const BVHHandle &p_handle, uint32_t p_tree_id, uint32_t p_tree_collision_mask, bool p_force_collision_check = true) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVH_LOCKED_FUNCTION
		// Returns true if the pairing state has changed.
		bool state_changed = tree.item_set_tree(p_handle, p_tree_id, p_tree_collision_mask);

		if (USE_PAIRS) {
			// not sure if absolutely necessary to flush collisions here. It will cost performance to, instead
			// of waiting for update, so only uncomment this if there are bugs.
			//_check_for_collisions();

			if ((p_force_collision_check || state_changed) && tree.item_get_active(p_handle)) {
				// when the pairable state changes, we need to force a collision check because newly pairable
				// items may be in collision, and unpairable items might move out of collision.
				// We cannot depend on waiting for the next update, because that may come much later.
				BOUNDS aabb;
				item_get_AABB(p_handle, aabb);

				// passing false disables the optimization which prevents collision checks if
				// the aabb hasn't changed
				_add_changed_item(p_handle, aabb, false);

				// force an immediate collision check (probably just for this one item)
				// but it must be a FULL collision check, also checking pairable state and masks.
				// This is because AABB intersecting objects may have changed pairable state / mask
				// such that they should no longer be paired. E.g. lights.
				_check_for_collisions(true);
			} // only if active
		}
	}

	// cull tests
	int cull_aabb(const BOUNDS &p_aabb, T **p_result_array, int p_result_max, const T *p_tester, uint32_t p_tree_collision_mask = 0xFFFFFFFF, int *p_subindex_array = nullptr) {
		BVH_LOCKED_FUNCTION
		typename BVHTREE_CLASS::CullParams params;

		params.result_count_overall = 0;
		params.result_max = p_result_max;
		params.result_array = p_result_array;
		params.subindex_array = p_subindex_array;
		params.tree_collision_mask = p_tree_collision_mask;
		params.abb.from(p_aabb);
		params.tester = p_tester;

		tree.cull_aabb(params);

		return params.result_count_overall;
	}

	int cull_segment(const POINT &p_from, const POINT &p_to, T **p_result_array, int p_result_max, const T *p_tester, uint32_t p_tree_collision_mask = 0xFFFFFFFF, int *p_subindex_array = nullptr) {
		BVH_LOCKED_FUNCTION
		typename BVHTREE_CLASS::CullParams params;

		params.result_count_overall = 0;
		params.result_max = p_result_max;
		params.result_array = p_result_array;
		params.subindex_array = p_subindex_array;
		params.tester = p_tester;
		params.tree_collision_mask = p_tree_collision_mask;

		params.segment.from = p_from;
		params.segment.to = p_to;

		tree.cull_segment(params);

		return params.result_count_overall;
	}

	// Stream segment candidates directly to the narrowphase callback. Unlike
	// cull_segment(), this does not stop after a fixed-size result buffer is full.
	// Callback returns a new ray fraction in [0, p_max_fraction], clipping
	// subsequent BVH traversal after a closer exact hit.
	using SegmentCastCallback = real_t (*)(T *, int, real_t, void *);
	void cast_segment(const POINT &p_from, const POINT &p_to, SegmentCastCallback p_callback, void *p_userdata, uint32_t p_tree_collision_mask = 0xFFFFFFFF, const T *p_tester = nullptr) {
		BVH_LOCKED_FUNCTION
		tree.cast_segment(p_from, p_to, p_callback, p_userdata, p_tree_collision_mask, p_tester);
	}

	// Stream point/AABB candidates instead of returning a fixed number of
	// unfiltered proxies. A false visitor result stops traversal immediately.
	using QueryVisitor = bool (*)(T *, int, void *);
	bool visit_point(const POINT &p_point, QueryVisitor p_visitor, void *p_userdata, uint32_t p_tree_collision_mask = 0xFFFFFFFF, const T *p_tester = nullptr) {
		BVH_LOCKED_FUNCTION
		return tree.visit_point(p_point, p_visitor, p_userdata, p_tree_collision_mask, p_tester);
	}

	bool visit_aabb(const BOUNDS &p_aabb, QueryVisitor p_visitor, void *p_userdata, uint32_t p_tree_collision_mask = 0xFFFFFFFF, const T *p_tester = nullptr) {
		BVH_LOCKED_FUNCTION
		return tree.visit_aabb(p_aabb, p_visitor, p_userdata, p_tree_collision_mask, p_tester);
	}

	int cull_point(const POINT &p_point, T **p_result_array, int p_result_max, const T *p_tester, uint32_t p_tree_collision_mask = 0xFFFFFFFF, int *p_subindex_array = nullptr) {
		BVH_LOCKED_FUNCTION
		typename BVHTREE_CLASS::CullParams params;

		params.result_count_overall = 0;
		params.result_max = p_result_max;
		params.result_array = p_result_array;
		params.subindex_array = p_subindex_array;
		params.tester = p_tester;
		params.tree_collision_mask = p_tree_collision_mask;

		params.point = p_point;

		tree.cull_point(params);
		return params.result_count_overall;
	}

	int cull_convex(const Vector<Plane> &p_convex, T **p_result_array, int p_result_max, const T *p_tester, uint32_t p_tree_collision_mask = 0xFFFFFFFF) {
		if (p_result_max <= 0 || p_convex.is_empty()) {
			// A zero-capacity query needs neither hull construction nor a tree traversal.
			return 0;
		}
		BVH_LOCKED_FUNCTION

		Vector<Vector3> convex_points = Geometry3D::compute_convex_mesh_points(&p_convex[0], p_convex.size());
		if (convex_points.is_empty()) {
			return 0;
		}

		typename BVHTREE_CLASS::CullParams params;
		params.result_count_overall = 0;
		params.result_max = p_result_max;
		params.result_array = p_result_array;
		params.subindex_array = nullptr;
		params.tester = p_tester;
		params.tree_collision_mask = p_tree_collision_mask;

		params.hull.planes = &p_convex[0];
		params.hull.num_planes = p_convex.size();
		params.hull.points = &convex_points[0];
		params.hull.num_points = convex_points.size();

		tree.cull_convex(params);

		return params.result_count_overall;
	}

private:
	// Existing dense-dense pairs are indexed globally, avoiding a per-object
	// hash table (and its memory overhead) on millions of sparse bodies.
	static constexpr uint32_t DENSE_PAIR_THRESHOLD = 32;

	static uint64_t _dense_pair_key(BVHHandle p_a, BVHHandle p_b) {
		const uint32_t a = MIN(p_a.id(), p_b.id());
		const uint32_t b = MAX(p_a.id(), p_b.id());
		return (uint64_t(a) << 32) | uint64_t(b);
	}

	// Called after adding both adjacency links. When a body crosses the
	// threshold, register all of its pairs with already-dense neighbors.
	void _index_new_dense_neighbors(BVHHandle p_handle) {
		const typename BVHTREE_CLASS::ItemPairs &pairs = tree._pairs[p_handle.id()];
		if (pairs.extended_pairs.size() != DENSE_PAIR_THRESHOLD) {
			return;
		}
		for (const typename BVHTREE_CLASS::ItemPairs::Link &link : pairs.extended_pairs) {
			if (tree._pairs[link.handle.id()].extended_pairs.size() >= DENSE_PAIR_THRESHOLD) {
				dense_pair_keys.insert(_dense_pair_key(p_handle, link.handle));
			}
		}
	}

	// Called only when an adjacency list falls from the threshold to one
	// below it. Dense-dense entries for its remaining links are now stale.
	void _unindex_new_sparse_neighbors(BVHHandle p_handle) {
		const typename BVHTREE_CLASS::ItemPairs &pairs = tree._pairs[p_handle.id()];
		for (const typename BVHTREE_CLASS::ItemPairs::Link &link : pairs.extended_pairs) {
			if (tree._pairs[link.handle.id()].extended_pairs.size() >= DENSE_PAIR_THRESHOLD) {
				dense_pair_keys.erase(_dense_pair_key(p_handle, link.handle));
			}
		}
	}

	// Pairing traverses candidate leaves directly. The original cull_aabb
	// filled _cull_hits for every changed proxy and then read the entire list
	// a second time, retaining memory proportional to the densest scene.
	void _check_for_collisions(bool p_full_check = false) {
		if (changed_items.is_empty()) {
			return;
		}

		struct PairVisit {
			BVH_Manager *manager;
			BVHHandle changed;
		};
		auto pair_visitor = [](uint32_t p_ref_id, void *p_userdata) -> bool {
			PairVisit &query = *static_cast<PairVisit *>(p_userdata);
			if (p_ref_id == query.changed.id()) {
				return true;
			}
			BVHHandle candidate;
			candidate.set_id(p_ref_id);
			// The callback changes pair adjacency, not BVH node topology.
			query.manager->_collide(query.changed, candidate);
			return true;
		};

		for (const BVHHandle &h : changed_items) {
			// Callbacks may grow pair adjacency storage: keep a stable AABB copy.
			const BOUNDS expanded_aabb = tree._pairs[h.id()].expanded_aabb;
			BVHABB_CLASS abb;
			abb.from(expanded_aabb);

			// Remove obsolete pairs first, preserving the full filter recheck
			// for static layer / collision exception changes.
			_find_leavers(h, abb, p_full_check);

			const typename BVHTREE_CLASS::ItemExtra &extra = _get_extra(h);
			PairVisit query = { this, h };
			tree.visit_aabb_refs(expanded_aabb, pair_visitor, &query, extra.tree_collision_mask, extra.userdata);
		}
		_reset();
	}

public:
	void item_get_AABB(BVHHandle p_handle, BOUNDS &r_aabb) {
		DEV_ASSERT(!p_handle.is_invalid());
		BVHABB_CLASS abb;
		BVH_LOCKED_FUNCTION
		tree.item_get_ABB(p_handle, abb);
		abb.to(r_aabb);
	}

private:
	// supplemental funcs
	uint32_t item_get_tree_id(BVHHandle p_handle) const { return _get_extra(p_handle).tree_id; }
	T *item_get_userdata(BVHHandle p_handle) const { return _get_extra(p_handle).userdata; }
	int item_get_subindex(BVHHandle p_handle) const { return _get_extra(p_handle).subindex; }

	// Unordered removal may move the last link into the deleted slot.
	// Update its partner's reciprocal index before compacting the list.
	void _remove_pair_link(BVHHandle p_owner, uint32_t p_index) {
		typename BVHTREE_CLASS::ItemPairs &pairs = tree._pairs[p_owner.id()];
		DEV_ASSERT(p_index < pairs.extended_pairs.size());
		const uint32_t last = pairs.extended_pairs.size() - 1;
		if (p_index != last) {
			const typename BVHTREE_CLASS::ItemPairs::Link moved = pairs.extended_pairs[last];
			typename BVHTREE_CLASS::ItemPairs &other = tree._pairs[moved.handle.id()];
			DEV_ASSERT(moved.reverse_index < other.extended_pairs.size());
			DEV_ASSERT(other.extended_pairs[moved.reverse_index].handle == p_owner);
			other.extended_pairs[moved.reverse_index].reverse_index = p_index;
		}
		pairs.remove_pair_at(p_index);
	}

	// The caller knows its adjacency index. The reciprocal index avoids
	// searching the partner's list to remove the corresponding link.
	void _unpair(BVHHandle p_from, BVHHandle p_to, uint32_t p_known_index) {
		const BVHHandle index_owner = p_from;
		tree._handle_sort(p_from, p_to);

		typename BVHTREE_CLASS::ItemExtra &exa = tree._extra[p_from.id()];
		typename BVHTREE_CLASS::ItemExtra &exb = tree._extra[p_to.id()];

		// if the userdata is the same, no collisions should occur
		if ((exa.userdata == exb.userdata) && exa.userdata) {
			return;
		}

		typename BVHTREE_CLASS::ItemPairs &pairs_from = tree._pairs[p_from.id()];
		typename BVHTREE_CLASS::ItemPairs &pairs_to = tree._pairs[p_to.id()];

		const uint32_t from_degree = pairs_from.extended_pairs.size();
		const uint32_t to_degree = pairs_to.extended_pairs.size();
		if (from_degree >= DENSE_PAIR_THRESHOLD && to_degree >= DENSE_PAIR_THRESHOLD) {
			dense_pair_keys.erase(_dense_pair_key(p_from, p_to));
		}

		uint32_t from_index;
		uint32_t to_index;
		if (index_owner == p_from) {
			from_index = p_known_index;
			DEV_ASSERT(from_index < from_degree);
			to_index = pairs_from.extended_pairs[from_index].reverse_index;
		} else {
			to_index = p_known_index;
			DEV_ASSERT(to_index < to_degree);
			from_index = pairs_to.extended_pairs[to_index].reverse_index;
		}
		DEV_ASSERT(from_index < from_degree && to_index < to_degree);
		DEV_ASSERT(pairs_from.extended_pairs[from_index].handle == p_to);
		DEV_ASSERT(pairs_to.extended_pairs[to_index].handle == p_from);
		void *ud_from = pairs_from.extended_pairs[from_index].userdata;
		_remove_pair_link(p_from, from_index);
		_remove_pair_link(p_to, to_index);
		if (from_degree == DENSE_PAIR_THRESHOLD) {
			_unindex_new_sparse_neighbors(p_from);
		}
		if (to_degree == DENSE_PAIR_THRESHOLD) {
			_unindex_new_sparse_neighbors(p_to);
		}
		// Avoid touching the hash allocator for the overwhelmingly common
		// sparse-sparse unlink, which could never have been indexed.
		if ((from_degree >= DENSE_PAIR_THRESHOLD || to_degree >= DENSE_PAIR_THRESHOLD) &&
				dense_pair_keys.is_empty()) {
			dense_pair_keys.reset();
		}

#ifdef BVH_VERBOSE_PAIRING
		print_line("_unpair " + itos(p_from.id()) + " from " + itos(p_to.id()));
#endif

		// callback
		if (unpair_callback) {
			unpair_callback(unpair_callback_userdata, p_from, exa.userdata, exa.subindex, p_to, exb.userdata, exb.subindex, ud_from);
		}
	}

	void *_recheck_pair(BVHHandle p_from, BVHHandle p_to, void *p_pair_data) {
		tree._handle_sort(p_from, p_to);

		typename BVHTREE_CLASS::ItemExtra &exa = tree._extra[p_from.id()];
		typename BVHTREE_CLASS::ItemExtra &exb = tree._extra[p_to.id()];

		// if the userdata is the same, no collisions should occur
		if ((exa.userdata == exb.userdata) && exa.userdata) {
			return p_pair_data;
		}

		// callback
		if (check_pair_callback) {
			return check_pair_callback(check_pair_callback_userdata, p_from, exa.userdata, exa.subindex, p_to, exb.userdata, exb.subindex, p_pair_data);
		}

		return p_pair_data;
	}

	// returns true if unpair
	bool _find_leavers_process_pair(typename BVHTREE_CLASS::ItemPairs &p_pairs_from, const BVHABB_CLASS &p_abb_from, BVHHandle p_from, BVHHandle p_to, bool p_full_check, uint32_t p_pair_index) {
		BVHABB_CLASS abb_to;
		tree.item_get_ABB(p_to, abb_to);

		// do they overlap?
		if (p_abb_from.intersects(abb_to)) {
			// the full check for pairable / non pairable (i.e. tree_id and tree_masks) and mask changes is extra expense
			// this need not be done in most cases (for speed) except in the case where set_tree is called
			// where the masks etc of the objects in question may have changed
			if (!p_full_check) {
				return false;
			}
			const typename BVHTREE_CLASS::ItemExtra &exa = _get_extra(p_from);
			const typename BVHTREE_CLASS::ItemExtra &exb = _get_extra(p_to);

			// Checking tree_ids and tree_collision_masks
			if (exa.are_item_trees_compatible(exb)) {
				bool pair_allowed = USER_PAIR_TEST_FUNCTION::user_pair_check(exa.userdata, exb.userdata);

				// the masks must still be compatible to pair
				// i.e. if there is a hit between the two and they intersect, then they should stay paired
				if (pair_allowed) {
					return false;
				}
			}
		}

		_unpair(p_from, p_to, p_pair_index);
		return true;
	}

	// find all the existing paired aabbs that are no longer
	// paired, and send callbacks
	void _find_leavers(BVHHandle p_handle, const BVHABB_CLASS &p_expanded_abb_from, bool p_full_check) {
		typename BVHTREE_CLASS::ItemPairs &p_from = tree._pairs[p_handle.id()];

		BVHABB_CLASS abb_from = p_expanded_abb_from;

		// remove from pairing list for every partner
		for (uint32_t n = 0; n < p_from.extended_pairs.size(); n++) {
			BVHHandle h_to = p_from.extended_pairs[n].handle;
			if (_find_leavers_process_pair(p_from, abb_from, p_handle, h_to, p_full_check, n)) {
				// we need to keep the counter n up to date if we deleted a pair
				// as the number of items in p_from.extended_pairs will have decreased by 1
				// and we don't want to miss an item

				// Note this can overflow to UINT32_MAX if we process the 0th element,
				// but it's fine as it will increment back to zero next loop,
				// it is not UB with uint32_t.
				n--;
			}
		}
	}

	// find NEW enterers, and send callbacks for them only
	// handle a and b
	void _collide(BVHHandle p_ha, BVHHandle p_hb) {
		// only have to do this oneway, lower ID then higher ID
		tree._handle_sort(p_ha, p_hb);

		const typename BVHTREE_CLASS::ItemExtra &exa = _get_extra(p_ha);
		const typename BVHTREE_CLASS::ItemExtra &exb = _get_extra(p_hb);

		// Compound shapes belonging to the same object can never form a pair.
		// Reject them before running the potentially expensive user filter.
		if ((exa.userdata == exb.userdata) && exa.userdata) {
			return;
		}

		typename BVHTREE_CLASS::ItemPairs &p_from = tree._pairs[p_ha.id()];
		typename BVHTREE_CLASS::ItemPairs &p_to = tree._pairs[p_hb.id()];

		// Only high-degree pairs use the hash index. Sparse contacts retain
		// the compact linear adjacency scan, with no per-body index storage.
		if (p_from.extended_pairs.size() >= DENSE_PAIR_THRESHOLD &&
				p_to.extended_pairs.size() >= DENSE_PAIR_THRESHOLD) {
			if (dense_pair_keys.has(_dense_pair_key(p_ha, p_hb))) {
				return;
			}
		} else if (p_from.extended_pairs.size() <= p_to.extended_pairs.size()) {
			if (p_from.contains_pair_to(p_hb)) {
				return;
			}
		} else {
			if (p_to.contains_pair_to(p_ha)) {
				return;
			}
		}

		// Already-existing pairs have been checked by _find_leavers().
		// Only new pairs need the user-defined (layer / mask) filter.
		if (!USER_PAIR_TEST_FUNCTION::user_pair_check(exa.userdata, exb.userdata)) {
			return;
		}

		// callback
		void *callback_userdata = nullptr;

#ifdef BVH_VERBOSE_PAIRING
		print_line("_pair " + itos(p_ha.id()) + " to " + itos(p_hb.id()));
#endif

		if (pair_callback) {
			callback_userdata = pair_callback(pair_callback_userdata, p_ha, exa.userdata, exa.subindex, p_hb, exb.userdata, exb.subindex);
		}

		// Reciprocal positions enable constant-time unlink and pair-data updates.
		const uint32_t from_index = p_from.extended_pairs.size();
		const uint32_t to_index = p_to.extended_pairs.size();
		p_from.add_pair_to(p_hb, callback_userdata, to_index);
		p_to.add_pair_to(p_ha, callback_userdata, from_index);
		if (p_from.extended_pairs.size() >= DENSE_PAIR_THRESHOLD &&
				p_to.extended_pairs.size() >= DENSE_PAIR_THRESHOLD) {
			dense_pair_keys.insert(_dense_pair_key(p_ha, p_hb));
		}
		_index_new_dense_neighbors(p_ha);
		_index_new_dense_neighbors(p_hb);
	}

	// if we remove an item, we need to immediately remove the pairs, to prevent reading the pair after deletion
	void _remove_pairs_containing(BVHHandle p_handle) {
		typename BVHTREE_CLASS::ItemPairs &p_from = tree._pairs[p_handle.id()];

		// remove from pairing list for every partner.
		// can't easily use a for loop here, because removing changes the size of the list
		while (p_from.extended_pairs.size()) {
			BVHHandle h_to = p_from.extended_pairs[0].handle;
			_unpair(p_handle, h_to, 0);
		}
	}

	// Send pair callbacks again for all existing pairs for the given handle.
	void _recheck_pairs(BVHHandle p_handle) {
		typename BVHTREE_CLASS::ItemPairs &from = tree._pairs[p_handle.id()];

		// checking pair for every partner.
		for (unsigned int n = 0; n < from.extended_pairs.size(); n++) {
			typename BVHTREE_CLASS::ItemPairs::Link &pair = from.extended_pairs[n];
			BVHHandle h_to = pair.handle;
			void *new_pair_data = _recheck_pair(p_handle, h_to, pair.userdata);

			if (new_pair_data != pair.userdata) {
				pair.userdata = new_pair_data;

				// The reciprocal link index stays current through unordered removals.
				typename BVHTREE_CLASS::ItemPairs &to = tree._pairs[h_to.id()];
				DEV_ASSERT(pair.reverse_index < to.extended_pairs.size());
				DEV_ASSERT(to.extended_pairs[pair.reverse_index].handle == p_handle);
				to.extended_pairs[pair.reverse_index].userdata = new_pair_data;
			}
		}
	}

private:
	const typename BVHTREE_CLASS::ItemExtra &_get_extra(BVHHandle p_handle) const {
		return tree._extra[p_handle.id()];
	}
	const typename BVHTREE_CLASS::ItemRef &_get_ref(BVHHandle p_handle) const {
		return tree._refs[p_handle.id()];
	}

	void _reset() {
		changed_items.clear();
		_tick++;
	}

	void _add_changed_item(BVHHandle p_handle, const BOUNDS &p_aabb, bool p_check_aabb = true) {
		// Note that non pairable items can pair with pairable,
		// so all types must be added to the list

#ifdef BVH_EXPAND_LEAF_AABBS
		// if using expanded AABB in the leaf, the redundancy check will already have been made
		BOUNDS &expanded_aabb = tree._pairs[p_handle.id()].expanded_aabb;
		item_get_AABB(p_handle, expanded_aabb);
#else
		// aabb check with expanded aabb. This greatly decreases processing
		// at the cost of slightly less accurate pairing checks
		// Note this pairing AABB is separate from the AABB in the actual tree
		BOUNDS &expanded_aabb = tree._pairs[p_handle.id()].expanded_aabb;

		// passing p_check_aabb false disables the optimization which prevents collision checks if
		// the aabb hasn't changed. This is needed where set_pairable has been called, but the position
		// has not changed.
		if (p_check_aabb && tree.expanded_aabb_encloses_not_shrink(expanded_aabb, p_aabb)) {
			return;
		}

		// ALWAYS update the new expanded aabb, even if already changed once
		// this tick, because it is vital that the AABB is kept up to date
		expanded_aabb = p_aabb;
		expanded_aabb.grow_by(tree._pairing_expansion);
#endif

		// this code is to ensure that changed items only appear once on the updated list
		// collision checking them multiple times is not needed, and repeats the same thing
		uint32_t &last_updated_tick = tree._extra[p_handle.id()].last_updated_tick;

		if (last_updated_tick == _tick) {
			return; // already on changed list
		}

		// mark as on list
		last_updated_tick = _tick;

		// Remember the queue position so erasing an item doesn't scan all moved bodies.
		tree._extra[p_handle.id()].changed_item_index = changed_items.size();
		changed_items.push_back(p_handle);
	}

	void _remove_changed_item(BVHHandle p_handle) {
		// Care has to be taken here for items that are deleted. The ref ID
		// could be reused on the same tick for new items. This is probably
		// rare but should be taken into consideration

		// callbacks
		_remove_pairs_containing(p_handle);

		// Unordered removal is O(1): update the moved entry's index.
		typename BVHTREE_CLASS::ItemExtra &extra = tree._extra[p_handle.id()];
		if (extra.last_updated_tick == _tick) {
			const uint32_t index = extra.changed_item_index;
			DEV_ASSERT(index < changed_items.size());
			DEV_ASSERT(changed_items[index] == p_handle);

			const BVHHandle last_handle = changed_items[changed_items.size() - 1];
			changed_items.remove_at_unordered(index);
			if (last_handle != p_handle) {
				tree._extra[last_handle.id()].changed_item_index = index;
			}
		}

		// A freed ref ID may be reused before the next update.
		extra.last_updated_tick = 0;
	}

	PairCallback pair_callback = nullptr;
	UnpairCallback unpair_callback = nullptr;
	CheckPairCallback check_pair_callback = nullptr;
	void *pair_callback_userdata = nullptr;
	void *unpair_callback_userdata = nullptr;
	void *check_pair_callback_userdata = nullptr;

	BVHTREE_CLASS tree;
	HashSet<uint64_t> dense_pair_keys;

	// for collision pairing,
	// maintain a list of all items moved etc on each frame / tick
	LocalVector<BVHHandle> changed_items;
	uint32_t _tick = 1; // Start from 1 so items with 0 indicate never updated.

	class BVHLockedFunction {
	public:
		BVHLockedFunction(Mutex *p_mutex, bool p_thread_safe) {
			// will be compiled out if not set in template
			if (p_thread_safe) {
				_mutex = p_mutex;
				_mutex->lock();

			} else {
				_mutex = nullptr;
			}
		}
		~BVHLockedFunction() {
			// will be compiled out if not set in template
			if (_mutex) {
				_mutex->unlock();
			}
		}

	private:
		Mutex *_mutex = nullptr;
	};

	mutable Mutex _mutex;

	// local toggle for turning on and off thread safety in project settings
	bool _thread_safe = BVH_THREAD_SAFE;
};

#undef BVHTREE_CLASS
