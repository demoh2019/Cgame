/**************************************************************************/
/*  test_tokenizer_buffer_hotpath.cpp                                     */
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

#include "../gdscript_tokenizer.h"
#include "../gdscript_tokenizer_buffer.h"

#include "core/string/string_builder.h"

#include <cstring>

namespace TestGDScriptTokenizerHotpath {

static void compare_text_and_buffer(const String &p_source, GDScriptTokenizerBuffer::CompressMode p_mode) {
	const Vector<uint8_t> binary = GDScriptTokenizerBuffer::parse_code_string(p_source, p_mode);
	REQUIRE(binary.size() > 12);
	CHECK(binary[0] == 'G');
	CHECK(binary[1] == 'D');
	CHECK(binary[2] == 'S');
	CHECK(binary[3] == 'C');

	GDScriptTokenizerText text;
	text.set_source_code(p_source);
	text.set_multiline_mode(true);

	GDScriptTokenizerBuffer buffered;
	REQUIRE(buffered.set_code_buffer(binary) == OK);
	buffered.set_multiline_mode(true);

	int scanned = 0;
	while (scanned < 100000) {
		const GDScriptTokenizer::Token expected = text.scan();
		const GDScriptTokenizer::Token actual = buffered.scan();

		REQUIRE(actual.type == expected.type);
		if (expected.type == GDScriptTokenizer::Token::LITERAL ||
				expected.type == GDScriptTokenizer::Token::ERROR ||
				expected.type == GDScriptTokenizer::Token::IDENTIFIER ||
				expected.type == GDScriptTokenizer::Token::ANNOTATION) {
			CHECK(actual.literal == expected.literal);
		} else if (actual.type == GDScriptTokenizer::Token::CONST_NAN) {
			CHECK(actual.literal == String("NAN"));
		} else {
			// The fast decoder still assigns token-name literals for keywords,
			// punctuation, operators and other non-payload tokens.
			CHECK(actual.literal == String(actual.get_name()));
		}
		scanned++;
		if (expected.type == GDScriptTokenizer::Token::TK_EOF) {
			break;
		}
	}
	CHECK(scanned > 10);
	CHECK(scanned < 100000);
}

TEST_CASE("[GDScriptTokenizerHotpath] Large repeated identifiers and constants roundtrip") {
	StringBuilder source;
	for (int i = 0; i < 1600; i++) {
		source += vformat("var symbol_%d = %d\n", i % 23, i % 29);
		source += vformat("var label_%d = \"unicode_é_日本_%d\"\n", i % 17, i % 13);
		source += vformat("symbol_%d += %d\n", i % 23, i % 29);
	}
	const String code = source.as_string();
	compare_text_and_buffer(code, GDScriptTokenizerBuffer::COMPRESS_NONE);
	compare_text_and_buffer(code, GDScriptTokenizerBuffer::COMPRESS_ZSTD);
}

TEST_CASE("[GDScriptTokenizerHotpath] Long identifier and line continuations roundtrip") {
	const String code = String("var short = 42\n") +
			String("var very_long_identifier_for_gdscript_parser_hot_path_repeated_") + String("x").repeat(1024) +
			String(" = \"unicode_é_日本\"\n") +
			String("var another_value = (\n\t1 +\n\t2\n)\n");
	compare_text_and_buffer(code + code + code + code + code, GDScriptTokenizerBuffer::COMPRESS_NONE);
	compare_text_and_buffer(code + code + code + code + code, GDScriptTokenizerBuffer::COMPRESS_ZSTD);
}


TEST_CASE("[GDScriptTokenizerHotpath] Raw token decoding keeps input untouched and owns the tokens") {
	StringBuilder source;
	for (int i = 0; i < 2200; i++) {
		source += vformat("var symbol_%d = \"value_é_日本_%d\"\n", i % 97, i);
		source += vformat("symbol_%d += %d\n", i % 97, i % 47);
	}
	source += "var special_number = NAN\n";
	const String code = source.as_string();
	Vector<uint8_t> binary = GDScriptTokenizerBuffer::parse_code_string(code, GDScriptTokenizerBuffer::COMPRESS_NONE);
	REQUIRE(binary.size() > 12);

	Vector<uint8_t> original;
	REQUIRE(original.resize(binary.size()) == OK);
	memcpy(original.ptrw(), binary.ptr(), binary.size());

	GDScriptTokenizerBuffer buffered;
	REQUIRE(buffered.set_code_buffer(binary) == OK);
	CHECK(binary == original);
	binary.clear();
	original.clear();

	GDScriptTokenizerText text;
	text.set_source_code(code);
	text.set_multiline_mode(true);
	buffered.set_multiline_mode(true);
	int scanned = 0;
	while (scanned < 100000) {
		const GDScriptTokenizer::Token expected = text.scan();
		const GDScriptTokenizer::Token actual = buffered.scan();
		REQUIRE(actual.type == expected.type);
		if (actual.type == GDScriptTokenizer::Token::LITERAL ||
				actual.type == GDScriptTokenizer::Token::IDENTIFIER ||
				actual.type == GDScriptTokenizer::Token::ANNOTATION) {
			CHECK(actual.literal == expected.literal);
		}
		if (actual.type == GDScriptTokenizer::Token::TK_EOF) {
			break;
		}
		scanned++;
	}
	CHECK(scanned > 10000);
	CHECK(scanned < 100000);
}

TEST_CASE("[GDScriptTokenizerHotpath] Unicode identifiers and punctuation decode correctly") {
	const String code = "var café_value = 42\nvar other_value = café_value + 5\nfunc test():\n\treturn other_value\n";
	compare_text_and_buffer(code, GDScriptTokenizerBuffer::COMPRESS_NONE);
	compare_text_and_buffer(code, GDScriptTokenizerBuffer::COMPRESS_ZSTD);
}

} // namespace TestGDScriptTokenizerHotpath
