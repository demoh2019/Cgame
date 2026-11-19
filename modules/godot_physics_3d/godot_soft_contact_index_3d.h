/**************************************************************************/
/*  godot_soft_contact_index_3d.h                                         */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/os/memory.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"

// Rigid-soft pairs contain at most one contact for each soft-body node.
// Linear searches are cheaper for short lists; larger contact patches
// benefit from direct node-ID lookup. Keep only a pointer in each pair:
// neither the HashMap nor its entries are allocated for ordinary contacts.
class GodotSoftContactIndex3D {
	static constexpr uint32_t INDEX_THRESHOLD = 64;
	static constexpr uint32_t RELEASE_THRESHOLD = 16;
	HashMap<int, uint32_t> *node_indices = nullptr;

public:
	GodotSoftContactIndex3D() = default;
	GodotSoftContactIndex3D(const GodotSoftContactIndex3D &) = delete;
	GodotSoftContactIndex3D &operator=(const GodotSoftContactIndex3D &) = delete;

	~GodotSoftContactIndex3D() {
		clear();
	}

	_FORCE_INLINE_ bool is_active() const {
		return node_indices != nullptr;
	}

	template <typename T>
	void maybe_build(const LocalVector<T> &p_contacts) {
		if (node_indices || p_contacts.size() < INDEX_THRESHOLD) {
			return;
		}

		node_indices = memnew((HashMap<int, uint32_t>));
		node_indices->reserve(p_contacts.size());
		for (uint32_t i = 0; i < p_contacts.size(); i++) {
			node_indices->insert(p_contacts[i].index_B, i);
		}
	}

	_FORCE_INLINE_ int find(int p_node_index) const {
		if (!node_indices) {
			return -1;
		}
		const uint32_t *index = node_indices->getptr(p_node_index);
		return index ? int(*index) : -1;
	}

	_FORCE_INLINE_ void appended(int p_node_index, uint32_t p_contact_index) {
		if (node_indices) {
			node_indices->insert(p_node_index, p_contact_index);
		}
	}

	void swap_removed(int p_deleted_node, int p_moved_node, uint32_t p_target_index, uint32_t p_remaining_contacts) {
		if (!node_indices) {
			return;
		}
		if (p_remaining_contacts < RELEASE_THRESHOLD) {
			// Release all node allocations and buckets once the pair is sparse.
			clear();
			return;
		}

		node_indices->erase(p_deleted_node);
		if (p_moved_node != p_deleted_node) {
			uint32_t *index = node_indices->getptr(p_moved_node);
			CRASH_COND(!index);
			*index = p_target_index;
		}
	}

	void clear() {
		if (node_indices) {
			memdelete(node_indices);
			node_indices = nullptr;
		}
	}
};
