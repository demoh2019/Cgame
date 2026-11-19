public:
// note .. maybe this can be attached to another node structure?
// depends which works best for cache.
struct ItemPairs {
	struct Link {
		void set(BVHHandle p_handle, void *p_userdata) {
			handle = p_handle;
			userdata = p_userdata;
		}
		BVHHandle handle;
		void *userdata;
	};

	void clear() {
		extended_pairs.reset();
		expanded_aabb = BOUNDS();
	}

	BOUNDS expanded_aabb;

	// The vector's size is the sole pair count, avoiding per-object duplication.
	LocalVector<Link> extended_pairs;

	void add_pair_to(BVHHandle p_handle, void *p_userdata) {
		// Most objects have only a few neighbors. Reserve exactly one link
		// on first contact rather than eagerly allocating room for two.
		if (extended_pairs.get_capacity() == 0) {
			extended_pairs.reserve_exact(1);
		}
		Link temp;
		temp.set(p_handle, p_userdata);

		extended_pairs.push_back(temp);
	}

	uint32_t find_pair_to(BVHHandle p_handle) const {
		for (uint32_t n = 0; n < extended_pairs.size(); n++) {
			if (extended_pairs[n].handle == p_handle) {
				return n;
			}
		}
		return uint32_t(-1);
	}

	bool contains_pair_to(BVHHandle p_handle) const {
		return find_pair_to(p_handle) != BVHCommon::INVALID;
	}

	// Remove a link at a position already found by the caller. This avoids
	// scanning the same adjacency list again when processing lost contacts.
	void *remove_pair_at(uint32_t p_index) {
		DEV_ASSERT(p_index < extended_pairs.size());
		void *userdata = extended_pairs[p_index].userdata;
		extended_pairs.remove_at_unordered(p_index);
		// Avoid pinning a large allocation to an object after a temporary
		// high-density contact event. Keep small buffers for contact churn.
		const uint32_t capacity = extended_pairs.get_capacity();
		const uint32_t count = extended_pairs.size();
		if (count == 0) {
			if (capacity > 8) {
				extended_pairs.reset();
			}
		} else if (capacity >= 64 && count <= capacity / 8) {
			// Dense clusters may dissolve without reaching zero contacts.
			// Keep twice the live count to provide hysteresis for new pairs.
			extended_pairs.shrink_to(MAX(uint32_t(8), count * 2));
		}
		return userdata;
	}

	void *remove_pair_to(BVHHandle p_handle) {
		const uint32_t index = find_pair_to(p_handle);
		return index != BVHCommon::INVALID ? remove_pair_at(index) : nullptr;
	}

	// experiment : scale the pairing expansion by the number of pairs.
	// when the number of pairs is high, the density is high and a lower collision margin is better.
	// when there are few local pairs, a larger margin is more optimal.
	real_t scale_expansion_margin(real_t p_margin) const {
		real_t x = real_t(extended_pairs.size()) * (1.0 / 9.0);
		x = MIN(x, 1.0);
		x = 1.0 - x;
		return p_margin * x;
	}
};
