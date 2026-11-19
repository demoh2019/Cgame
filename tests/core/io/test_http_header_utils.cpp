/**************************************************************************/
/*  test_http_header_utils.cpp                                            */
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

TEST_FORCE_LINK(test_http_header_utils)

#include "core/io/http_header_utils.h"
#include "core/string/ustring.h"

namespace TestHTTPHeaderUtils {

static bool matches(const String &p_header, const char *p_ascii_lowercase, bool p_exact = false) {
	return HTTPHeaderUtils::matches_ascii_case_insensitive(p_header.span(), p_ascii_lowercase, p_exact);
}

TEST_CASE("[HTTPHeaderFast] Uppercase header names preserve case-insensitive matching") {
	CHECK(matches("Content-Length: 42", "content-length:"));
	CHECK(matches("CONTENT-LENGTH: 42", "content-length:"));
	CHECK(matches("cOnTeNt-LeNgTh: 42", "content-length:"));
	CHECK(matches("Transfer-Encoding: CHUNKED", "transfer-encoding:"));
	CHECK(matches("CONNECTION: CLOSE", "connection: close"));
}

TEST_CASE("[HTTPHeaderFast] Strict token matching rejects suffixes") {
	CHECK(matches("chunked", "chunked", true));
	CHECK(matches("ChUnKeD", "chunked", true));
	CHECK_FALSE(matches("chunked, gzip", "chunked", true));
	CHECK_FALSE(matches("chunkedX", "chunked", true));
	CHECK_FALSE(matches("chunke", "chunked", true));
	CHECK(matches("chunkedX", "chunked", false));
}

TEST_CASE("[HTTPHeaderFast] Header prefixes require complete names") {
	CHECK_FALSE(matches("content-lengt", "content-length:"));
	CHECK_FALSE(matches("content-length", "content-length:"));
	CHECK_FALSE(matches("content-encoding: gzip", "content-length:"));
	CHECK_FALSE(matches("x-content-length: 10", "content-length:"));
	CHECK(matches("content-length:", "content-length:"));
}

TEST_CASE("[HTTPHeaderFast] Empty patterns and empty fields are well-defined") {
	CHECK(matches("", "", true));
	CHECK(matches("a", "", false));
	CHECK_FALSE(matches("a", "", true));
	CHECK_FALSE(matches("", "a", false));
}

TEST_CASE("[HTTPHeaderFast] Non-ASCII cannot accidentally match ASCII names") {
	CHECK_FALSE(matches(String::utf8("cóntent-length: 2"), "content-length:"));
	CHECK_FALSE(matches(String::utf8("cøntent-length: 2"), "content-length:"));
	CHECK(matches("Content-Length: 2", "content-length:"));
}

TEST_CASE("[HTTPHeaderFast] Trimmed ASCII tokens decode without lowercase copies") {
	String field = "TRANSFER-ENCODING:  CHUNKED  ";
	Span<char32_t> value(field.ptr() + sizeof("transfer-encoding:") - 1, field.length() - (sizeof("transfer-encoding:") - 1));
	value = String::strip_edges_span(value, true, true);
	CHECK(HTTPHeaderUtils::matches_ascii_case_insensitive(value, "chunked", true));

	String length = "Content-Length:   123456  ";
	Span<char32_t> count(length.ptr() + sizeof("content-length:") - 1, length.length() - (sizeof("content-length:") - 1));
	count = String::strip_edges_span(count, true, true);
	CHECK_EQ(String::to_int(count.ptr(), count.size()), 123456);
}

TEST_CASE("[HTTPHeaderFast] Connection: close matches identical historical prefixes") {
	CHECK(matches("connection: close", "connection: close"));
	CHECK(matches("Connection: Close ", "connection: close"));
	CHECK(matches("Connection: closed", "connection: close"));
	CHECK_FALSE(matches("Connection: keep-alive", "connection: close"));
}

TEST_CASE("[HTTPHeaderFast] Long ASCII values do not change prefix matching") {
	String field = "Content-Length: ";
	for (int i = 0; i < 1024; ++i) {
		field += '7';
	}
	CHECK(matches(field, "content-length:"));
	CHECK_FALSE(matches(field, "content-length:", true));
	CHECK_FALSE(matches(field, "transfer-encoding:"));
}

} // namespace TestHTTPHeaderUtils
