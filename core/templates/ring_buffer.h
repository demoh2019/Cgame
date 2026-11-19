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
		int left = data_left();
		p_size = MIN(left, p_size);
		if (p_size <= 0) {
			return 0;
		}
		int pos = read_pos;
		int to_read = p_size;
		int dst = 0;
		while (to_read) {
			int end = pos + to_read;
			end = MIN(end, size());
			int total = end - pos;
			copy_block(p_buf + dst, data.ptr() + pos, total);
			dst += total;
			to_read -= total;
			pos = 0;
		}
		if (p_advance) {
			inc(read_pos, p_size);
		}
		return p_size;
	}

	int copy(T *p_buf, int p_offset, int p_size) const {
		int left = data_left();
		if ((p_offset + p_size) > left) {
			p_size = left - p_offset;
			if (p_size <= 0) {
				return 0;
			}
		}
		p_size = MIN(left, p_size);
		if (p_size <= 0) {
			return 0;
		}
		int pos = read_pos;
		inc(pos, p_offset);
		int to_read = p_size;
		int dst = 0;
		while (to_read) {
			int end = pos + to_read;
			end = MIN(end, size());
			int total = end - pos;
			copy_block(p_buf + dst, data.ptr() + pos, total);
			dst += total;
			to_read -= total;
			pos = 0;
		}
		return p_size;
	}

	int find(const T &p_value, int p_offset, int p_max_size) const {
		const int left = data_left();
		if (p_offset < 0 || p_max_size <= 0 || p_offset >= left) {
			return -1;
		}
		// Subtract instead of adding sizes to avoid signed integer overflow.
		p_max_size = MIN(left - p_offset, p_max_size);
		int pos = read_pos;
		inc(pos, p_offset);
		int to_read = p_max_size;
		while (to_read) {
			const int total = MIN(to_read, size() - pos);
			if constexpr (std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<T, bool>) {
				// Byte buffers (network/audio/streaming) can use optimized libc scanning.
				const T *const begin = data.ptr() + pos;
				const T *const found = static_cast<const T *>(std::memchr(begin, static_cast<unsigned char>(p_value), size_t(total)));
				if (found) {
					return p_max_size - to_read + int(found - begin);
				}
			} else {
				for (int i = 0; i < total; i++) {
					if (data[pos + i] == p_value) {
						return i + (p_max_size - to_read);
					}
				}
			}
			to_read -= total;
			pos = 0;
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

	Error write(const T &p_v) {
		ERR_FAIL_COND_V(space_left() < 1, FAILED);
		data[inc(write_pos, 1)] = p_v;
		return OK;
	}

	int write(const T *p_buf, int p_size) {
		int left = space_left();
		p_size = MIN(left, p_size);
		if (p_size <= 0) {
			return 0;
		}

		int pos = write_pos;
		int to_write = p_size;
		int src = 0;
		while (to_write) {
			int end = pos + to_write;
			end = MIN(end, size());
			int total = end - pos;

			copy_block(data.ptr() + pos, p_buf + src, total);
			src += total;
			to_write -= total;
			pos = 0;
		}

		inc(write_pos, p_size);
		return p_size;
	}

	inline int space_left() const {
		int left = read_pos - write_pos;
		if (left < 0) {
			return size() + left - 1;
		}
		if (left == 0) {
			return size() - 1;
		}
		return left - 1;
	}
	inline int data_left() const {
		return size() - space_left() - 1;
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
