/**************************************************************************/
/*  span.h                                                                */
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
#include "core/typedefs.h"

#include <cstring>

template <typename LHS, typename RHS>
bool are_spans_equal(const LHS *p_lhs, const RHS *p_rhs, size_t p_size) {
	if constexpr (std::is_same_v<LHS, RHS> && std::is_fundamental_v<LHS>) {
		// Optimize trivial type comparison.
		// is_trivially_equality_comparable would help, but it doesn't exist.
		// memcmp requires pointer argument to be valid even on size = 0 (C11 §7.24.1(2)).
		// Span allows ptr arguments to be invalid as long as size = 0, so only call when p_size > 0.
		// Identical storage is already byte-for-byte equal: skip the full scan.
		// Restrict this shortcut to the bitwise-comparison branch so types with
		// non-reflexive custom equality operators keep their existing semantics.
		return p_size == 0 || p_lhs == p_rhs || memcmp(p_lhs, p_rhs, p_size * sizeof(LHS)) == 0;
	} else {
		// Normal case: Need to iterate the array manually.
		for (size_t j = 0; j < p_size; j++) {
			if (p_lhs[j] != p_rhs[j]) {
				return false;
			}
		}

		return true;
	}
}

// Equivalent of std::span.
// Represents a view into a contiguous memory space.
// DISCLAIMER: This data type does not own the underlying buffer. DO NOT STORE IT.
//  Additionally, for the lifetime of the Span, do not resize the buffer, and do not insert or remove elements from it.
//  Failure to respect this may lead to crashes or undefined behavior.
template <typename T>
class Span {
	const T *_ptr = nullptr;
	uint64_t _len = 0;

public:
	static constexpr bool is_string = std::disjunction_v<
			std::is_same<T, char>,
			std::is_same<T, char16_t>,
			std::is_same<T, char32_t>,
			std::is_same<T, wchar_t>>;

	_FORCE_INLINE_ constexpr Span() = default;

	_FORCE_INLINE_ Span(const T *p_ptr, uint64_t p_len) :
			_ptr(p_ptr), _len(p_len) {
#ifdef DEBUG_ENABLED
		// TODO In c++20, make this check run only in non-consteval, and make this constructor constexpr.
		if (_ptr == nullptr && _len > 0) {
			ERR_PRINT("Internal bug, please report: Span was created from nullptr with size > 0. Recovering by using size = 0.");
			_len = 0;
		}
#endif
	}

	// Allows creating Span directly from C arrays and string literals.
	template <size_t N>
	_FORCE_INLINE_ constexpr Span(const T (&p_array)[N]) :
			_ptr(p_array), _len(N) {
		if constexpr (is_string) {
			// Cut off the \0 terminator implicitly added to string literals.
			if (N > 0 && p_array[N - 1] == '\0') {
				_len--;
			}
		}
	}

	_FORCE_INLINE_ constexpr uint64_t size() const { return _len; }
	_FORCE_INLINE_ constexpr bool is_empty() const { return _len == 0; }

	_FORCE_INLINE_ constexpr const T *ptr() const { return _ptr; }

	// NOTE: Span subscripts sanity check the bounds to avoid undefined behavior.
	//       This is slower than direct buffer access and can prevent autovectorization.
	//       If the bounds are known, use ptr() subscript instead.
	_FORCE_INLINE_ constexpr const T &operator[](uint64_t p_idx) const {
		CRASH_COND(p_idx >= _len);
		return _ptr[p_idx];
	}

	_FORCE_INLINE_ constexpr const T *begin() const { return _ptr; }
	_FORCE_INLINE_ constexpr const T *end() const { return _ptr + _len; }

	template <typename T1>
	_FORCE_INLINE_ constexpr Span<T1> reinterpret() const {
		return Span<T1>(reinterpret_cast<const T1 *>(_ptr), _len * sizeof(T) / sizeof(T1));
	}

	// Algorithms.
	constexpr int64_t find(const T &p_val, uint64_t p_from = 0) const;
	template <typename T1 = T>
	constexpr int64_t find_sequence(const Span<T1> &p_span, uint64_t p_from = 0) const;
	constexpr int64_t rfind(const T &p_val, uint64_t p_from) const;
	_FORCE_INLINE_ constexpr int64_t rfind(const T &p_val) const { return rfind(p_val, size() - 1); }
	template <typename T1 = T>
	constexpr int64_t rfind_sequence(const Span<T1> &p_span, uint64_t p_from) const;
	template <typename T1 = T>
	_FORCE_INLINE_ constexpr int64_t rfind_sequence(const Span<T1> &p_span) const { return p_span.size() > size() ? -1 : rfind_sequence(p_span, size() - p_span.size()); }
	constexpr uint64_t count(const T &p_val) const;
	/// Find the index of the given value using binary search.
	/// Note: Assumes that elements in the span are sorted. Otherwise, use find() instead.
	template <typename Comparator = Comparator<T>>
	constexpr uint64_t bisect(const T &p_value, bool p_before, Comparator p_compare = Comparator()) const;

	/// The caller is responsible to ensure size() > 0.
	constexpr T max() const;
};

template <typename T>
constexpr int64_t Span<T>::find(const T &p_val, uint64_t p_from) const {
#if defined(__GNUC__) || defined(__clang__)
	if constexpr (std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<std::remove_cv_t<T>, bool>) {
		// Preserve compile-time evaluation while allowing libc's vectorized
		// byte scanner for runtime calls on GCC/Clang.
		if (!__builtin_is_constant_evaluated()) {
			if (p_from >= size()) {
				return -1;
			}
			const T *const found = static_cast<const T *>(std::memchr(ptr() + p_from, static_cast<unsigned char>(p_val), size_t(size() - p_from)));
			return found ? int64_t(found - ptr()) : -1;
		}
	}
#endif
	for (uint64_t i = p_from; i < size(); i++) {
		if (ptr()[i] == p_val) {
			return i;
		}
	}
	return -1;
}

template <typename T>
template <typename T1>
constexpr int64_t Span<T>::find_sequence(const Span<T1> &p_span, uint64_t p_from) const {
	const uint64_t needle_size = p_span.size();
	// Subtract only after validating the range; otherwise unsigned underflow
	// can make an oversized pattern scan past the end of the haystack.
	if (p_from > size() || needle_size > size() - p_from) {
		return -1;
	}
	if (needle_size == 0) {
		return p_from;
	}

	const T *const haystack = ptr();
	const T1 *const needle = p_span.ptr();
	const uint64_t last_start = size() - needle_size;
#if defined(__GNUC__) || defined(__clang__)
	if constexpr (std::is_same_v<T, T1> && std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<std::remove_cv_t<T>, bool>) {
		if (!__builtin_is_constant_evaluated()) {
			// Skip directly to byte candidates instead of scanning each offset.
			const T *candidate = haystack + p_from;
			const T *const end = haystack + last_start + 1;
			while (candidate < end) {
				candidate = static_cast<const T *>(std::memchr(candidate, static_cast<unsigned char>(needle[0]), size_t(end - candidate)));
				if (!candidate) {
					return -1;
				}
				if (needle_size == 1 || (candidate[needle_size - 1] == needle[needle_size - 1] && std::memcmp(candidate, needle, size_t(needle_size)) == 0)) {
					return int64_t(candidate - haystack);
				}
				candidate++;
			}
			return -1;
		}
	}
#endif
	for (uint64_t i = p_from; i <= last_start; i++) {
		// Avoid calling memcmp / traversing a class sequence when either
		// endpoint already disproves the candidate. For same-type floats,
		// preserve the bitwise memcmp semantics of are_spans_equal().
		if constexpr (!(std::is_same_v<T, T1> && std::is_floating_point_v<T>)) {
			if (haystack[i] != needle[0] || (needle_size > 1 && haystack[i + needle_size - 1] != needle[needle_size - 1])) {
				continue;
			}
		}
		if (are_spans_equal(haystack + i, needle, needle_size)) {
			return i;
		}
	}
	return -1;
}

template <typename T>
constexpr int64_t Span<T>::rfind(const T &p_val, uint64_t p_from) const {
	DEV_ASSERT(p_from < size());
#if defined(__GNUC__) || defined(__clang__)
	if constexpr (std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<std::remove_cv_t<T>, bool>) {
		if (!__builtin_is_constant_evaluated()) {
			// Search 8 bytes per iteration, with no alignment assumptions.
			// The zero-byte test can mark an adjacent nonzero byte after a borrow,
			// so verify candidates in reverse order before returning a match.
			constexpr uint64_t ONE_PER_BYTE = 0x0101010101010101ULL;
			constexpr uint64_t HIGH_BIT_PER_BYTE = 0x8080808080808080ULL;
			const uint64_t repeated_value = uint64_t(uint8_t(p_val)) * ONE_PER_BYTE;
			uint64_t remaining = p_from + 1;
			while (remaining >= sizeof(uint64_t)) {
				remaining -= sizeof(uint64_t);
				uint64_t block;
				std::memcpy(&block, ptr() + remaining, sizeof(block));
				const uint64_t diff = block ^ repeated_value;
				if (((diff - ONE_PER_BYTE) & ~diff & HIGH_BIT_PER_BYTE) != 0) {
					for (uint64_t i = sizeof(uint64_t); i > 0;) {
						--i;
						if (ptr()[remaining + i] == p_val) {
							return int64_t(remaining + i);
						}
					}
				}
			}
			while (remaining > 0) {
				--remaining;
				if (ptr()[remaining] == p_val) {
					return int64_t(remaining);
				}
			}
			return -1;
		}
	}
#endif
	for (int64_t i = p_from; i >= 0; i--) {
		if (ptr()[i] == p_val) {
			return i;
		}
	}
	return -1;
}

template <typename T>
template <typename T1>
constexpr int64_t Span<T>::rfind_sequence(const Span<T1> &p_span, uint64_t p_from) const {
	const uint64_t needle_size = p_span.size();
	if (p_from > size() || needle_size > size() - p_from) {
		return -1;
	}
	if (needle_size == 0) {
		return p_from;
	}

	const T *const haystack = ptr();
	const T1 *const needle = p_span.ptr();
#if defined(__GNUC__) || defined(__clang__)
	if constexpr (std::is_same_v<T, T1> && std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<std::remove_cv_t<T>, bool>) {
		if (!__builtin_is_constant_evaluated()) {
			if (needle_size == 1) {
				return rfind(needle[0], p_from);
			}
			// When the endpoints differ, check eight candidate starts at once.
			// If both endpoints are the same, the scalar path avoids overhead
			// for extremely frequent candidates in repeated-byte buffers.
			if (needle[0] != needle[needle_size - 1]) {
				constexpr uint64_t ONE_PER_BYTE = 0x0101010101010101ULL;
				constexpr uint64_t HIGH_BIT_PER_BYTE = 0x8080808080808080ULL;
				const uint64_t first_pattern = uint64_t(uint8_t(needle[0])) * ONE_PER_BYTE;
				const uint64_t last_pattern = uint64_t(uint8_t(needle[needle_size - 1])) * ONE_PER_BYTE;
				uint64_t remaining = p_from + 1;
				while (remaining >= sizeof(uint64_t)) {
					remaining -= sizeof(uint64_t);
					uint64_t first_word;
					std::memcpy(&first_word, haystack + remaining, sizeof(first_word));
					const uint64_t first_diff = first_word ^ first_pattern;
					const uint64_t first_candidates = (first_diff - ONE_PER_BYTE) & ~first_diff & HIGH_BIT_PER_BYTE;
					if (first_candidates == 0) {
						continue;
					}
					uint64_t last_word;
					std::memcpy(&last_word, haystack + remaining + needle_size - 1, sizeof(last_word));
					const uint64_t last_diff = last_word ^ last_pattern;
					const uint64_t last_candidates = (last_diff - ONE_PER_BYTE) & ~last_diff & HIGH_BIT_PER_BYTE;
					if ((first_candidates & last_candidates) == 0) {
						continue;
					}
					// Borrow propagation can produce false candidate bits.
					// Verify both endpoints in reverse order before comparing the interior.
					for (uint64_t i = sizeof(uint64_t); i > 0;) {
						--i;
						const uint64_t pos = remaining + i;
						if (haystack[pos] == needle[0] &&
								haystack[pos + needle_size - 1] == needle[needle_size - 1] &&
								(needle_size == 2 || std::memcmp(haystack + pos, needle, size_t(needle_size)) == 0)) {
							return int64_t(pos);
						}
					}
				}
				while (remaining > 0) {
					--remaining;
					if (haystack[remaining] == needle[0] &&
							haystack[remaining + needle_size - 1] == needle[needle_size - 1] &&
							(needle_size == 2 || std::memcmp(haystack + remaining, needle, size_t(needle_size)) == 0)) {
						return int64_t(remaining);
					}
				}
				return -1;
			}
		}
	}
#endif
	// Never truncate the unsigned range to signed before walking backwards.
	for (uint64_t i = p_from + 1; i > 0;) {
		--i;
		if constexpr (!(std::is_same_v<T, T1> && std::is_floating_point_v<T>)) {
			if (haystack[i] != needle[0] || (needle_size > 1 && haystack[i + needle_size - 1] != needle[needle_size - 1])) {
				continue;
			}
		}
		if (are_spans_equal(haystack + i, needle, needle_size)) {
			return i;
		}
	}
	return -1;
}

template <typename T>
constexpr uint64_t Span<T>::count(const T &p_val) const {
#if defined(__GNUC__) || defined(__clang__)
	if constexpr (std::is_integral_v<T> && sizeof(T) == 1 && !std::is_same_v<std::remove_cv_t<T>, bool>) {
		// A scalar loop is cheaper for short spans and constexpr evaluation.
		if (!__builtin_is_constant_evaluated() && size() >= 64) {
			constexpr uint64_t ONE_PER_BYTE = 0x0101010101010101ULL;
			constexpr uint64_t LOW_BITS = 0x7F7F7F7F7F7F7F7FULL;
			constexpr uint64_t HIGH_BITS = 0x8080808080808080ULL;
			const uint64_t pattern = uint64_t(uint8_t(p_val)) * ONE_PER_BYTE;
			uint64_t amount = 0;
			uint64_t i = 0;
			while (size() - i >= sizeof(uint64_t)) {
				uint64_t word;
				std::memcpy(&word, ptr() + i, sizeof(word));
				const uint64_t diff = word ^ pattern;
				// Exact per-byte zero test: masking before the addition avoids
				// cross-byte borrows and false matches next to a zero byte.
				const uint64_t matches = ~(((diff & LOW_BITS) + LOW_BITS) | diff) & HIGH_BITS;
				// Each matching byte contributes one; the sum fits in one byte.
				amount += ((matches >> 7) * ONE_PER_BYTE) >> 56;
				i += sizeof(uint64_t);
			}
			for (; i < size(); i++) {
				amount += ptr()[i] == p_val;
			}
			return amount;
		}
	}
#endif
	uint64_t amount = 0;
	for (uint64_t i = 0; i < size(); i++) {
		if (ptr()[i] == p_val) {
			amount++;
		}
	}
	return amount;
}

template <typename T>
template <typename Comparator>
constexpr uint64_t Span<T>::bisect(const T &p_value, bool p_before, Comparator p_compare) const {
	uint64_t lo = 0;
	uint64_t hi = size();
	if (p_before) {
		while (lo < hi) {
			const uint64_t mid = (lo + hi) / 2;
			if (p_compare(ptr()[mid], p_value)) {
				lo = mid + 1;
			} else {
				hi = mid;
			}
		}
	} else {
		while (lo < hi) {
			const uint64_t mid = (lo + hi) / 2;
			if (p_compare(p_value, ptr()[mid])) {
				hi = mid;
			} else {
				lo = mid + 1;
			}
		}
	}
	return lo;
}

template <typename T>
constexpr T Span<T>::max() const {
	DEV_ASSERT(size() > 0);
	T max_val = _ptr[0];
	for (size_t i = 1; i < _len; ++i) {
		if (_ptr[i] > max_val) {
			max_val = _ptr[i];
		}
	}
	return max_val;
}

template <typename LHS, typename RHS>
bool operator==(const Span<LHS> &p_lhs, const Span<RHS> &p_rhs) {
	return p_lhs.size() == p_rhs.size() && are_spans_equal(p_lhs.ptr(), p_rhs.ptr(), p_lhs.size());
}

template <typename LHS, typename RHS>
_FORCE_INLINE_ bool operator!=(const Span<LHS> &p_lhs, const Span<RHS> &p_rhs) {
	return !(p_lhs == p_rhs);
}

// Zero-constructing Span initializes _ptr and _len to 0 (and thus empty).
template <typename T>
struct is_zero_constructible<Span<T>> : std::true_type {};
