/**************************************************************************/
/*  local_vector.h                                                        */
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

#include "core/error/error_macros.h"
#include "core/os/memory.h"
#include "core/string/print_string.h" // IWYU pragma: keep. `WARN_VERBOSE` macro.
#include "core/templates/sort_array.h"
#include "core/templates/vector.h"

#include <cstring>
#include <functional>
#include <initializer_list>
#include <type_traits>

/**
 * Array-like container with unique ownership.
 *
 * Elements are relocated by naive memory moves; they must not store their own address (see GH-100509).
 *
 * Core container guidance:
 * https://docs.godotengine.org/en/latest/engine_details/architecture/core_types.html#containers
 *
 * @tparam tight Disable exponential growth (reallocate element-by-element instead).
 */
template <typename T, typename U = uint32_t, bool force_trivial = false, bool tight = false>
class _WARN_UNUSED_ LocalVector {
	static_assert(!force_trivial, "force_trivial is no longer supported. Use resize_uninitialized instead.");

private:
	U count = 0;
	U capacity = 0;
	T *data = nullptr;

	template <bool p_init>
	void _resize(U p_size) {
		if (p_size < count) {
			if constexpr (!std::is_trivially_destructible_v<T>) {
				for (U i = p_size; i < count; i++) {
					data[i].~T();
				}
			}
			count = p_size;
		} else if (p_size > count) {
			reserve(p_size);
			if constexpr (p_init) {
				memnew_arr_placement(data + count, p_size - count);
			} else {
				static_assert(std::is_trivially_destructible_v<T>, "T must be trivially destructible to resize uninitialized");
			}
			count = p_size;
		}
	}

	// Can't use `_resize(0)`, since it requires a no-arg-constructor even if it wouldn't be called.
	void _clear() {
		if constexpr (!std::is_trivially_destructible_v<T>) {
			for (U i = 0; i < count; i++) {
				data[i].~T();
			}
		}
		count = 0;
	}

public:
	_FORCE_INLINE_ T *ptr() _LIFETIME_BOUND_ { return data; }
	_FORCE_INLINE_ const T *ptr() const _LIFETIME_BOUND_ { return data; }
	_FORCE_INLINE_ U size() const { return count; }

	_FORCE_INLINE_ Span<T> span() const _LIFETIME_BOUND_ { return Span(data, count); }
	_FORCE_INLINE_ operator Span<T>() const _LIFETIME_BOUND_ { return span(); }

	// Overload for lvalues (copies).
	_FORCE_INLINE_ void push_back(const T &p_elem) {
		if (unlikely(count == capacity)) {
			// Must take a copy instead of a reference (see GH-31736).
			T local_copy(p_elem);
			reserve(count + 1);
			memnew_placement(&data[count++], T(std::move(local_copy)));
		} else {
			memnew_placement(&data[count++], T(p_elem));
		}
	}

	// Overload for rvalues (moves).
	_FORCE_INLINE_ void push_back(T &&p_elem) {
		if (unlikely(count == capacity)) {
			// STL states that p_elem should never be a self-insertion:
			// i.e. vec.push_back(std::move(vec[0]));
			// However for safety, and compatibility we can choose to make a copy
			// here too.
			T local_copy(std::move(p_elem));
			reserve(count + 1);
			memnew_placement(&data[count++], T(std::move(local_copy)));
		} else {
			memnew_placement(&data[count++], T(std::move(p_elem)));
		}
	}

	void remove_at(U p_index) {
		ERR_FAIL_UNSIGNED_INDEX(p_index, count);
		count--;
		if constexpr (std::is_trivially_copyable_v<T>) {
			if (p_index < count) {
				// Shift the surviving POD values in one optimized bulk move.
				std::memmove(data + p_index, data + p_index + 1, size_t(count - p_index) * sizeof(T));
			}
		} else {
			for (U i = p_index; i < count; i++) {
				data[i] = std::move(data[i + 1]);
			}
		}
		data[count].~T();
	}

	/// Removes the item copying the last value into the position of the one to
	/// remove. It's generally faster than `remove_at`.
	void remove_at_unordered(U p_index) {
		ERR_FAIL_UNSIGNED_INDEX(p_index, count);
		count--;
		if (count > p_index) {
			data[p_index] = std::move(data[count]);
		}
		data[count].~T();
	}

	_FORCE_INLINE_ bool erase(const T &p_val) {
		int64_t idx = find(p_val);
		if (idx >= 0) {
			remove_at(idx);
			return true;
		}
		return false;
	}

	bool erase_unordered(const T &p_val) {
		int64_t idx = find(p_val);
		if (idx >= 0) {
			remove_at_unordered(idx);
			return true;
		}
		return false;
	}

	U erase_multiple_unordered(const T &p_val) {
		U from = 0;
		U occurrences = 0;
		while (true) {
			const int64_t idx = find(p_val, from);
			if (idx == -1) {
				break;
			}

			const U at = U(idx);
			// Remove matching tail values before swapping a survivor into the hole.
			// This avoids move assignments when many matches cluster at the end,
			// while keeping find()'s fast scanning for sparse matches.
			while (count > at && data[count - 1] == p_val) {
				data[--count].~T();
				occurrences++;
			}
			if (at == count) {
				break;
			}

			remove_at_unordered(at);
			from = at; // Inspect the value moved into the deleted slot.
			occurrences++;
		}
		return occurrences;
	}

	void reverse() {
		for (U i = 0; i < count / 2; i++) {
			SWAP(data[i], data[count - i - 1]);
		}
	}
#ifndef DISABLE_DEPRECATED
	[[deprecated("Use reverse() instead")]] void invert() { reverse(); }
#endif

	_FORCE_INLINE_ void clear() { _clear(); }
	_FORCE_INLINE_ void reset() {
		clear();
		if (data) {
			memfree(data);
			data = nullptr;
			capacity = 0;
		}
	}
	_FORCE_INLINE_ bool is_empty() const { return count == 0; }
	_FORCE_INLINE_ U get_capacity() const { return capacity; }

	// Unlike reserve(), this allocates exactly the requested initial capacity.
	// Subsequent growth through push_back() still uses geometric expansion.
	// Useful for the common case of tiny lists that rarely grow past one item.
	void reserve_exact(U p_size) {
		if (p_size > capacity) {
			T *new_data = (T *)memrealloc(data, size_t(p_size) * sizeof(T));
			CRASH_COND_MSG(!new_data, "Out of memory");
			data = new_data;
			capacity = p_size;
		}
	}

	// Reclaim excess capacity explicitly without changing the number or order
	// of elements. The caller controls the threshold to avoid resize churn.
	void shrink_to(U p_capacity) {
		if (p_capacity < count || p_capacity >= capacity) {
			return;
		}
		if (p_capacity == 0) {
			reset();
			return;
		}
		T *new_data = (T *)memrealloc(data, size_t(p_capacity) * sizeof(T));
		CRASH_COND_MSG(!new_data, "Out of memory");
		data = new_data;
		capacity = p_capacity;
	}

	void reserve(U p_size) {
		if (p_size > capacity) {
			if (tight) {
				capacity = p_size;
			} else {
				// Try 1.5x the current capacity.
				// This ratio was chosen because it is close to the ideal growth rate of the golden ratio.
				// See https://archive.ph/Z2R8w for details.
				capacity = MAX((U)2, capacity + ((1 + capacity) >> 1));
				// If 1.5x growth isn't enough, just use the needed size exactly.
				if (p_size > capacity) {
					capacity = p_size;
				}
			}
			data = (T *)memrealloc(data, capacity * sizeof(T));
			CRASH_COND_MSG(!data, "Out of memory");
		} else if (p_size < count) {
			WARN_VERBOSE("reserve() called with a capacity smaller than the current size. This is likely a mistake.");
		}
	}

	/// Resize the vector.
	/// Elements are initialized (or not) depending on what the default C++ behavior for T is.
	/// Note: If force_trivial is set, this will behave like resize_uninitialized instead.
	void resize(U p_size) {
		// Don't init when trivially constructible.
		_resize<!std::is_trivially_constructible_v<T>>(p_size);
	}

	/// Resize and set new values to 0 / false / nullptr.
	_FORCE_INLINE_ void resize_initialized(U p_size) { _resize<true>(p_size); }

	/// Resize and keep memory uninitialized.
	/// This means that any newly added elements have an unknown value, and are expected to be set after the `resize_uninitialized` call.
	/// This is only available for trivially destructible types (otherwise, trivial resize might be UB).
	_FORCE_INLINE_ void resize_uninitialized(U p_size) { _resize<false>(p_size); }

	_FORCE_INLINE_ const T &operator[](U p_index) const _LIFETIME_BOUND_ {
		CRASH_BAD_UNSIGNED_INDEX(p_index, count);
		return data[p_index];
	}
	_FORCE_INLINE_ T &operator[](U p_index) _LIFETIME_BOUND_ {
		CRASH_BAD_UNSIGNED_INDEX(p_index, count);
		return data[p_index];
	}

	struct Iterator {
		_FORCE_INLINE_ T &operator*() const {
			return *elem_ptr;
		}
		_FORCE_INLINE_ T *operator->() const { return elem_ptr; }
		_FORCE_INLINE_ Iterator &operator++() {
			elem_ptr++;
			return *this;
		}
		_FORCE_INLINE_ Iterator &operator--() {
			elem_ptr--;
			return *this;
		}

		_FORCE_INLINE_ bool operator==(const Iterator &p_other) const { return elem_ptr == p_other.elem_ptr; }
		_FORCE_INLINE_ bool operator!=(const Iterator &p_other) const { return elem_ptr != p_other.elem_ptr; }

		Iterator(T *p_ptr) { elem_ptr = p_ptr; }
		Iterator() {}
		Iterator(const Iterator &p_it) { elem_ptr = p_it.elem_ptr; }

	private:
		T *elem_ptr = nullptr;
	};

	struct ConstIterator {
		_FORCE_INLINE_ const T &operator*() const {
			return *elem_ptr;
		}
		_FORCE_INLINE_ const T *operator->() const { return elem_ptr; }
		_FORCE_INLINE_ ConstIterator &operator++() {
			elem_ptr++;
			return *this;
		}
		_FORCE_INLINE_ ConstIterator &operator--() {
			elem_ptr--;
			return *this;
		}

		_FORCE_INLINE_ bool operator==(const ConstIterator &p_other) const { return elem_ptr == p_other.elem_ptr; }
		_FORCE_INLINE_ bool operator!=(const ConstIterator &p_other) const { return elem_ptr != p_other.elem_ptr; }

		ConstIterator(const T *p_ptr) { elem_ptr = p_ptr; }
		ConstIterator() {}
		ConstIterator(const ConstIterator &p_it) { elem_ptr = p_it.elem_ptr; }

	private:
		const T *elem_ptr = nullptr;
	};

	_FORCE_INLINE_ Iterator begin() _LIFETIME_BOUND_ {
		return Iterator(data);
	}
	_FORCE_INLINE_ Iterator end() _LIFETIME_BOUND_ {
		return Iterator(data + size());
	}

	_FORCE_INLINE_ ConstIterator begin() const _LIFETIME_BOUND_ {
		return ConstIterator(ptr());
	}
	_FORCE_INLINE_ ConstIterator end() const _LIFETIME_BOUND_ {
		return ConstIterator(ptr() + size());
	}

	void insert(U p_pos, T p_val) {
		ERR_FAIL_UNSIGNED_INDEX(p_pos, count + 1);
		if (p_pos == count) {
			push_back(std::move(p_val));
		} else {
			if constexpr (std::is_trivially_copyable_v<T>) {
				resize(count + 1);
				// The last slot already exists; shift in place without per-element assignments.
				std::memmove(data + p_pos + 1, data + p_pos, size_t(count - p_pos - 1) * sizeof(T));
			} else {
				// Construct the new tail by moving the old tail, avoiding a potentially
				// expensive default construction and an extra move assignment.
				// This also allows insertion of non-default-constructible types.
				reserve(count + 1);
				memnew_placement(&data[count], T(std::move(data[count - 1])));
				++count;
				for (U i = count - 2; i > p_pos; i--) {
					data[i] = std::move(data[i - 1]);
				}
			}
			data[p_pos] = std::move(p_val);
		}
	}

	int64_t find(const T &p_val, int64_t p_from = 0) const {
		if (p_from < 0) {
			p_from = size() + p_from;
		}
		if (p_from < 0 || p_from >= size()) {
			return -1;
		}
		if constexpr (std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<T, bool>) {
			const T *const found = static_cast<const T *>(std::memchr(data + p_from, static_cast<unsigned char>(p_val), size_t(size() - p_from)));
			return found ? int64_t(found - data) : -1;
		} else {
			return span().find(p_val, p_from);
		}
	}

	bool has(const T &p_val) const {
		return find(p_val) != -1;
	}

	template <typename C>
	void sort_custom() {
		U len = count;
		if (len == 0) {
			return;
		}

		SortArray<T, C> sorter;
		sorter.sort(data, len);
	}

	void sort() {
		sort_custom<Comparator<T>>();
	}

	void ordered_insert(T p_val) {
		// Appending sorted or equal values avoids the binary search entirely.
		if (count == 0 || !Comparator<T>()(p_val, data[count - 1])) {
			push_back(std::move(p_val));
			return;
		}
		const U idx = span().bisect(p_val, false);
		insert(idx, std::move(p_val));
	}

	Vector<uint8_t> to_byte_array() const { //useful to pass stuff to gpu or variant
		Vector<uint8_t> ret;
		ret.resize(count * sizeof(T));
		uint8_t *w = ret.ptrw();
		if (w) {
			memcpy(w, data, sizeof(T) * count);
		}
		return ret;
	}

	LocalVector() = default;
	LocalVector(std::initializer_list<T> p_init) {
		reserve(p_init.size());
		size_t i = 0;
		for (const T &value : p_init) {
			memnew_placement(&data[i], T(value));
			i++;
		}
		count = p_init.size();
	}
	explicit LocalVector(Span<T> p_span) {
		reserve(p_span.size());
		for (size_t i = 0; i < p_span.size(); i++) {
			memnew_placement(&data[i], T(p_span.ptr()[i]));
		}
		count = p_span.size();
	}
	explicit LocalVector(const LocalVector &p_vector) :
			LocalVector(p_vector.span()) {}
	LocalVector(LocalVector &&p_from) {
		data = p_from.data;
		count = p_from.count;
		capacity = p_from.capacity;

		p_from.data = nullptr;
		p_from.count = 0;
		p_from.capacity = 0;
	}

	void operator=(Span<T> p_from) {
		const T *const source = p_from.ptr();
		if (source == data) {
			// A full self-assignment needs no work. For a prefix, only destroy
			// the removed tail; avoid reassigning every surviving element.
			resize(p_from.size());
			return;
		}
		// A span into our tail must be copied before shrinking: for
		// nontrivial T, resize() would destroy the source elements first.
		// std::less provides a total pointer order even for unrelated buffers.
		if (data != nullptr && source != nullptr &&
				std::less<const T *>()(data, source) &&
				std::less<const T *>()(source, data + count)) {
			if constexpr (std::is_trivially_copyable_v<T>) {
				std::memmove(data, source, size_t(p_from.size()) * sizeof(T));
			} else {
				// Copying left to right preserves still-unread source elements.
				for (size_t i = 0; i < p_from.size(); i++) {
					data[i] = source[i];
				}
			}
			resize(p_from.size());
			return;
		}
		resize(p_from.size());
		if constexpr (std::is_trivially_copyable_v<T>) {
			if (count > 0) {
				std::memmove(data, source, size_t(count) * sizeof(T));
			}
		} else {
			for (size_t i = 0; i < p_from.size(); i++) {
				data[i] = source[i];
			}
		}
	}
	void operator=(const LocalVector &p_vector) { operator=(p_vector.span()); }
	void operator=(LocalVector &&p_from) {
		if (unlikely(this == &p_from)) {
			return;
		}
		reset();

		data = p_from.data;
		count = p_from.count;
		capacity = p_from.capacity;

		p_from.data = nullptr;
		p_from.count = 0;
		p_from.capacity = 0;
	}
	void operator=(Vector<T> &&p_from) {
		resize(p_from.size());
		if constexpr (std::is_trivially_copyable_v<T>) {
			if (count > 0) {
				std::memcpy(data, p_from.ptr(), size_t(count) * sizeof(T));
			}
		} else {
			for (U i = 0; i < count; i++) {
				data[i] = std::move(p_from[i]);
			}
		}
	}

	~LocalVector() {
		if (data) {
			reset();
		}
	}
};

template <typename T, typename U = uint32_t>
using TightLocalVector = LocalVector<T, U, false, true>;

// Zero-constructing LocalVector initializes count, capacity and data to 0 and thus empty.
template <typename T, typename U, bool force_trivial, bool tight>
struct is_zero_constructible<LocalVector<T, U, force_trivial, tight>> : std::true_type {};
