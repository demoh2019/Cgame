/**************************************************************************/
/*  http_header_utils.h                                                   */
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

#include "core/templates/span.h"

namespace HTTPHeaderUtils {

// HTTP header names and transfer-encoding tokens use ASCII case-insensitive
// matching. Do not allocate a lowercase copy of each received header.
// The pattern must be a lowercase, NUL-terminated ASCII literal.
inline bool matches_ascii_case_insensitive(Span<char32_t> p_text, const char *p_lowercase_pattern, bool p_exact = false) {
	uint64_t i = 0;
	for (; p_lowercase_pattern[i] != 0; i++) {
		if (i >= p_text.size()) {
			return false;
		}
		char32_t character = p_text[i];
		if (character >= U'A' && character <= U'Z') {
			character += U'a' - U'A';
		}
		if (character != static_cast<unsigned char>(p_lowercase_pattern[i])) {
			return false;
		}
	}
	return !p_exact || i == p_text.size();
}

} // namespace HTTPHeaderUtils
