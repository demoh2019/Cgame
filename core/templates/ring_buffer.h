/**************************************************************************/
/*  ring_buffer.h                                                         */
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

#include "core/templates/local_vector.h"

#include <cstring>
#include <type_traits>

template <typename T>
class _WARN_UNUSED_ RingBuffer {
	LocalVector<T> data;
	int read_pos = 0;
	int write_pos = 0;
	int size_mask;

	// Fast bulk transfers for trivially copyable bytes and audio samples.
	// Keep assignment semantics for nontrivial resource types.
	static _FORCE_INLINE_ void copy_block(T *p_dest, const T *p_source, int p_count) {
		if constexpr (std::is_trivially_copyable_v<T>) {
			std::memmove(p_dest, p_source, size_t(p_count) * sizeof(T));
		} else {
			for (int i = 0; i < p_count; i++) {
				p_dest[i] = p_source[i];
			}
		}
	}

	// Avoid libc call overhead for very short byte spans, while retaining fast SIMD search for large spans.
	static _FORCE_INLINE_ int find_block(const T *p_data, const T &p_value, int p_count) {
		if constexpr (std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<T, bool>) {
			if (p_count >= 16) {
				const T *found = static_cast<const T *>(std::memchr(p_data, static_cast<unsigned char>(p_value), size_t(p_count)));
				return found ? int(found - p_data) : -1;
			}
		}
		for (int i = 0; i < p_count; i++) {
			if (p_data[i] == p_value) {
				return i;
			}
		}
		return -1;
	}

	inline int inc(int &p_var, int p_size) const {
		int ret = p_var;
		p_var += p_size;
		p_var = p_var & size_mask;
		return ret;
	}

public:
	T read() {
		ERR_FAIL_COND_V(data_left() < 1, T());
		return data.ptr()[inc(read_pos, 1)];
	}

	int read(T *p_buf, int p_size, bool p_advance = true) {
		p_size = MIN(data_left(), p_size);
		if (p_size <= 0) {
			return 0;
		}

		// A transfer no larger than the capacity spans at most two blocks.
		const int first = MIN(p_size, size() - read_pos);
		const T *source = data.ptr();
		copy_block(p_buf, source + read_pos, first);
		if (p_size > first) {
			copy_block(p_buf + first, source, p_size - first);
		}

		if (p_advance) {
			inc(read_pos, p_size);
		}
		return p_size;
	}

	int copy(T *p_buf, int p_offset, int p_size) const {
		const int left = data_left();
		if (p_offset < 0 || p_offset >= left || p_size <= 0) {
			return 0;
		}
		// Avoid overflow on large offsets and lengths.
		p_size = MIN(left - p_offset, p_size);
		const int pos = (read_pos + p_offset) & size_mask;
		const int first = MIN(p_size, size() - pos);
		const T *source = data.ptr();
		copy_block(p_buf, source + pos, first);
		if (p_size > first) {
			copy_block(p_buf + first, source, p_size - first);
		}
		return p_size;
	}

	int find(const T &p_value, int p_offset, int p_max_size) const {
		const int left = data_left();
		if (p_offset < 0 || p_offset >= left || p_max_size <= 0) {
			return -1;
		}
		p_max_size = MIN(p_max_size, left - p_offset);
		int pos = read_pos;
		inc(pos, p_offset);

		// At most two contiguous spans; no loop state on the common unwrapped path.
		const int first = MIN(p_max_size, size() - pos);
		const T *source = data.ptr();
		const int first_match = find_block(source + pos, p_value, first);
		if (first_match >= 0) {
			return first_match;
		}
		if (first < p_max_size) {
			const int second_match = find_block(source, p_value, p_max_size - first);
			if (second_match >= 0) {
				return first + second_match;
			}
		}
		return -1;
	}

	inline int advance_read(int p_n) {
		p_n = MIN(p_n, data_left());
		inc(read_pos, p_n);
		return p_n;
	}

	inline int decrease_write(int p_n) {
		p_n = MIN(p_n, data_left());
		inc(write_pos, size_mask + 1 - p_n);
		return p_n;
	}

	// Direct I/O into the contiguous writable span avoids a second copy.
	// Only valid for trivially-copyable elements. Call advance_write() after
	// writing at most contiguous_space_left() elements into write_ptr().
	_FORCE_INLINE_ int contiguous_space_left() const {
		return MIN(space_left(), size() - write_pos);
	}

	_FORCE_INLINE_ T *write_ptr() _LIFETIME_BOUND_ {
		static_assert(std::is_trivially_copyable_v<T>, "Direct ring writes require trivially copyable elements.");
		return data.ptr() + write_pos;
	}

	_FORCE_INLINE_ int advance_write(int p_n) {
		static_assert(std::is_trivially_copyable_v<T>, "Direct ring writes require trivially copyable elements.");
		if (p_n <= 0) {
			return 0;
		}
		p_n = MIN(p_n, space_left());
		inc(write_pos, p_n);
		return p_n;
	}

	Error write(const T &p_v) {
		ERR_FAIL_COND_V(space_left() < 1, FAILED);
		data[inc(write_pos, 1)] = p_v;
		return OK;
	}

	int write(const T *p_buf, int p_size) {
		p_size = MIN(space_left(), p_size);
		if (p_size <= 0) {
			return 0;
		}

		const int first = MIN(p_size, size() - write_pos);
		T *dest = data.ptr();
		copy_block(dest + write_pos, p_buf, first);
		if (p_size > first) {
			copy_block(dest, p_buf + first, p_size - first);
		}

		inc(write_pos, p_size);
		return p_size;
	}

	inline int space_left() const {
		// Capacity is a power of two, so masking replaces wrap branches.
		return (read_pos - write_pos - 1) & size_mask;
	}
	inline int data_left() const {
		return (write_pos - read_pos) & size_mask;
	}

	inline int size() const {
		return data.size();
	}

	inline void clear() {
		read_pos = 0;
		write_pos = 0;
	}

	void resize(int p_power) {
		int old_size = size();
		int new_size = 1 << p_power;
		int mask = new_size - 1;
		data.resize(int64_t(1) << int64_t(p_power));
		if (old_size < new_size && read_pos > write_pos) {
			if (write_pos > 0) {
				copy_block(data.ptr() + old_size, data.ptr(), write_pos);
			}
			write_pos = (old_size + write_pos) & mask;
		} else {
			read_pos = read_pos & mask;
			write_pos = write_pos & mask;
		}

		size_mask = mask;
	}

	RingBuffer(int p_power = 0) {
		resize(p_power);
	}
};
