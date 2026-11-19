/**************************************************************************/
/*  test_string.cpp                                                       */
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

TEST_FORCE_LINK(test_string)

#include "core/string/char_utils.h"
#include "core/string/ustring.h"

namespace TestString {

int u32scmp(const char32_t *l, const char32_t *r) {
	for (; *l == *r && *l && *r; l++, r++) {
		// Continue.
	}
	return *l - *r;
}

TEST_CASE("[String] Assign Latin-1 char string") {
	String s = "Hello";
	CHECK(u32scmp(s.get_data(), U"Hello") == 0);
}

TEST_CASE("[String] Assign from Latin-1 char string (operator=)") {
	String s = "Dolly";
	const String &t = s;
	CHECK(u32scmp(t.get_data(), U"Dolly") == 0);
}

TEST_CASE("[String] Assign from Latin-1 char string (copycon)") {
	String s("Sheep");
	const String &t1(s);
	CHECK(u32scmp(t1.get_data(), U"Sheep") == 0);

	String t2 = String::latin1(Span("Sheep", 3));
	CHECK(u32scmp(t2.get_data(), U"She") == 0);
}

TEST_CASE("[String] Assign from wchar_t string (operator=)") {
	String s = L"Give me";
	CHECK(u32scmp(s.get_data(), U"Give me") == 0);
}

TEST_CASE("[String] Assign from wchar_t string (copycon)") {
	String s(L"Wool");
	CHECK(u32scmp(s.get_data(), U"Wool") == 0);
}

TEST_CASE("[String] Assign from char32_t string (operator=)") {
	String s = U"Give me";
	CHECK(u32scmp(s.get_data(), U"Give me") == 0);
}

TEST_CASE("[String] Assign from char32_t string (copycon)") {
	String s(U"Wool");
	CHECK(u32scmp(s.get_data(), U"Wool") == 0);
}

TEST_CASE("[String] UTF8") {
	/* how can i embed UTF in here? */
	static const char32_t u32str[] = { 0x0045, 0x0020, 0x304A, 0x360F, 0x3088, 0x3046, 0x1F3A4, 0 };
	static const uint8_t u8str[] = { 0x45, 0x20, 0xE3, 0x81, 0x8A, 0xE3, 0x98, 0x8F, 0xE3, 0x82, 0x88, 0xE3, 0x81, 0x86, 0xF0, 0x9F, 0x8E, 0xA4, 0 };
	String expected = u32str;
	String parsed;
	Error err = parsed.append_utf8(expected.utf8().get_data());
	CHECK(err == OK);
	CHECK(parsed == u32str);

	parsed.clear();
	err = parsed.append_utf8(expected.utf8().span());
	CHECK(err == OK);
	CHECK(parsed == u32str);

	parsed.clear();
	err = parsed.append_utf8((const char *)u8str);
	CHECK(err == OK);
	CHECK(parsed == u32str);

	parsed.clear();
	err = parsed.append_utf8(Span(u8str).reinterpret<char>());
	CHECK(err == OK);
	CHECK(parsed == u32str);

	CharString cs = (const char *)u8str;
	CHECK(String::utf8(cs) == parsed);
}

TEST_CASE("[String] UTF16") {
	/* how can i embed UTF in here? */
	static const char32_t u32str[] = { 0x0045, 0x0020, 0x304A, 0x360F, 0x3088, 0x3046, 0x1F3A4, 0 };
	static const char16_t u16str[] = { 0x0045, 0x0020, 0x304A, 0x360F, 0x3088, 0x3046, 0xD83C, 0xDFA4, 0 };
	String expected = u32str;
	String parsed;
	Error err = parsed.append_utf16(expected.utf16().get_data());
	CHECK(err == OK);
	CHECK(parsed == u32str);

	parsed.clear();
	err = parsed.append_utf16(expected.utf16().span());
	CHECK(err == OK);
	CHECK(parsed == u32str);

	parsed.clear();
	err = parsed.append_utf16(u16str);
	CHECK(err == OK);
	CHECK(parsed == u32str);

	parsed.clear();
	err = parsed.append_utf16(Span(u16str));
	CHECK(err == OK);
	CHECK(parsed == u32str);

	Char16String cs = u16str;
	CHECK(String::utf16(cs) == parsed);
}

TEST_CASE("[String] UTF8 with BOM") {
	/* how can i embed UTF in here? */
	static const char32_t u32str[] = { 0x0045, 0x0020, 0x304A, 0x360F, 0x3088, 0x3046, 0x1F3A4, 0 };
	static const uint8_t u8str[] = { 0xEF, 0xBB, 0xBF, 0x45, 0x20, 0xE3, 0x81, 0x8A, 0xE3, 0x98, 0x8F, 0xE3, 0x82, 0x88, 0xE3, 0x81, 0x86, 0xF0, 0x9F, 0x8E, 0xA4, 0 };
	String s;
	Error err = s.append_utf8((const char *)u8str);
	CHECK(err == OK);
	CHECK(s == u32str);

	CharString cs = (const char *)u8str;
	CHECK(String::utf8(cs) == s);
}

TEST_CASE("[String] UTF16 with BOM") {
	/* how can i embed UTF in here? */
	static const char32_t u32str[] = { 0x0020, 0x0045, 0x304A, 0x360F, 0x3088, 0x3046, 0x1F3A4, 0 };
	static const char16_t u16str[] = { 0xFEFF, 0x0020, 0x0045, 0x304A, 0x360F, 0x3088, 0x3046, 0xD83C, 0xDFA4, 0 };
	static const char16_t u16str_swap[] = { 0xFFFE, 0x2000, 0x4500, 0x4A30, 0x0F36, 0x8830, 0x4630, 0x3CD8, 0xA4DF, 0 };
	String s;
	Error err = s.append_utf16(u16str);
	CHECK(err == OK);
	CHECK(s == u32str);

	s.clear();
	err = s.append_utf16(u16str_swap);
	CHECK(err == OK);
	CHECK(s == u32str);

	Char16String cs = u16str;
	CHECK(String::utf16(cs) == s);

	cs = u16str_swap;
	CHECK(String::utf16(cs) == s);
}

TEST_CASE("[String] Invalid UTF8 (non shortest form sequence)") {
	ERR_PRINT_OFF
	// Examples from the unicode standard : 3.9 Unicode Encoding Forms - Table 3.8.
	static const uint8_t u8str[] = { 0xC0, 0xAF, 0xE0, 0x80, 0xBF, 0xF0, 0x81, 0x82, 0x41, 0 };
	static const char32_t u32str[] = { 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0x41, 0 };
	String s;
	Error err = s.append_utf8((const char *)u8str);
	CHECK(err == ERR_INVALID_DATA);
	CHECK(s == u32str);

	CharString cs = (const char *)u8str;
	CHECK(String::utf8(cs) == s);
	ERR_PRINT_ON
}

TEST_CASE("[String] Invalid UTF8 (ill formed sequences for surrogates)") {
	ERR_PRINT_OFF
	// Examples from the unicode standard : 3.9 Unicode Encoding Forms - Table 3.9.
	static const uint8_t u8str[] = { 0xED, 0xA0, 0x80, 0xED, 0xBF, 0xBF, 0xED, 0xAF, 0x41, 0 };
	static const char32_t u32str[] = { 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0x41, 0 };
	String s;
	Error err = s.append_utf8((const char *)u8str);
	CHECK(err == ERR_INVALID_DATA);
	CHECK(s == u32str);

	CharString cs = (const char *)u8str;
	CHECK(String::utf8(cs) == s);
	ERR_PRINT_ON
}

TEST_CASE("[String] Invalid UTF8 (other ill formed sequences)") {
	ERR_PRINT_OFF
	// Examples from the unicode standard : 3.9 Unicode Encoding Forms - Table 3.10.
	static const uint8_t u8str[] = { 0xF4, 0x91, 0x92, 0x93, 0xFF, 0x41, 0x80, 0xBF, 0x42, 0 };
	static const char32_t u32str[] = { 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0x41, 0xFFFD, 0xFFFD, 0x42, 0 };
	String s;
	Error err = s.append_utf8((const char *)u8str);
	CHECK(err == ERR_INVALID_DATA);
	CHECK(s == u32str);

	CharString cs = (const char *)u8str;
	CHECK(String::utf8(cs) == s);
	ERR_PRINT_ON
}

TEST_CASE("[String] Invalid UTF8 (truncated sequences)") {
	ERR_PRINT_OFF
	// Examples from the unicode standard : 3.9 Unicode Encoding Forms - Table 3.11.
	static const uint8_t u8str[] = { 0xE1, 0x80, 0xE2, 0xF0, 0x91, 0x92, 0xF1, 0xBF, 0x41, 0 };
	static const char32_t u32str[] = { 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0x41, 0 };
	String s;
	Error err = s.append_utf8((const char *)u8str);
	CHECK(err == ERR_INVALID_DATA);
	CHECK(s == u32str);

	CharString cs = (const char *)u8str;
	CHECK(String::utf8(cs) == s);
	ERR_PRINT_ON
}

TEST_CASE("[String] Invalid UTF16 (non-standard)") {
	ERR_PRINT_OFF
	static const char16_t u16str[] = { 0x0045, 0x304A, 0x3088, 0x3046, 0xDFA4, 0 };
	//                                 +       +       +       +       unpaired
	static const char32_t u32str[] = { 0x0045, 0x304A, 0x3088, 0x3046, 0xDFA4, 0 };
	String s;
	Error err = s.append_utf16(u16str);
	CHECK(err == ERR_PARSE_ERROR);
	CHECK(s == u32str);

	Char16String cs = u16str;
	CHECK(String::utf16(cs) == s);
	ERR_PRINT_ON
}

TEST_CASE("[String] ASCII") {
	String s = U"Primero Leche";
	String t = s.ascii(false).get_data();
	CHECK(s == t);

	t = s.ascii(true).get_data();
	CHECK(s == t);
}

TEST_CASE("[String] Comparisons (equal)") {
	String s = "Test Compare";
	CHECK(s == "Test Compare");
	CHECK(s == U"Test Compare");
	CHECK(s == L"Test Compare");
	CHECK(s == String("Test Compare"));

	CharString empty = "";
	CharString cs = "Test Compare";
	CHECK(!(empty == cs));
	CHECK(!(cs == empty));
	CHECK(cs == CharString("Test Compare"));
}

TEST_CASE("[String] Comparisons (not equal)") {
	String s = "Test Compare";
	CHECK(s != "Peanut");
	CHECK(s != U"Coconut");
	CHECK(s != L"Coconut");
	CHECK(s != String("Butter"));
}

TEST_CASE("[String] Comparisons (operator <)") {
	String s = "Bees";
	CHECK(s < "Elephant");
	CHECK(!(s < U"Amber"));
	CHECK(!(s < L"Amber"));
	CHECK(!(s < String("Beatrix")));
}

TEST_CASE("[String] Concatenation") {
	String s;

	s += "Have";
	s += ' ';
	s += 'a';
	s += String(" ");
	s = s + U"Nice";
	s = s + " ";
	s = s + String("Day");

	CHECK(s == "Have a Nice Day");
}

TEST_CASE("[String] Testing size and length of string") {
	// todo: expand this test to do more tests on size() as it is complicated under the hood.
	CHECK(String("Mellon").size() == 7);
	CHECK(String("Mellon1").size() == 8);

	// length works fine and is easier to test
	CHECK(String("Mellon").length() == 6);
	CHECK(String("Mellon1").length() == 7);
	CHECK(String("Mellon2").length() == 7);
	CHECK(String("Mellon3").length() == 7);
}

TEST_CASE("[String] Testing for empty string") {
	CHECK(!String("Mellon").is_empty());
	// do this more than once, to check for string corruption
	CHECK(String("").is_empty());
	CHECK(String("").is_empty());
	CHECK(String("").is_empty());
}

TEST_CASE("[String] Contains") {
	String s = "C:\\Godot\\project\\string_test.tscn";
	CHECK(s.contains(":\\"));
	CHECK(s.contains("Godot"));
	CHECK(s.contains(String("project\\string_test")));
	CHECK(s.contains(String("\\string_test.tscn")));

	CHECK(!s.contains("://"));
	CHECK(!s.contains("Godoh"));
	CHECK(!s.contains(String("project\\string test")));
	CHECK(!s.contains(String("\\char_test.tscn")));
}

TEST_CASE("[String] Contains case insensitive") {
	String s = "C:\\Godot\\project\\string_test.tscn";
	CHECK(s.containsn("Godot"));
	CHECK(s.containsn("godot"));
	CHECK(s.containsn(String("Project\\string_test")));
	CHECK(s.containsn(String("\\string_Test.tscn")));

	CHECK(!s.containsn("Godoh"));
	CHECK(!s.containsn("godoh"));
	CHECK(!s.containsn(String("project\\string test")));
	CHECK(!s.containsn(String("\\char_test.tscn")));
}

TEST_CASE("[String] Test chr") {
	CHECK(String::chr('H') == "H");
	CHECK(String::chr(0x3012)[0] == 0x3012);
	ERR_PRINT_OFF
	CHECK(String::chr(0xd812)[0] == 0xfffd); // Unpaired UTF-16 surrogate
	CHECK(String::chr(0x20d812)[0] == 0xfffd); // Outside UTF-32 range
	ERR_PRINT_ON
}

TEST_CASE("[String] Operator []") {
	String a = "Kugar Sane";
	a[0] = 'S';
	a[6] = 'C';
	CHECK(a == "Sugar Cane");
	CHECK(a[1] == 'u');
	CHECK(a.unicode_at(1) == 'u');
}

TEST_CASE("[String] Case function test") {
	String a = "MoMoNgA";

	CHECK(a.to_upper() == "MOMONGA");
	CHECK(a.to_lower() == "momonga");
}

TEST_CASE("[String] ASCII case conversion fast path") {
	// Exhaustive ASCII coverage, including control characters and punctuation.
	for (char32_t ch = 0; ch < 128; ch++) {
		const char32_t expected_lower = ch >= U'A' && ch <= U'Z' ? ch + (U'a' - U'A') : ch;
		const char32_t expected_upper = ch >= U'a' && ch <= U'z' ? ch - (U'a' - U'A') : ch;
		CHECK(String::char_lowercase(ch) == expected_lower);
		CHECK(String::char_uppercase(ch) == expected_upper);
	}
}

TEST_CASE("[String] Mixed Unicode and ASCII case conversion") {
	CHECK(String::char_lowercase(U'Ä') == U'ä');
	CHECK(String::char_uppercase(U'ä') == U'Ä');
	CHECK(String::char_lowercase(U'Ω') == U'ω');
	CHECK(String::char_uppercase(U'ω') == U'Ω');
	CHECK(String::char_lowercase(U'Я') == U'я');
	CHECK(String::char_uppercase(U'я') == U'Я');
	CHECK(String::char_lowercase(U'😀') == U'😀');
	CHECK(String::char_uppercase(U'😀') == U'😀');
	CHECK(String(U"AbC-ÄΩЯ").to_lower() == U"abc-äωя");
	CHECK(String(U"abc-äωя").to_upper() == U"ABC-ÄΩЯ");
	CHECK(String().to_lower().is_empty());
	CHECK(String().to_upper().is_empty());
}

TEST_CASE("[String] ASCII case conversion matches character mapping") {
	for (char32_t c = 1; c < 128; ++c) {
		const String source = String::chr(c);
		const String uppercase = source.to_upper();
		const String lowercase = source.to_lower();
		CHECK(uppercase.length() == 1);
		CHECK(lowercase.length() == 1);
		CHECK(uppercase[0] == String::char_uppercase(c));
		CHECK(lowercase[0] == String::char_lowercase(c));
	}
}

TEST_CASE("[String] Case conversion preserves Unicode mapping") {
	const String source = U"\u0416\u03A3\u00C4\u212A";
	CHECK(source.to_lower() == String(U"\u0436\u03C3\u00E4k"));
	CHECK(source.to_upper() == source);
	CHECK(String(U"\u0436\u03C3\u00E4k").to_upper() == String(U"\u0416\u03A3\u00C4K"));

	String mixed = "hello WORLD ";
	mixed += String(U"\u0416\u03A3");
	CHECK(mixed.to_lower() == String(U"hello world \u0436\u03C3"));
	CHECK(mixed.to_upper() == String(U"HELLO WORLD \u0416\u03A3"));
}

TEST_CASE("[String] Already normalized case conversion shares original allocation") {
	String lowercase;
	String uppercase;
	for (int i = 0; i < 1024; ++i) {
		lowercase += "the quick brown fox 123 ";
		uppercase += "THE QUICK BROWN FOX 123 ";
	}
	lowercase += String(U"\u0436\u03C3\u00E4");
	uppercase += String(U"\u0416\u03A3\u00C4");

	const char32_t *lower_ptr = lowercase.ptr();
	const char32_t *upper_ptr = uppercase.ptr();
	const String same_lower = lowercase.to_lower();
	const String same_upper = uppercase.to_upper();
	CHECK(same_lower == lowercase);
	CHECK(same_upper == uppercase);
	CHECK(same_lower.ptr() == lower_ptr);
	CHECK(same_upper.ptr() == upper_ptr);
	CHECK(lowercase.ptr() == lower_ptr);
	CHECK(uppercase.ptr() == upper_ptr);
}

TEST_CASE("[String] Case conversion works at start middle end and with embedded NUL") {
	CHECK(String("abcdefgh").to_upper() == "ABCDEFGH");
	CHECK(String("ABCDEFGH").to_lower() == "abcdefgh");
	CHECK(String("111X111").to_lower() == "111x111");
	CHECK(String("111x111").to_upper() == "111X111");
	CHECK(String("111111X").to_lower() == "111111x");
	CHECK(String("111111x").to_upper() == "111111X");

	String embedded = "xQ";
	embedded.resize_uninitialized(5);
	embedded[2] = 0;
	embedded[3] = 'Z';
	embedded[4] = 0;
	CHECK(embedded.to_lower()[1] == 'q');
	CHECK(embedded.to_lower()[2] == 0);
	CHECK(embedded.to_upper()[1] == 'Q');
	CHECK(embedded.to_upper()[2] == 0);
}

TEST_CASE("[String] Case compare function test") {
	String a = "MoMoNgA";

	CHECK(a.casecmp_to("momonga") != 0);
	CHECK(a.nocasecmp_to("momonga") == 0);
}

TEST_CASE("[String] Natural compare function test") {
	String a = "img2.png";

	CHECK(a.nocasecmp_to("img10.png") > 0);
	CHECK(a.naturalnocasecmp_to("img10.png") < 0);
}

TEST_CASE("[String] File compare function test") {
	String a = "_img2.png";
	String b = "img2.png";

	CHECK(a.nocasecmp_to("img10.png") > 0);
	CHECK_MESSAGE(a.filenocasecmp_to("img10.png") < 0, "Should sort before letters.");
	CHECK_MESSAGE(a.filenocasecmp_to(".img10.png") > 0, "Should sort after period.");
	CHECK(b.filenocasecmp_to("img3.png") < 0);
}

TEST_CASE("[String] hex_encode_buffer") {
	static const uint8_t u8str[] = { 0x45, 0xE3, 0x81, 0x8A, 0x8F, 0xE3 };
	String s = String::hex_encode_buffer(u8str, 6);
	CHECK(s == U"45e3818a8fe3");
}

TEST_CASE("[String] Substr") {
	String s = "Killer Baby";
	CHECK(s.substr(3, 4) == "ler ");
	CHECK(s.substr(3) == "ler Baby");
}

TEST_CASE("[String] get_slice reuses first delimiter search") {
	const String input = "alpha::beta::gamma::";
	CHECK(input.get_slice(String("::"), 0) == "alpha");
	CHECK(input.get_slice("::", 0) == "alpha");
	CHECK(input.get_slice(String("::"), 1) == "beta");
	CHECK(input.get_slice("::", 1) == "beta");
	CHECK(input.get_slice(String("::"), 2) == "gamma");
	CHECK(input.get_slice("::", 2) == "gamma");
	CHECK(input.get_slice(String("::"), 3) == "");
	CHECK(input.get_slice("::", 3) == "");
	CHECK(input.get_slice(String("::"), 4) == "");
	CHECK(input.get_slice("::", 4) == "");
}

TEST_CASE("[String] get_slice preserves edge cases for both overloads") {
	const String no_delimiter = "unsplit";
	CHECK(no_delimiter.get_slice(String(":"), 0) == no_delimiter);
	CHECK(no_delimiter.get_slice(":", 0) == no_delimiter);
	CHECK(no_delimiter.get_slice(String(":"), 42) == no_delimiter);
	CHECK(no_delimiter.get_slice(":", 42) == no_delimiter);
	CHECK(no_delimiter.get_slice(String(":"), -1) == "");
	CHECK(no_delimiter.get_slice(":", -1) == "");
	CHECK(no_delimiter.get_slice(String(), 0) == "");
	CHECK(no_delimiter.get_slice("", 0) == "");
	CHECK(no_delimiter.get_slice(nullptr, 0) == "");
	CHECK(String().get_slice(String(":"), 0) == "");
	CHECK(String().get_slice(":", 0) == "");
	const String adjacent = ":a::b:";
	CHECK(adjacent.get_slice(String(":"), 0) == "");
	CHECK(adjacent.get_slice(":", 0) == "");
	CHECK(adjacent.get_slice(String(":"), 1) == "a");
	CHECK(adjacent.get_slice(":", 2) == "");
	CHECK(adjacent.get_slice(String(":"), 3) == "b");
	CHECK(adjacent.get_slice(":", 4) == "");
	CHECK(adjacent.get_slice(":", 5) == "");
}

TEST_CASE("[String] get_slice long and multilingual inputs") {
	String prefix;
	for (int i = 0; i < 256; ++i) {
		prefix += "abcdefghijklmnopqrstuvwxyz012345";
	}
	const String input = prefix + String("::") + String(U"\u0416\u03A3\u00C4") + "::tail";
	CHECK(input.get_slice(String("::"), 0) == prefix);
	CHECK(input.get_slice("::", 0) == prefix);
	CHECK(input.get_slice(String("::"), 1) == String(U"\u0416\u03A3\u00C4"));
	CHECK(input.get_slice("::", 1) == String(U"\u0416\u03A3\u00C4"));
	CHECK(input.get_slice(String("::"), 2) == "tail");
	CHECK(input.get_slice("::", 2) == "tail");
	CHECK(input.get_slice(String("::"), 100) == "");
	CHECK(input.get_slice("::", 100) == "");
	const String unicode_sep = String(U"\u0416\u00A7\u03A3\u00A7\u00C4");
	CHECK(unicode_sep.get_slice(String(U"\u00A7"), 0) == String(U"\u0416"));
	CHECK(unicode_sep.get_slice(String(U"\u00A7"), 1) == String(U"\u03A3"));
	CHECK(unicode_sep.get_slice(String(U"\u00A7"), 2) == String(U"\u00C4"));
}

TEST_CASE("[String] Find") {
	String s = "Pretty Woman Woman";
	MULTICHECK_STRING_EQ(s, find, "tty", 3);
	MULTICHECK_STRING_EQ(s, find, "Revenge of the Monster Truck", -1);
	MULTICHECK_STRING_INT_EQ(s, find, "Wo", 9, 13);
	MULTICHECK_STRING_INT_EQ(s, find, "Wo", 1000, -1);
	MULTICHECK_STRING_INT_EQ(s, find, "Wo", -1, -1);
	MULTICHECK_STRING_EQ(s, find, "", -1);
	MULTICHECK_STRING_EQ(s, find, "Pretty Woman Woman", 0);
	MULTICHECK_STRING_EQ(s, find, "WOMAN", -1);
	MULTICHECK_STRING_INT_EQ(s, find, "", 9, -1);

	MULTICHECK_STRING_EQ(s, rfind, "", -1);
	MULTICHECK_STRING_EQ(s, rfind, "foo", -1);
	MULTICHECK_STRING_EQ(s, rfind, "Pretty Woman Woman", 0);
	MULTICHECK_STRING_EQ(s, rfind, "man", 15);
	MULTICHECK_STRING_EQ(s, rfind, "WOMAN", -1);
	MULTICHECK_STRING_INT_EQ(s, rfind, "", 15, -1);
	MULTICHECK_STRING_INT_EQ(s, rfind, "Wo", 1000, -1);
	MULTICHECK_STRING_INT_EQ(s, rfind, "Wo", -1, 13);
}

TEST_CASE("[String] Find character") {
	String s = "racecar";
	CHECK_EQ(s.find_char('r'), 0);
	CHECK_EQ(s.find_char('r', 1), 6);
	CHECK_EQ(s.find_char('e'), 3);
	CHECK_EQ(s.find_char('e', 4), -1);

	CHECK_EQ(s.rfind_char('r'), 6);
	CHECK_EQ(s.rfind_char('r', 5), 0);
	CHECK_EQ(s.rfind_char('e'), 3);
	CHECK_EQ(s.rfind_char('e', 2), -1);
}

TEST_CASE("[String] Find case insensitive") {
	String s = "Pretty Whale Whale";
	MULTICHECK_STRING_EQ(s, findn, "WHA", 7);
	MULTICHECK_STRING_INT_EQ(s, findn, "WHA", 9, 13);
	MULTICHECK_STRING_INT_EQ(s, findn, "WHA", 1000, -1);
	MULTICHECK_STRING_INT_EQ(s, findn, "WHA", -1, -1);
	MULTICHECK_STRING_EQ(s, findn, "Revenge of the Monster SawFish", -1);
	MULTICHECK_STRING_EQ(s, findn, "", -1);
	MULTICHECK_STRING_EQ(s, findn, "wha", 7);
	MULTICHECK_STRING_EQ(s, findn, "Wha", 7);
	MULTICHECK_STRING_INT_EQ(s, findn, "", 3, -1);

	MULTICHECK_STRING_EQ(s, rfindn, "WHA", 13);
	MULTICHECK_STRING_EQ(s, rfindn, "", -1);
	MULTICHECK_STRING_EQ(s, rfindn, "wha", 13);
	MULTICHECK_STRING_EQ(s, rfindn, "Wha", 13);
	MULTICHECK_STRING_INT_EQ(s, rfindn, "", 13, -1);
	MULTICHECK_STRING_INT_EQ(s, rfindn, "WHA", 1000, -1);
	MULTICHECK_STRING_INT_EQ(s, rfindn, "WHA", -1, 13);
}

TEST_CASE("[String] Find case insensitive ASCII fast path") {
	const String s = "xxaBcDyyABCDzz";
	CHECK(s.findn(String("abcd")) == 2);
	CHECK(s.findn("ABcd") == 2);
	CHECK(s.findn(String("abCd"), 3) == 8);
	CHECK(s.findn("aBcD", 3) == 8);
	CHECK(s.rfindn(String("ABcD")) == 8);
	CHECK(s.rfindn("aBcD") == 8);
	CHECK(s.rfindn(String("aBcD"), 7) == 2);
	CHECK(s.rfindn("abCd", 7) == 2);
	CHECK(s.findn("abCe") == -1);
	CHECK(s.findn(String("abCe")) == -1);
	CHECK(s.findn("ABCDz", 9) == -1);

	String repeated;
	for (int i = 0; i < 128; ++i) {
		repeated += "aBcD";
	}
	CHECK(repeated.findn("ABCD") == 0);
	CHECK(repeated.rfindn("abcd") == 127 * 4);
	CHECK(repeated.findn("abce") == -1);
}

TEST_CASE("[String] Find case insensitive ASCII exhaustive pairs") {
	for (char32_t a = 32; a < 127; ++a) {
		for (char32_t b = 32; b < 127; ++b) {
			const char32_t folded_a = (a >= 'A' && a <= 'Z') ? a + ('a' - 'A') : a;
			const char32_t folded_b = (b >= 'A' && b <= 'Z') ? b + ('a' - 'A') : b;
			const int expected = folded_a == folded_b ? 0 : -1;
			const String source = String::chr(a);
			const String needle = String::chr(b);
			CHECK(source.findn(needle) == expected);
			CHECK(source.rfindn(needle) == expected);
		}
	}
}

TEST_CASE("[String] Find case insensitive Unicode fallback") {
	const String s = U"xx\u212A\u03A3\u00C4yy\u0416\u0423\u041A";
	CHECK(s.findn(String(U"k\u03C3\u00E4")) == 2);
	CHECK(s.rfindn(String(U"k\u03C3\u00E4")) == 2);
	CHECK(s.findn(String(U"\u0436\u0443\u043A")) == 7);
	CHECK(s.rfindn(String(U"\u0436\u0443\u043A")) == 7);
	CHECK(s.findn("k") == 2);
	CHECK(s.rfindn("K") == 2);
	CHECK(s.findn(String(U"k\u03C3\u00E5")) == -1);
	CHECK(s.findn(String(U"\u0436\u0443\u043A"), 8) == -1);
}

TEST_CASE("[String] Find MK") {
	Vector<String> keys;
	keys.push_back("sty");
	keys.push_back("tty");
	keys.push_back("man");

	String s = "Pretty Woman";
	int key = 0;

	CHECK(s.findmk(keys, 0, &key) == 3);
	CHECK(key == 1);

	CHECK(s.findmk(keys, 5, &key) == 9);
	CHECK(key == 2);

	CHECK(s.findmk(keys, -1, &key) == -1);
	CHECK(s.findmk(keys, 1000, &key) == -1);
}

TEST_CASE("[String] Find MK filters middle mismatches and preserves key order") {
	Vector<String> keys;
	keys.push_back("aXYZz");
	keys.push_back("a123z");
	keys.push_back("a12");
	keys.push_back("zz");
	keys.push_back("a123z");
	const String haystack = "qqqa12zzzzza123z";
	int matched_key = -7;
	CHECK(haystack.findmk(keys, 0, &matched_key) == 3);
	CHECK(matched_key == 2);
	CHECK(haystack.findmk(keys, 5, &matched_key) == 6);
	CHECK(matched_key == 3);
	CHECK(haystack.findmk(keys, 11, &matched_key) == 11);
	CHECK(matched_key == 1); // Earlier identical key wins.
	CHECK(haystack.findmk(keys, 99, &matched_key) == -1);
	CHECK(matched_key == 1); // A miss does not alter output metadata.
}

TEST_CASE("[String] Find MK preserves empty keys and UTF32 matching") {
	Vector<String> keys;
	keys.push_back(U"🚀Ω");
	keys.push_back(U"Ω🚀");
	keys.push_back("");
	keys.push_back(U"🚀");
	const String haystack = U"αβΩ🚀γ";
	int matched = -1;
	CHECK(haystack.findmk(keys, 0, &matched) == 0);
	CHECK(matched == 2);
	CHECK(haystack.findmk(keys, 3, &matched) == 3);
	CHECK(matched == 2);

	Vector<String> without_empty;
	without_empty.push_back(U"🚀Ω");
	without_empty.push_back(U"Ω🚀");
	CHECK(haystack.findmk(without_empty, 0, &matched) == 2);
	CHECK(matched == 1);
	CHECK(haystack.findmk(without_empty, 3, &matched) == -1);
	CHECK(matched == 1);
	CHECK(String().findmk(without_empty, 0, &matched) == -1);
	CHECK(matched == 1);
}

TEST_CASE("[String] Find MK deterministic differential search") {
	uint32_t seed = 0x9e3779b9;
	auto next = [&seed]() {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		return seed;
	};
	for (int trial = 0; trial < 180; trial++) {
		String haystack;
		const int haystack_len = 20 + int(next() % 120);
		for (int i = 0; i < haystack_len; i++) {
			haystack += String::chr(U'a' + (next() % 5));
		}
		Vector<String> patterns;
		const int count = 1 + int(next() % 24);
		for (int k = 0; k < count; k++) {
			String token;
			const int n = int(next() % 9);
			for (int j = 0; j < n; j++) {
				token += String::chr(U'a' + (next() % 5));
			}
			patterns.push_back(token);
		}
		for (int j = 0; j < 15; j++) {
			const int from = int(next() % (haystack_len + 8)) - 3;
			int expected_index = -1;
			int expected_key = -1;
			for (int pos = MAX(0, from); pos < haystack.length() && from >= 0 && expected_index < 0; pos++) {
				for (int k = 0; k < patterns.size(); k++) {
					if (patterns[k].length() <= haystack.length() - pos &&
							haystack.substr(pos, patterns[k].length()) == patterns[k]) {
						expected_index = pos;
						expected_key = k;
						break;
					}
				}
			}
			int actual_key = -99;
			CHECK(haystack.findmk(patterns, from, &actual_key) == expected_index);
			if (expected_index >= 0) {
				CHECK(actual_key == expected_key);
			} else {
				CHECK(actual_key == -99);
			}
		}
	}
}

TEST_CASE("[String] Find and replace") {
	String s = "Happy Birthday, Anna!";
	MULTICHECK_STRING_STRING_EQ(s, replace, "Birthday", "Halloween", "Happy Halloween, Anna!");
	MULTICHECK_STRING_STRING_EQ(s, replace_first, "y", "Y", "HappY Birthday, Anna!");
	MULTICHECK_STRING_STRING_EQ(s, replacen, "Y", "Y", "HappY BirthdaY, Anna!");
}

TEST_CASE("[String] Replace character fast path Unicode and ASCII") {
	const String input = "banana";
	CHECK(input.replace(String("a"), String("o")) == "bonono");
	CHECK(input.replace("a", "o") == "bonono");
	CHECK(input.replace(String("x"), String("o")) == input);
	CHECK(input.replace("x", "o") == input);
	CHECK(String(U"αβαβα").replace(String(U"α"), String(U"λ")) == U"λβλβλ");
	CHECK(String(U"ÄÄa").replace(String(U"Ä"), String(U"ä")) == U"ääa");
	CHECK(String(U"😀b😀").replace(String(U"😀"), String(U"★")) == U"★b★");
}

TEST_CASE("[String] Replace char fast path COW and no-op") {
	const String input = "aAaAa";
	const char32_t *before = input.ptr();
	String unchanged = input.replace_char(U'a', U'a');
	CHECK(unchanged.ptr() == before);
	String replacement = input.replace(String("a"), String("a"));
	CHECK(replacement.ptr() == before);
	CHECK(input.replace("a", "a").ptr() == before);
	CHECK(input == "aAaAa");
	CHECK(input.replace_char(U'x', U'y').ptr() == before);
	String changed = input.replace(String("a"), String("b"));
	CHECK(changed == "bAbAb");
	CHECK(input == "aAaAa");
}

TEST_CASE("[String] Replace preserves multi-character semantics") {
	const String input = "aaaa";
	CHECK(input.replace(String("aa"), String("b")) == "bb");
	CHECK(input.replace("aa", "b") == "bb");
	CHECK(input.replace(String("a"), String("")) == "");
	CHECK(input.replace("a", "") == "");
	CHECK(String("ABA").replacen("a", "a") == "aBa");
	CHECK(input.replace(String(""), String("z")) == input);
}

TEST_CASE("[String] Replace deletion fast path and empty repeat") {
	const String ascii = "bananas";
	CHECK(ascii.replace(String("a"), String()) == "bnns");
	CHECK(ascii.replace("a", "") == "bnns");
	CHECK(ascii.replace("as", "") == "banan");
	CHECK(ascii == "bananas");
	const String unicode = U"αβαα";
	CHECK(unicode.replace(String(U"α"), String()) == U"β");
	CHECK(unicode == U"αβαα");
	const String empty = "";
	const char32_t *original = empty.ptr();
	CHECK(empty.repeat(1).ptr() == original);
	CHECK(empty.repeat(500).ptr() == original);
	CHECK(empty.repeat(500).is_empty());
	CHECK(String("ab").repeat(3) == "ababab");
}

TEST_CASE("[String] replace_char") {
	String s = "Banana";
	CHECK(s.replace_char('n', 'x') == "Baxaxa");
	CHECK(s.replace_char('\0', 'x') == "Banana");
	ERR_PRINT_OFF
	CHECK(s.replace_char('n', '\0') == "Banana");
	ERR_PRINT_ON
}

TEST_CASE("[String] replace_chars") {
	String s = "Banana";
	CHECK(s.replace_chars(String("Bn"), 'x') == "xaxaxa");
	CHECK(s.replace_chars("Bn", 'x') == "xaxaxa");
	CHECK(s.replace_chars(String(), 'x') == "Banana");
	CHECK(s.replace_chars("", 'x') == "Banana");
	ERR_PRINT_OFF
	CHECK(s.replace_chars(String("Bn"), '\0') == "Banana");
	CHECK(s.replace_chars("Bn", '\0') == "Banana");
	ERR_PRINT_ON
}

TEST_CASE("[String] Insertion") {
	String s = "Who is Frederic?";
	s = s.insert(s.find("?"), " Chopin");
	CHECK(s == "Who is Frederic Chopin?");

	s = "foobar";
	CHECK(s.insert(0, "X") == "Xfoobar");
	CHECK(s.insert(-100, "X") == "foobar");
	CHECK(s.insert(6, "X") == "foobarX");
	CHECK(s.insert(100, "X") == "foobarX");
	CHECK(s.insert(2, "") == "foobar");

	s = "";
	CHECK(s.insert(0, "abc") == "abc");
	CHECK(s.insert(100, "abc") == "abc");
	CHECK(s.insert(-100, "abc") == "");
	CHECK(s.insert(0, "") == "");
}

TEST_CASE("[String] Erasing") {
	String s = "Josephine is such a cute girl!";
	s = s.erase(s.find("cute "), String("cute ").length());
	CHECK(s == "Josephine is such a girl!");
}

TEST_CASE("[String] Erase preserves Unicode and shares storage on no-op") {
	const String source = U"αβ😀γδ";
	const char32_t *original = source.ptr();

	CHECK(source.erase(0, 2) == U"😀γδ");
	CHECK(source.erase(2, 1) == U"αβγδ");
	CHECK(source.erase(4, 1) == U"αβ😀γ");
	CHECK(source.erase(1, 100) == U"α");
	CHECK(source.erase(0, 100) == "");
	CHECK(source.erase(0, 0).ptr() == original);
	CHECK(source.erase(source.length(), 3).ptr() == original);
	CHECK(source.erase(100000, 3).ptr() == original);
	CHECK(source.erase(3, 0).ptr() == original);
	CHECK(source.erase(2, 0x7fffffff) == U"αβ");
	CHECK(source == U"αβ😀γδ");
	CHECK(source.ptr() == original);

	const String empty;
	CHECK(empty.erase(0, 0).is_empty());
	CHECK(empty.erase(0, 100).is_empty());
}

TEST_CASE("[String] Erase randomized equivalence with substring semantics") {
	uint32_t seed = 0xA1C3B529;
	for (int trial = 0; trial < 512; trial++) {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		const int len = int(seed % 256);

		String input;
		input.resize_uninitialized(len + 1);
		char32_t *chars = input.ptrw();
		for (int i = 0; i < len; i++) {
			chars[i] = (i % 11 == 0) ? U'λ' : char32_t('a' + ((seed + uint32_t(i)) % 26));
		}
		chars[len] = 0;

		const int pos = int((seed >> 8) % uint32_t(len + 17));
		const int count = (trial % 7 == 0) ? 0x7fffffff : int((seed >> 16) % 330);
		const int clamped_count = pos < len ? MIN(count, len - pos) : 0;
		const String expected = input.left(pos) + input.substr(pos + clamped_count);
		CHECK(input.erase(pos, count) == expected);
		CHECK(input.length() == len);
	}
}

TEST_CASE("[String] remove_char") {
	String s = "Banana";
	CHECK(s.remove_char('a') == "Bnn");
	CHECK(s.remove_char('\0') == "Banana");
	CHECK(s.remove_char('x') == "Banana");
}

TEST_CASE("[String] remove_chars") {
	String s = "Banana";
	CHECK(s.remove_chars("Ba") == "nn");
	CHECK(s.remove_chars(String("Ba")) == "nn");
	CHECK(s.remove_chars("") == "Banana");
	CHECK(s.remove_chars(String()) == "Banana");
	CHECK(s.remove_chars("xy") == "Banana");
	CHECK(s.remove_chars(String("xy")) == "Banana");
}

TEST_CASE("[String] remove_chars long ASCII membership mask") {
	String input;
	String expected;
	for (int i = 0; i < 256; ++i) {
		input += "A\tB\nC D\rE-F_";
		expected += "ABCDEF";
	}
	const String original = input;
	CHECK(input.remove_chars(" \t\n\r-_") == expected);
	CHECK(input.remove_chars(String(" \t\n\r-_")) == expected);
	CHECK(input == original);
	CHECK(input.remove_chars("xyz~") == original);

	String only_removed;
	for (int i = 0; i < 100; ++i) {
		only_removed += "@_~ ";
	}
	CHECK(only_removed.remove_chars("@_~ ") == "");
}

TEST_CASE("[String] remove_chars ASCII bit boundary and exhaustive printable input") {
	const String remove_set = String("@_~") + String::chr(127);
	String input;
	String expected;
	for (int repeat = 0; repeat < 4; ++repeat) {
		for (char32_t c = 32; c < 128; ++c) {
			input += String::chr(c);
			if (c != '@' && c != '_' && c != '~' && c != 127) {
				expected += String::chr(c);
			}
		}
	}
	CHECK(input.remove_chars(remove_set) == expected);

	String repeated;
	String kept;
	for (int i = 0; i < 128; ++i) {
		repeated += "@a_b~c";
		repeated += String::chr(127);
		kept += "abc";
	}
	CHECK(repeated.remove_chars(remove_set) == kept);
}

TEST_CASE("[String] remove_chars preserves Unicode with ASCII set and Unicode fallback") {
	String input;
	String ascii_expected;
	String unicode_expected;
	for (int i = 0; i < 32; ++i) {
		input += String(U"\u0416 \u03A3\t\u212A \u00C4");
		ascii_expected += String(U"\u0416\u03A3\u212A\u00C4");
		unicode_expected += String(U"\u212A\u00C4");
	}
	CHECK(input.remove_chars(" \t\r\n") == ascii_expected);
	CHECK(input.remove_chars(String(" \t\r\n")) == ascii_expected);
	CHECK(input.remove_chars(String(U" \u0416\u03A3\t")) == unicode_expected);
	CHECK(String("A B").remove_chars(" \t-_") == "AB");
}

TEST_CASE("[String] Number to string") {
	CHECK(String::num(0) == "0.0"); // The method takes double, so always add zeros.
	CHECK(String::num(0.0) == "0.0");
	CHECK(String::num(-0.0) == "-0.0"); // Includes sign even for zero.
	CHECK(String::num(3.141593) == "3.141593");
	CHECK(String::num(3.141593, 3) == "3.142");
	CHECK(String::num(42.100023, 4) == "42.1"); // No trailing zeros.

	// String::num_int64 tests.
	CHECK(String::num_int64(3141593) == "3141593");
	CHECK(String::num_int64(-3141593) == "-3141593");
	CHECK(String::num_int64(0xA141593, 16) == "a141593");
	CHECK(String::num_int64(0xA141593, 16, true) == "A141593");
	ERR_PRINT_OFF;
	CHECK(String::num_int64(3141593, 1) == ""); // Invalid base < 2.
	CHECK(String::num_int64(3141593, 37) == ""); // Invalid base > 36.
	ERR_PRINT_ON;

	// String::num_uint64 tests.
	CHECK(String::num_uint64(4294967295) == "4294967295");
	CHECK(String::num_uint64(0xF141593, 16) == "f141593");
	CHECK(String::num_uint64(0xF141593, 16, true) == "F141593");
	ERR_PRINT_OFF;
	CHECK(String::num_uint64(4294967295, 1) == ""); // Invalid base < 2.
	CHECK(String::num_uint64(4294967295, 37) == ""); // Invalid base > 36.
	ERR_PRINT_ON;

	// String::num_scientific tests.
	CHECK(String::num_scientific(30000000.0) == "30000000");
	CHECK(String::num_scientific(1234567890.0) == "1234567890");
	CHECK(String::num_scientific(3e100) == "3e+100");
	CHECK(String::num_scientific(7e-100) == "7e-100");
	CHECK(String::num_scientific(Math::TAU) == "6.283185307179586");
	CHECK(String::num_scientific(Math::INF) == "inf");
	CHECK(String::num_scientific(-Math::INF) == "-inf");
	CHECK(String::num_scientific(Math::NaN) == "nan");
	CHECK(String::num_scientific(2.0) == "2");
	CHECK(String::num_scientific(1.0) == "1");
	CHECK(String::num_scientific(0.0) == "0");
	CHECK(String::num_scientific(-0.0) == "-0");

	// String::num_real tests.
	CHECK(String::num_real(1.0) == "1.0");
	CHECK(String::num_real(1.0, false) == "1");
	CHECK(String::num_real(9.9) == "9.9");
	CHECK(String::num_real(9.99) == "9.99");
	CHECK(String::num_real(9.999) == "9.999");
	CHECK(String::num_real(9.9999) == "9.9999");
	CHECK(String::num_real(3.141593) == "3.141593");
	CHECK(String::num_real(3.141) == "3.141"); // No trailing zeros.
#ifdef REAL_T_IS_DOUBLE
	CHECK_MESSAGE(String::num_real(real_t(123.456789)) == "123.456789", "Prints the appropriate amount of digits for real_t = double.");
	CHECK_MESSAGE(String::num_real(real_t(-123.456789)) == "-123.456789", "Prints the appropriate amount of digits for real_t = double.");
	CHECK_MESSAGE(String::num_real(real_t(Math::PI)) == "3.14159265358979", "Prints the appropriate amount of digits for real_t = double.");
	CHECK_MESSAGE(String::num_real(real_t(3.1415f)) == "3.1414999961853", "Prints more digits of 32-bit float when real_t = double (ones that would be reliable for double) and no trailing zero.");
#else
	CHECK_MESSAGE(String::num_real(real_t(123.456789)) == "123.4568", "Prints the appropriate amount of digits for real_t = float.");
	CHECK_MESSAGE(String::num_real(real_t(-123.456789)) == "-123.4568", "Prints the appropriate amount of digits for real_t = float.");
	CHECK_MESSAGE(String::num_real(real_t(Math::PI)) == "3.141593", "Prints the appropriate amount of digits for real_t = float.");
	CHECK_MESSAGE(String::num_real(real_t(3.1415f)) == "3.1415", "Prints only reliable digits of 32-bit float when real_t = float.");
#endif // REAL_T_IS_DOUBLE

	// Checks doubles with many decimal places.
	CHECK(String::num(0.0000012345432123454321, -1) == "0.00000123454321"); // -1 uses 14 as sane default.
	CHECK(String::num(0.0000012345432123454321) == "0.00000123454321"); // -1 is the default value.
	CHECK(String::num(-0.0000012345432123454321) == "-0.00000123454321");
	CHECK(String::num(-10000.0000012345432123454321) == "-10000.0000012345");
	CHECK(String::num(0.0000000000012345432123454321) == "0.00000000000123");
	CHECK(String::num(0.0000000000012345432123454321, 3) == "0.0");

	// Note: When relevant (remainder > 0.5), the last digit gets rounded up,
	// which can also lead to not include a trailing zero, e.g. "...89" -> "...9".
	CHECK(String::num(0.0000056789876567898765) == "0.00000567898766"); // Should round last digit.
	CHECK(String::num(10000.000005678999999999) == "10000.000005679"); // We cut at ...789|99 which is rounded to ...79, so only 13 decimals.
	CHECK(String::num(42.12999999, 6) == "42.13"); // Also happens with lower decimals count.

	// 32 is MAX_DECIMALS. We can't reliably store that many so we can't compare against a string,
	// but we can check that the string length is 34 (32 + 2 for "0.").
	CHECK(String::num(0.00000123456789987654321123456789987654321, 32).length() == 34);
	CHECK(String::num(0.00000123456789987654321123456789987654321, 42).length() == 34); // Should enforce MAX_DECIMALS.
	CHECK(String::num(10000.00000123456789987654321123456789987654321, 42).length() == 38); // 32 decimals + "10000.".
}

TEST_CASE("[String] String to integer") {
	static const char *nums[14] = { "1237461283", "- 22", "0", " - 1123412", "", "10_000_000", "-1_2_3_4", "10__000", "  1  2  34 ", "-0", "007", "--45", "---46", "-7-2" };
	static const int num[14] = { 1237461283, -22, 0, -1123412, 0, 10000000, -1234, 10000, 1234, 0, 7, 45, -46, -72 };

	for (int i = 0; i < 14; i++) {
		CHECK(String(nums[i]).to_int() == num[i]);
	}
	CHECK(String("0b1011").to_int() == 1011); // Looks like a binary number, but to_int() handles this as a base-10 number, "b" is just ignored.
	CHECK(String("0B1011").to_int() == 1011);

	CHECK(String("0x1012").to_int() == 1012); // Looks like a hexadecimal number, but to_int() handles this as a base-10 number, "x" is just ignored.
	CHECK(String("0X1012").to_int() == 1012);

	ERR_PRINT_OFF
	CHECK(String("999999999999999999999999999999999999999999999999999999999").to_int() == INT64_MAX); // Too large, largest possible is returned.
	CHECK(String("-999999999999999999999999999999999999999999999999999999999").to_int() == INT64_MIN); // Too small, smallest possible is returned.
	ERR_PRINT_ON
}

TEST_CASE("[String] Hex to integer") {
	static const char *nums[13] = { "0xFFAE", "22", "0", "AADDAD", "0x7FFFFFFFFFFFFFFF", "-0xf", "", "000", "000f", "0xaA", "-ff", "-", "0XFFAE" };
	static const int64_t num[13] = { 0xFFAE, 0x22, 0, 0xAADDAD, 0x7FFFFFFFFFFFFFFF, -0xf, 0, 0, 0xf, 0xaa, -0xff, 0x0, 0xFFAE };

	for (int i = 0; i < 13; i++) {
		CHECK(String(nums[i]).hex_to_int() == num[i]);
	}

	// Invalid hex strings should return 0.
	static const char *invalid_nums[15] = { "qwerty", "QWERTY", "0xqwerty", "0x00qwerty", "qwerty00", "0x", "0x__", "__", "x12", "+", " ff", "ff ", "f f", "+ff", "--0x78" };

	ERR_PRINT_OFF
	for (int i = 0; i < 15; i++) {
		CHECK(String(invalid_nums[i]).hex_to_int() == 0);
	}

	CHECK(String("0xFFFFFFFFFFFFFFFFFFFFFFF").hex_to_int() == INT64_MAX); // Too large, largest possible is returned.
	CHECK(String("-0xFFFFFFFFFFFFFFFFFFFFFFF").hex_to_int() == INT64_MIN); // Too small, smallest possible is returned.
	ERR_PRINT_ON
}

TEST_CASE("[String] Bin to integer") {
	static const char *nums[11] = { "", "0", "0b0", "0b1", "0b", "1", "0b1010", "-0b11", "-1010", "0b0111111111111111111111111111111111111111111111111111111111111111", "0B1010" };
	static const int64_t num[11] = { 0, 0, 0, 1, 0, 1, 10, -3, -10, 0x7FFFFFFFFFFFFFFF, 10 };

	for (int i = 0; i < 11; i++) {
		CHECK(String(nums[i]).bin_to_int() == num[i]);
	}

	// Invalid bin strings should return 0. The long "0x11...11" is just too long for a 64 bit int.
	static const char *invalid_nums[16] = { "qwerty", "QWERTY", "0bqwerty", "0b00qwerty", "qwerty00", "0x__", "0b__", "__", "b12", "+", "-", "0x12ab", " 11", "11 ", "1 1", "--0b11" };

	for (int i = 0; i < 16; i++) {
		CHECK(String(invalid_nums[i]).bin_to_int() == 0);
	}

	ERR_PRINT_OFF
	CHECK(String("0b111111111111111111111111111111111111111111111111111111111111111111111111111111111").bin_to_int() == INT64_MAX); // Too large, largest possible is returned.
	CHECK(String("-0b111111111111111111111111111111111111111111111111111111111111111111111111111111111").bin_to_int() == INT64_MIN); // Too small, smallest possible is returned.
	ERR_PRINT_ON
}

TEST_CASE("[String] String to float") {
	static const char *nums[12] = { "-12348298412.2", "0.05", "2.0002", " -0.0001", "0", "000", "123", "0.0", "000.000", "000.007", "234__", "3..14" };
	static const double num[12] = { -12348298412.2, 0.05, 2.0002, -0.0001, 0.0, 0.0, 123.0, 0.0, 0.0, 0.007, 234.0, 3.0 };

	for (int i = 0; i < 12; i++) {
		CHECK(!(Math::abs(String(nums[i]).to_float() - num[i]) > 0.00001));
	}

	// Invalid float strings should return 0.
	static const char *invalid_nums[6] = { "qwerty", "qwerty123", "0xffff", "0b1010", "--3.13", "__345" };

	for (int i = 0; i < 6; i++) {
		CHECK(String(invalid_nums[i]).to_float() == 0);
	}

	// Very large exponents.
	CHECK(String("1e308").to_float() == 1e308);
	CHECK(String("-1e308").to_float() == -1e308);

	// Exponent is so high that value is INFINITY/-INFINITY.
	CHECK(String("1e309").to_float() == Math::INF);
	CHECK(String("1e511").to_float() == Math::INF);
	CHECK(String("-1e309").to_float() == -Math::INF);
	CHECK(String("-1e511").to_float() == -Math::INF);

	// Exponent is so high that a warning message is printed. Value is INFINITY/-INFINITY.
	ERR_PRINT_OFF
	CHECK(String("1e512").to_float() == Math::INF);
	CHECK(String("-1e512").to_float() == -Math::INF);
	ERR_PRINT_ON
}

TEST_CASE("[String] Slicing") {
	String s = "Mars,Jupiter,Saturn,Uranus";
	const char *slices[4] = { "Mars", "Jupiter", "Saturn", "Uranus" };
	MULTICHECK_GET_SLICE(s, ",", slices);
}

TEST_CASE("[String] Begins with") {
	// Test cases for true:
	MULTICHECK_STRING_EQ(String("res://foobar"), begins_with, "res://", true);
	MULTICHECK_STRING_EQ(String("abc"), begins_with, "abc", true);
	MULTICHECK_STRING_EQ(String("abc"), begins_with, "", true);
	MULTICHECK_STRING_EQ(String(""), begins_with, "", true);

	// Test cases for false:
	MULTICHECK_STRING_EQ(String("res"), begins_with, "res://", false);
	MULTICHECK_STRING_EQ(String("abcdef"), begins_with, "foo", false);
	MULTICHECK_STRING_EQ(String("abc"), begins_with, "ax", false);
	MULTICHECK_STRING_EQ(String(""), begins_with, "abc", false);

	// Test "const char *" version also with nullptr.
	String s("foo");
	bool state = s.begins_with(nullptr) == false;
	CHECK_MESSAGE(state, "nullptr check failed");

	String empty("");
	state = empty.begins_with(nullptr) == false;
	CHECK_MESSAGE(state, "nullptr check with empty string failed");
}

TEST_CASE("[String] Ends with") {
	// Test cases for true:
	MULTICHECK_STRING_EQ(String("res://foobar"), ends_with, "foobar", true);
	MULTICHECK_STRING_EQ(String("abc"), ends_with, "abc", true);
	MULTICHECK_STRING_EQ(String("abc"), ends_with, "", true);
	MULTICHECK_STRING_EQ(String(""), ends_with, "", true);

	// Test cases for false:
	MULTICHECK_STRING_EQ(String("res"), ends_with, "res://", false);
	MULTICHECK_STRING_EQ(String("abcdef"), ends_with, "foo", false);
	MULTICHECK_STRING_EQ(String("abc"), ends_with, "ax", false);
	MULTICHECK_STRING_EQ(String(""), ends_with, "abc", false);

	// Test "const char *" version also with nullptr.
	String s("foo");
	bool state = s.ends_with(nullptr) == false;
	CHECK_MESSAGE(state, "nullptr check failed");

	String empty("");
	state = empty.ends_with(nullptr) == false;
	CHECK_MESSAGE(state, "nullptr check with empty string failed");
}

TEST_CASE("[String] Split maxsplit tail hotpath regressions") {
	{
		const String s = "one::two::three";
		const char *expected[] = { "one", "two::three" };
		MULTICHECK_SPLIT(s, split, "::", true, 1, expected, 2);
	}
	{
		const String s = ",,tail";
		const char *expected[] = { "", ",tail" };
		MULTICHECK_SPLIT(s, split, ",", true, 1, expected, 2);
	}
	{
		const String s = "head::";
		const char *expected[] = { "head", "" };
		MULTICHECK_SPLIT(s, split, "::", true, 1, expected, 2);
	}
	{
		const String s = "head::";
		const char *expected[] = { "head" };
		MULTICHECK_SPLIT(s, split, "::", false, 1, expected, 1);
	}
	{
		const String s = "a,,,b";
		const char *expected[] = { "a", "b" };
		MULTICHECK_SPLIT(s, split, ",", false, 1, expected, 2);
	}
	{
		const String s = "a,b,c";
		const char *expected[] = { "a", "b,c" };
		MULTICHECK_SPLIT(s, split, ",", false, 1, expected, 2);
	}
	{
		const String s = "abcd";
		const char *expected[] = { "a", "bcd" };
		MULTICHECK_SPLIT(s, split, "", true, 1, expected, 2);
		MULTICHECK_SPLIT(s, split, "", false, 1, expected, 2);
	}
	{
		const String s = "a,b,c";
		const char *expected[] = { "a", "b", "c" };
		MULTICHECK_SPLIT(s, split, ",", true, 0, expected, 3);
	}
	{
		const String s = String(U"Ä|Ω|Я");
		const Vector<String> output = s.split(String("|"), true, 1);
		REQUIRE(output.size() == 2);
		CHECK(output[0] == String(U"Ä"));
		CHECK(output[1] == String(U"Ω|Я"));
	}
	{
		const String tail = String("abcdefghijklmnopqrstuvwxyz").repeat(400);
		const String input = "header:" + tail;
		const Vector<String> output = input.split(String(":"), true, 1);
		const Vector<String> output_cstr = input.split(":", true, 1);
		REQUIRE(output.size() == 2);
		REQUIRE(output_cstr.size() == 2);
		CHECK(output[0] == "header");
		CHECK(output[1] == tail);
		CHECK(output_cstr[0] == "header");
		CHECK(output_cstr[1] == tail);
	}
}

TEST_CASE("[String] Splitting") {
	{
		const String s = "Mars,Jupiter,Saturn,Uranus";

		const char *slices_l[3] = { "Mars", "Jupiter", "Saturn,Uranus" };
		MULTICHECK_SPLIT(s, split, ",", true, 2, slices_l, 3);

		const char *slices_r[3] = { "Mars,Jupiter", "Saturn", "Uranus" };
		MULTICHECK_SPLIT(s, rsplit, ",", true, 2, slices_r, 3);
	}

	{
		const String s = "test";
		const char *slices[4] = { "t", "e", "s", "t" };
		MULTICHECK_SPLIT(s, split, "", true, 0, slices, 4);
	}

	{
		const String s = "";
		const char *slices[1] = { "" };
		MULTICHECK_SPLIT(s, split, "", true, 0, slices, 1);
		MULTICHECK_SPLIT(s, split, "", false, 0, slices, 0);
	}

	{
		const String s = "Mars Jupiter Saturn Uranus";
		const char *slices[4] = { "Mars", "Jupiter", "Saturn", "Uranus" };
		Vector<String> l = s.split_spaces();
		for (int i = 0; i < l.size(); i++) {
			CHECK(l[i] == slices[i]);
		}
	}
	{
		const String s = "Mars Jupiter Saturn Uranus";
		const char *slices[2] = { "Mars", "Jupiter Saturn Uranus" };
		Vector<String> l = s.split_spaces(1);
		for (int i = 0; i < l.size(); i++) {
			CHECK(l[i] == slices[i]);
		}
	}

	{
		const String s = "1.2;2.3 4.5";
		const double slices[3] = { 1.2, 2.3, 4.5 };

		const Vector<double> d_arr = s.split_floats(";");
		CHECK(d_arr.size() == 2);
		for (int i = 0; i < d_arr.size(); i++) {
			CHECK(Math::abs(d_arr[i] - slices[i]) <= 0.00001);
		}

		const Vector<String> keys = { ";", " " };
		const Vector<float> f_arr = s.split_floats_mk(keys);
		CHECK(f_arr.size() == 3);
		for (int i = 0; i < f_arr.size(); i++) {
			CHECK(Math::abs(f_arr[i] - slices[i]) <= 0.00001);
		}
	}

	{
		const String s = " -2.0        5";
		const double slices[10] = { 0, -2, 0, 0, 0, 0, 0, 0, 0, 5 };

		const Vector<double> arr = s.split_floats(" ");
		CHECK(arr.size() == 10);
		for (int i = 0; i < arr.size(); i++) {
			CHECK(Math::abs(arr[i] - slices[i]) <= 0.00001);
		}

		const Vector<String> keys = { ";", " " };
		const Vector<float> mk = s.split_floats_mk(keys);
		CHECK(mk.size() == 10);
		for (int i = 0; i < mk.size(); i++) {
			CHECK(mk[i] == slices[i]);
		}
	}

	{
		const String s = "1;2 4";
		const int slices[3] = { 1, 2, 4 };

		const Vector<int> arr = s.split_ints(";");
		CHECK(arr.size() == 2);
		for (int i = 0; i < arr.size(); i++) {
			CHECK(arr[i] == slices[i]);
		}

		const Vector<String> keys = { ";", " " };
		const Vector<int> mk = s.split_ints_mk(keys);
		CHECK(mk.size() == 3);
		for (int i = 0; i < mk.size(); i++) {
			CHECK(mk[i] == slices[i]);
		}
	}
}

TEST_CASE("[String] format") {
	const String value_format = "red=\"$red\" green=\"$green\" blue=\"$blue\" alpha=\"$alpha\"";

	Dictionary value_dictionary;
	value_dictionary["red"] = 10;
	value_dictionary["green"] = 20;
	value_dictionary["blue"] = "bla";
	value_dictionary["alpha"] = 0.4;
	String value = value_format.format(value_dictionary, "$_");

	CHECK(value == "red=\"10\" green=\"20\" blue=\"bla\" alpha=\"0.4\"");
}

TEST_CASE("[String] sprintf") {
	String format, output;
	Array args;
	bool error;

	// %%
	format = "fish %% frog";
	args.clear();
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish % frog"));
	///// Ints

	// Int
	format = "fish %d frog";
	args.clear();
	args.push_back(5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 5 frog"));

	// Int left padded with zeroes.
	format = "fish %05d frog";
	args.clear();
	args.push_back(5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 00005 frog"));

	// Int left padded with spaces.
	format = "fish %5d frog";
	args.clear();
	args.push_back(5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish     5 frog"));

	// Int right padded with spaces.
	format = "fish %-5d frog";
	args.clear();
	args.push_back(5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 5     frog"));

	// Int with sign (positive).
	format = "fish %+d frog";
	args.clear();
	args.push_back(5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish +5 frog"));

	// Negative int.
	format = "fish %d frog";
	args.clear();
	args.push_back(-5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -5 frog"));

	// Negative int left padded with spaces.
	format = "fish %5d frog";
	args.clear();
	args.push_back(-5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish    -5 frog"));

	// Negative int left padded with zeros.
	format = "fish %05d frog";
	args.clear();
	args.push_back(-5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -0005 frog"));

	// Negative int right padded with spaces.
	format = "fish %-5d frog";
	args.clear();
	args.push_back(-5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -5    frog"));

	// Negative int right padded with zeros. (0 ignored)
	format = "fish %-05d frog";
	args.clear();
	args.push_back(-5);
	ERR_PRINT_OFF; // Silence warning about 0 ignored.
	output = format.sprintf(args, &error);
	ERR_PRINT_ON;
	REQUIRE(error == false);
	CHECK(output == String("fish -5    frog"));

	// Hex (lower)
	format = "fish %x frog";
	args.clear();
	args.push_back(45);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 2d frog"));

	// Hex (upper)
	format = "fish %X frog";
	args.clear();
	args.push_back(45);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 2D frog"));

	// Octal
	format = "fish %o frog";
	args.clear();
	args.push_back(99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 143 frog"));

	// INT64_MIN
	format = "fish %d frog";
	args.clear();
	args.push_back(INT64_MIN);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -9223372036854775808 frog"));

	// INT64_MIN hex (lower)
	format = "fish %x frog";
	args.clear();
	args.push_back(INT64_MIN);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -8000000000000000 frog"));

	// INT64_MIN hex (upper)
	format = "fish %X frog";
	args.clear();
	args.push_back(INT64_MIN);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -8000000000000000 frog"));

	// INT64_MIN octal
	format = "fish %o frog";
	args.clear();
	args.push_back(INT64_MIN);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -1000000000000000000000 frog"));

	///// Reals

	// Real
	format = "fish %f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 99.990000 frog"));

	// Real left-padded.
	format = "fish %11f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish   99.990000 frog"));

	// Real (infinity) left-padded
	format = "fish %11f frog";
	args.clear();
	args.push_back(Math::INF);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish         inf frog"));

	// Real right-padded.
	format = "fish %-11f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 99.990000   frog"));

	// Real given int.
	format = "fish %f frog";
	args.clear();
	args.push_back(99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 99.000000 frog"));

	// Real with sign (positive).
	format = "fish %+f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish +99.990000 frog"));

	// Real with sign (negative zero).
	format = "fish %+f frog";
	args.clear();
	args.push_back(-0.0);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish -0.000000 frog"));

	// Real with sign (positive zero).
	format = "fish %+f frog";
	args.clear();
	args.push_back(0.0);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish +0.000000 frog"));

	// Real with 1 decimal.
	format = "fish %.1f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 100.0 frog"));

	// Real with 12 decimals.
	format = "fish %.12f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 99.990000000000 frog"));

	// Real with no decimals.
	format = "fish %.f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 100 frog"));

	// Negative real right padded with zeros. (0 ignored)
	format = "fish %-011f frog";
	args.clear();
	args.push_back(-99.99);
	ERR_PRINT_OFF; // Silence warning about 0 ignored.
	output = format.sprintf(args, &error);
	ERR_PRINT_ON;
	REQUIRE(error == false);
	CHECK(output == String("fish -99.990000  frog"));

	///// Vectors

	// Vector2
	format = "fish %v frog";
	args.clear();
	args.push_back(Variant(Vector2(19.99, 1.00)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (19.990000, 1.000000) frog"));

	// Vector3
	format = "fish %v frog";
	args.clear();
	args.push_back(Variant(Vector3(19.99, 1.00, -2.05)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (19.990000, 1.000000, -2.050000) frog"));

	// Vector4
	format = "fish %v frog";
	args.clear();
	args.push_back(Variant(Vector4(19.99, 1.00, -2.05, 5.5)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (19.990000, 1.000000, -2.050000, 5.500000) frog"));

	// Vector with negative values.
	format = "fish %v frog";
	args.clear();
	args.push_back(Variant(Vector2(-19.99, -1.00)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (-19.990000, -1.000000) frog"));

	// Vector left-padded.
	format = "fish %11v frog";
	args.clear();
	args.push_back(Variant(Vector3(19.99, 1.00, -2.05)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (  19.990000,    1.000000,   -2.050000) frog"));

	// Vector left-padded with inf/nan
	format = "fish %11v frog";
	args.clear();
	args.push_back(Variant(Vector2(Math::INF, Math::NaN)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (        inf,         nan) frog"));

	// Vector right-padded.
	format = "fish %-11v frog";
	args.clear();
	args.push_back(Variant(Vector3(19.99, 1.00, -2.05)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (19.990000  , 1.000000   , -2.050000  ) frog"));

	// Vector left-padded with zeros.
	format = "fish %011v frog";
	args.clear();
	args.push_back(Variant(Vector3(19.99, 1.00, -2.05)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (0019.990000, 0001.000000, -002.050000) frog"));

	// Vector given Vector3i.
	format = "fish %v frog";
	args.clear();
	args.push_back(Variant(Vector3i(19, 1, -2)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (19.000000, 1.000000, -2.000000) frog"));

	// Vector with 1 decimal.
	format = "fish %.1v frog";
	args.clear();
	args.push_back(Variant(Vector3(19.99, 1.00, -2.05)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (20.0, 1.0, -2.0) frog"));

	// Vector with 12 decimals.
	format = "fish %.12v frog";
	args.clear();
	args.push_back(Variant(Vector3(19.00, 1.00, -2.00)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (19.000000000000, 1.000000000000, -2.000000000000) frog"));

	// Vector with no decimals.
	format = "fish %.v frog";
	args.clear();
	args.push_back(Variant(Vector3(19.99, 1.00, -2.05)));
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish (20, 1, -2) frog"));

	///// Strings

	// String
	format = "fish %s frog";
	args.clear();
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish cheese frog"));

	// String left-padded.
	format = "fish %10s frog";
	args.clear();
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish     cheese frog"));

	// String right-padded.
	format = "fish %-10s frog";
	args.clear();
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish cheese     frog"));

	///// Characters

	// Character as string.
	format = "fish %c frog";
	args.clear();
	args.push_back("A");
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish A frog"));

	// Character as int.
	format = "fish %c frog";
	args.clear();
	args.push_back(65);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish A frog"));

	///// Dynamic width

	// String dynamic width.
	format = "fish %*s frog";
	args.clear();
	args.push_back(10);
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	REQUIRE(output == String("fish     cheese frog"));

	// Int dynamic width.
	format = "fish %*d frog";
	args.clear();
	args.push_back(10);
	args.push_back(99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	REQUIRE(output == String("fish         99 frog"));

	// Float dynamic width.
	format = "fish %*.*f frog";
	args.clear();
	args.push_back(10);
	args.push_back(3);
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish     99.990 frog"));

	///// Argument indices.
	format = "fish %2$d frog %1$s xx";
	args.clear();
	args.push_back("test");
	args.push_back(5);
	output = format.sprintf(args, &error);
	REQUIRE(error == false);
	CHECK(output == String("fish 5 frog test xx"));

	///// Errors

	// More formats than arguments.
	format = "fish %s %s frog";
	args.clear();
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "not enough arguments for format string");

	// More arguments than formats.
	format = "fish %s frog";
	args.clear();
	args.push_back("hello");
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "not all arguments converted during string formatting");

	// Incomplete format.
	format = "fish %10";
	args.clear();
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "incomplete format");

	// Bad character in format string.
	format = "fish %&f frog";
	args.clear();
	args.push_back("cheese");
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "unsupported format character");

	// Too many decimals.
	format = "fish %2.2.2f frog";
	args.clear();
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "too many decimal points in format");

	// * not a number or vector.
	format = "fish %*f frog";
	args.clear();
	args.push_back("cheese");
	args.push_back(99.99);
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "* wants number or vector");

	// Character too long.
	format = "fish %c frog";
	args.clear();
	args.push_back("sc");
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "%c requires number or single-character string");

	// Character bad type.
	format = "fish %c frog";
	args.clear();
	args.push_back(Array());
	output = format.sprintf(args, &error);
	REQUIRE(error);
	CHECK(output == "%c requires number or single-character string");
}

TEST_CASE("[String] is_numeric") {
	CHECK(String("12").is_numeric());
	CHECK(String("1.2").is_numeric());
	CHECK(!String("AF").is_numeric());
	CHECK(String("-12").is_numeric());
	CHECK(String("-1.2").is_numeric());
}

TEST_CASE("[String] pad") {
	String s = String("test");
	CHECK(s.lpad(10, "x") == U"xxxxxxtest");
	CHECK(s.rpad(10, "x") == U"testxxxxxx");

	s = String("10.10");
	CHECK(s.pad_decimals(4) == U"10.1000");
	CHECK(s.pad_decimals(1) == U"10.1");
	CHECK(s.pad_zeros(4) == U"0010.10");
	CHECK(s.pad_zeros(1) == U"10.10");
}

TEST_CASE("[String] is_subsequence_of") {
	String a = "is subsequence of";
	CHECK(String("sub").is_subsequence_of(a));
	CHECK(!String("Sub").is_subsequence_of(a));
	CHECK(String("Sub").is_subsequence_ofn(a));
}

TEST_CASE("[String] is_lowercase") {
	CHECK(String("abcd1234 !@#$%^&*()_-=+,.<>/\\|[]{};':\"`~").is_lowercase());
	CHECK(String("").is_lowercase());
	CHECK(!String("abc_ABC").is_lowercase());
}

TEST_CASE("[String] compound word case conversion linear-path regression") {
	const String inputs[] = {
		String(""),
		String("   "),
		String("a___b"),
		String("a--b"),
		String("HTTPServer2D"),
		String("  hi---there__WORLD  "),
		String("abCD123Digits"),
		String(U"Über_name"),
		String(U"Äpfel_Öl"),
		String(U"Язык_Программирования"),
	};
	// Reconstruct the previous slice-by-slice assembly as a reference using
	// the normalized snake-case output, including its collapsed-space behavior.
	for (const String &input : inputs) {
		const String normalized = input.to_snake_case().replace_char('_', ' ').strip_edges();
		String reference_title;
		String reference_camel;
		String reference_pascal;
		for (int i = 0; i < normalized.get_slice_count(" "); ++i) {
			String slice = normalized.get_slicec(' ', i);
			if (slice.is_empty()) {
				continue;
			}
			String upper = slice;
			upper[0] = String::char_uppercase(upper[0]);
			if (i > 0) {
				reference_title += " ";
			}
			reference_title += upper;
			reference_pascal += upper;
			slice[0] = i == 0 ? String::char_lowercase(slice[0]) : String::char_uppercase(slice[0]);
			reference_camel += slice;
		}
		CHECK(input.capitalize() == reference_title);
		CHECK(input.to_camel_case() == reference_camel);
		CHECK(input.to_pascal_case() == reference_pascal);
	}

	CHECK(String("HTTPRequest2D").to_snake_case() == "http_request_2d");
	CHECK(String(U"Über_name").to_snake_case() == U"über_name");
	CHECK(String(U"Über_name").capitalize() == U"Über Name");
	CHECK(String(U"Über_name").to_camel_case() == U"überName");
	CHECK(String(U"Über_name").to_pascal_case() == U"ÜberName");

	// Large separator-heavy input exercised without intermediate slice allocations.
	const String many = String("a_").repeat(256) + "end";
	CHECK(many.capitalize() == String("A ").repeat(256) + "End");
	CHECK(many.to_camel_case() == "a" + String("A").repeat(255) + "End");
	CHECK(many.to_pascal_case() == String("A").repeat(256) + "End");
	CHECK(many.to_snake_case() == String("a_").repeat(256) + "end");
}

TEST_CASE("[String] match") {
	CHECK(String("img1.png").match("*.png"));
	CHECK(!String("img1.jpeg").match("*.png"));
	CHECK(!String("img1.Png").match("*.png"));
	CHECK(String("img1.Png").matchn("*.png"));
}

TEST_CASE("[String] iterative wildcard matching exhaustive short patterns") {
	// Reference implementation intentionally mirrors the original recursive
	// semantics, but is only used on tiny inputs so it cannot explode.
	auto reference = [](auto &&self, const char32_t *pattern, const char32_t *text, bool case_sensitive) -> bool {
		switch (*pattern) {
			case '\0':
				return !*text;
			case '*':
				return self(self, pattern + 1, text, case_sensitive) || (*text && self(self, pattern, text + 1, case_sensitive));
			case '?':
				return *text && *text != '.' && self(self, pattern + 1, text + 1, case_sensitive);
			default:
				return (case_sensitive ? *text == *pattern : String::char_uppercase(*text) == String::char_uppercase(*pattern)) &&
						self(self, pattern + 1, text + 1, case_sensitive);
		}
	};

	constexpr char32_t text_alphabet[] = { 'a', 'A', 'b', '.' };
	constexpr char32_t pattern_alphabet[] = { 'a', 'b', '.', '?', '*' };
	for (int text_length = 1, text_count = 4; text_length <= 3; ++text_length, text_count *= 4) {
		for (int text_index = 0; text_index < text_count; ++text_index) {
			char32_t text[4] = {};
			int text_number = text_index;
			for (int i = 0; i < text_length; ++i) {
				text[i] = text_alphabet[text_number % 4];
				text_number /= 4;
			}
			const String source(text);
			for (int pattern_length = 1, pattern_count = 5; pattern_length <= 4; ++pattern_length, pattern_count *= 5) {
				for (int pattern_index = 0; pattern_index < pattern_count; ++pattern_index) {
					char32_t pattern[5] = {};
					int pattern_number = pattern_index;
					for (int i = 0; i < pattern_length; ++i) {
						pattern[i] = pattern_alphabet[pattern_number % 5];
						pattern_number /= 5;
					}
					const String wildcard(pattern);
					CHECK(source.match(wildcard) == reference(reference, pattern, text, true));
					CHECK(source.matchn(wildcard) == reference(reference, pattern, text, false));
				}
			}
		}
	}
}

TEST_CASE("[String] iterative wildcard matching pathological and Unicode cases") {
	CHECK(String("a.b").match("a*b"));
	CHECK(!String("a.b").match("a?b")); // '?' never matches period.
	CHECK(String("a.b").match("a*?"));
	CHECK(String("abc").match("a**c"));
	CHECK(!String("abc").match("a**d"));
	CHECK(String("abc").match("**?"));
	CHECK(String("abc").match("*"));
	CHECK(!String("").match("*")); // Preserve String::match's empty-input guard.
	CHECK(!String("abc").match(""));
	CHECK(String(U"ÄΩЯ.txt").matchn(U"*ä?я.TXT"));
	CHECK(!String(U"ÄΩЯ.txt").match(U"*ä?я.TXT"));

	// The recursive matcher has exponential work on this non-matching input.
	// The iterative matcher must handle it with constant extra memory.
	CHECK(!String("a").repeat(128).match(String("*a").repeat(24) + "b"));
	CHECK(String("a").repeat(128).match(String("*a").repeat(24) + "*"));
}

TEST_CASE("[String] ASCII-fast case comparisons preserve ordering and Unicode") {
	CHECK(String("AbCd").nocasecmp_to("aBcD") == 0);
	CHECK(String("abc").nocasecmp_to("ABD") < 0);
	CHECK(String("ABD").nocasecmp_to("abc") > 0);
	CHECK(String(U"ÄΩЯ").nocasecmp_to(U"äωя") == 0);
	CHECK(String(U"Яa").nocasecmp_to(U"яB") < 0);
	CHECK(String("file2").naturalnocasecmp_to("FILE10") < 0);
	CHECK(String(U"Ω2").naturalnocasecmp_to(U"ω10") < 0);
	CHECK(String(U"ÄB").is_subsequence_ofn(U"äXXb"));
	CHECK(!String(U"ÄB").is_subsequence_of(U"äXXb"));
}

TEST_CASE("[String] IPVX address to string") {
	IPAddress ip0("2001:0db8:85a3:0000:0000:8a2e:0370:7334");
	CHECK(ip0.is_valid());

	IPAddress ip(0x0123, 0x4567, 0x89ab, 0xcdef, true);
	CHECK(ip.is_valid());

	IPAddress ip2("fe80::52e5:49ff:fe93:1baf");
	CHECK(ip2.is_valid());

	IPAddress ip3("::ffff:192.168.0.1");
	CHECK(ip3.is_valid());

	String ip4 = "192.168.0.1";
	CHECK(ip4.is_valid_ip_address());

	ip4 = "192.368.0.1";
	CHECK(!ip4.is_valid_ip_address());

	String ip6 = "2001:0db8:85a3:0000:0000:8a2e:0370:7334";
	CHECK(ip6.is_valid_ip_address());

	ip6 = "2001:0db8:85j3:0000:0000:8a2e:0370:7334";
	CHECK(!ip6.is_valid_ip_address());

	ip6 = "2001:0db8:85f345:0000:0000:8a2e:0370:7334";
	CHECK(!ip6.is_valid_ip_address());

	ip6 = "2001:0db8::0:8a2e:370:7334";
	CHECK(ip6.is_valid_ip_address());

	ip6 = "::ffff:192.168.0.1";
	CHECK(ip6.is_valid_ip_address());
}

TEST_CASE("[String] Capitalize against many strings") {
	String input = "2D";
	String output = "2d";
	CHECK(input.capitalize() == output);

	input = "2d";
	output = "2d";
	CHECK(input.capitalize() == output);

	input = "2db";
	output = "2 Db";
	CHECK(input.capitalize() == output);

	input = "HTML5 Html5 html5 html_5";
	output = "Html 5 Html 5 Html 5 Html 5";
	CHECK(input.capitalize() == output);

	input = "Node2D Node2d NODE2D NODE_2D node_2d";
	output = "Node 2d Node 2d Node 2d Node 2d Node 2d";
	CHECK(input.capitalize() == output);

	input = "Node2DPosition";
	output = "Node 2d Position";
	CHECK(input.capitalize() == output);

	input = "Number2Digits";
	output = "Number 2 Digits";
	CHECK(input.capitalize() == output);

	input = "bytes2var";
	output = "Bytes 2 Var";
	CHECK(input.capitalize() == output);

	input = "linear2db";
	output = "Linear 2 Db";
	CHECK(input.capitalize() == output);

	input = "vector3";
	output = "Vector 3";
	CHECK(input.capitalize() == output);

	input = "sha256";
	output = "Sha 256";
	CHECK(input.capitalize() == output);

	input = "PascalCase";
	output = "Pascal Case";
	CHECK(input.capitalize() == output);

	input = "PascalPascalCase";
	output = "Pascal Pascal Case";
	CHECK(input.capitalize() == output);

	input = "snake_case";
	output = "Snake Case";
	CHECK(input.capitalize() == output);

	input = "snake_snake_case";
	output = "Snake Snake Case";
	CHECK(input.capitalize() == output);

	input = "kebab-case";
	output = "Kebab Case";
	CHECK(input.capitalize() == output);

	input = "kebab-kebab-case";
	output = "Kebab Kebab Case";
	CHECK(input.capitalize() == output);

	input = "sha256sum";
	output = "Sha 256 Sum";
	CHECK(input.capitalize() == output);

	input = "cat2dog";
	output = "Cat 2 Dog";
	CHECK(input.capitalize() == output);

	input = "function(name)";
	output = "Function(name)";
	CHECK(input.capitalize() == output);

	input = "snake_case_function(snake_case_arg)";
	output = "Snake Case Function(snake Case Arg)";
	CHECK(input.capitalize() == output);

	input = "snake_case_function( snake_case_arg )";
	output = "Snake Case Function( Snake Case Arg )";
	CHECK(input.capitalize() == output);

	input = "kebab-case-function( kebab-case-arg )";
	output = "Kebab Case Function( Kebab Case Arg )";
	CHECK(input.capitalize() == output);

	input = "kebab_case_function( kebab_case_arg )";
	output = "Kebab Case Function( Kebab Case Arg )";
	CHECK(input.capitalize() == output);

	input = U"словоСлово_слово слово";
	output = U"Слово Слово Слово Слово";
	CHECK(input.capitalize() == output);

	input = U"λέξηΛέξη_λέξη λέξη";
	output = U"Λέξη Λέξη Λέξη Λέξη";
	CHECK(input.capitalize() == output);

	input = U"բառԲառ_բառ բառ";
	output = U"Բառ Բառ Բառ Բառ";
	CHECK(input.capitalize() == output);
}

struct StringCasesTestCase {
	const char32_t *input;
	const char32_t *camel_case;
	const char32_t *pascal_case;
	const char32_t *snake_case;
	const char32_t *kebab_case;
};

TEST_CASE("[String] Checking case conversion methods") {
	StringCasesTestCase test_cases[] = {
		/* clang-format off */
		{ U"2D",                     U"2d",                   U"2d",                   U"2d",                      U"2d"                      },
		{ U"2d",                     U"2d",                   U"2d",                   U"2d",                      U"2d"                      },
		{ U"2db",                    U"2Db",                  U"2Db",                  U"2_db",                    U"2-db"                    },
		{ U"Vector3",                U"vector3",              U"Vector3",              U"vector_3",                U"vector-3"                },
		{ U"sha256",                 U"sha256",               U"Sha256",               U"sha_256",                 U"sha-256"                 },
		{ U"Node2D",                 U"node2d",               U"Node2d",               U"node_2d",                 U"node-2d"                 },
		{ U"RichTextLabel",          U"richTextLabel",        U"RichTextLabel",        U"rich_text_label",         U"rich-text-label"         },
		{ U"HTML5",                  U"html5",                U"Html5",                U"html_5",                  U"html-5"                  },
		{ U"Node2DPosition",         U"node2dPosition",       U"Node2dPosition",       U"node_2d_position",        U"node-2d-position"        },
		{ U"Number2Digits",          U"number2Digits",        U"Number2Digits",        U"number_2_digits",         U"number-2-digits"         },
		{ U"get_property_list",      U"getPropertyList",      U"GetPropertyList",      U"get_property_list",       U"get-property-list"       },
		{ U"get_camera_2d",          U"getCamera2d",          U"GetCamera2d",          U"get_camera_2d",           U"get-camera-2d"           },
		{ U"_physics_process",       U"physicsProcess",       U"PhysicsProcess",       U"_physics_process",        U"-physics-process"        },
		{ U"bytes2var",              U"bytes2Var",            U"Bytes2Var",            U"bytes_2_var",             U"bytes-2-var"             },
		{ U"linear2db",              U"linear2Db",            U"Linear2Db",            U"linear_2_db",             U"linear-2-db"             },
		{ U"sha256sum",              U"sha256Sum",            U"Sha256Sum",            U"sha_256_sum",             U"sha-256-sum"             },
		{ U"camelCase",              U"camelCase",            U"CamelCase",            U"camel_case",              U"camel-case"              },
		{ U"PascalCase",             U"pascalCase",           U"PascalCase",           U"pascal_case",             U"pascal-case"             },
		{ U"snake_case",             U"snakeCase",            U"SnakeCase",            U"snake_case",              U"snake-case"              },
		{ U"kebab-case",             U"kebabCase",            U"KebabCase",            U"kebab_case",              U"kebab-case"              },
		{ U"Test TEST test",         U"testTestTest",         U"TestTestTest",         U"test_test_test",          U"test-test-test"          },
		{ U"словоСлово_слово слово", U"словоСловоСловоСлово", U"СловоСловоСловоСлово", U"слово_слово_слово_слово", U"слово-слово-слово-слово" },
		{ U"λέξηΛέξη_λέξη λέξη",     U"λέξηΛέξηΛέξηΛέξη",     U"ΛέξηΛέξηΛέξηΛέξη",     U"λέξη_λέξη_λέξη_λέξη",     U"λέξη-λέξη-λέξη-λέξη"     },
		{ U"բառԲառ_բառ բառ",         U"բառԲառԲառԲառ",         U"ԲառԲառԲառԲառ",         U"բառ_բառ_բառ_բառ",         U"բառ-բառ-բառ-բառ"         },
		{ nullptr,                   nullptr,                 nullptr,                 nullptr,                    nullptr                    },
		/* clang-format on */
	};

	int idx = 0;
	while (test_cases[idx].input != nullptr) {
		String input = test_cases[idx].input;
		CHECK(input.to_camel_case() == test_cases[idx].camel_case);
		CHECK(input.to_pascal_case() == test_cases[idx].pascal_case);
		CHECK(input.to_snake_case() == test_cases[idx].snake_case);
		CHECK(input.to_kebab_case() == test_cases[idx].kebab_case);
		idx++;
	}
}

TEST_CASE("[String] Checking string is empty when it should be") {
	bool state = true;
	bool success;

	String a = "";
	success = a[0] == 0;
	if (!success) {
		state = false;
	}
	String b = "Godot";
	success = b[b.size()] == 0;
	if (!success) {
		state = false;
	}
	const String c = "";
	success = c[0] == 0;
	if (!success) {
		state = false;
	}

	const String d = "Godot";
	success = d[d.size()] == 0;
	if (!success) {
		state = false;
	}

	CHECK(state);
}

TEST_CASE("[String] lstrip and rstrip") {
#define STRIP_TEST(x) \
	{ \
		bool success = x; \
		state = state && success; \
	}

	bool state = true;

	// strip none
	STRIP_TEST(String("abc").lstrip("") == "abc");
	STRIP_TEST(String("abc").rstrip("") == "abc");
	// strip one
	STRIP_TEST(String("abc").lstrip("a") == "bc");
	STRIP_TEST(String("abc").rstrip("c") == "ab");
	// strip lots
	STRIP_TEST(String("bababbababccc").lstrip("ab") == "ccc");
	STRIP_TEST(String("aaabcbcbcbbcbbc").rstrip("cb") == "aaa");
	// strip empty string
	STRIP_TEST(String("").lstrip("") == "");
	STRIP_TEST(String("").rstrip("") == "");
	// strip to empty string
	STRIP_TEST(String("abcabcabc").lstrip("bca") == "");
	STRIP_TEST(String("abcabcabc").rstrip("bca") == "");
	// don't strip wrong end
	STRIP_TEST(String("abc").lstrip("c") == "abc");
	STRIP_TEST(String("abca").lstrip("a") == "bca");
	STRIP_TEST(String("abc").rstrip("a") == "abc");
	STRIP_TEST(String("abca").rstrip("a") == "abc");
	// in utf-8 "¿" (\u00bf) has the same first byte as "µ" (\u00b5)
	// and the same second as "ÿ" (\u00ff)
	STRIP_TEST(String::utf8("¿").lstrip(String::utf8("µÿ")) == String::utf8("¿"));
	STRIP_TEST(String::utf8("¿").rstrip(String::utf8("µÿ")) == String::utf8("¿"));
	STRIP_TEST(String::utf8("µ¿ÿ").lstrip(String::utf8("µÿ")) == String::utf8("¿ÿ"));
	STRIP_TEST(String::utf8("µ¿ÿ").rstrip(String::utf8("µÿ")) == String::utf8("µ¿"));

	// the above tests repeated with additional superfluous strip chars

	// strip none
	STRIP_TEST(String("abc").lstrip("qwjkl") == "abc");
	STRIP_TEST(String("abc").rstrip("qwjkl") == "abc");
	// strip one
	STRIP_TEST(String("abc").lstrip("qwajkl") == "bc");
	STRIP_TEST(String("abc").rstrip("qwcjkl") == "ab");
	// strip lots
	STRIP_TEST(String("bababbababccc").lstrip("qwabjkl") == "ccc");
	STRIP_TEST(String("aaabcbcbcbbcbbc").rstrip("qwcbjkl") == "aaa");
	// strip empty string
	STRIP_TEST(String("").lstrip("qwjkl") == "");
	STRIP_TEST(String("").rstrip("qwjkl") == "");
	// strip to empty string
	STRIP_TEST(String("abcabcabc").lstrip("qwbcajkl") == "");
	STRIP_TEST(String("abcabcabc").rstrip("qwbcajkl") == "");
	// don't strip wrong end
	STRIP_TEST(String("abc").lstrip("qwcjkl") == "abc");
	STRIP_TEST(String("abca").lstrip("qwajkl") == "bca");
	STRIP_TEST(String("abc").rstrip("qwajkl") == "abc");
	STRIP_TEST(String("abca").rstrip("qwajkl") == "abc");
	// in utf-8 "¿" (\u00bf) has the same first byte as "µ" (\u00b5)
	// and the same second as "ÿ" (\u00ff)
	STRIP_TEST(String::utf8("¿").lstrip(String::utf8("qwaµÿjkl")) == String::utf8("¿"));
	STRIP_TEST(String::utf8("¿").rstrip(String::utf8("qwaµÿjkl")) == String::utf8("¿"));
	STRIP_TEST(String::utf8("µ¿ÿ").lstrip(String::utf8("qwaµÿjkl")) == String::utf8("¿ÿ"));
	STRIP_TEST(String::utf8("µ¿ÿ").rstrip(String::utf8("qwaµÿjkl")) == String::utf8("µ¿"));

	CHECK(state);

#undef STRIP_TEST
}

TEST_CASE("[String] Ensuring empty string into extend_utf8 passes empty string") {
	String empty;
	CHECK(empty.append_utf8(nullptr, -1) == ERR_INVALID_DATA);
}

TEST_CASE("[String] Cyrillic to_lower()") {
	String upper = U"АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ";
	String lower = U"абвгдеёжзийклмнопрстуфхцчшщъыьэюя";

	String test = upper.to_lower();

	bool state = test == lower;

	CHECK(state);
}

TEST_CASE("[String] bounded count without substring allocations") {
	// The previous implementation copied the selected substring and called
	// find/findn on that copy. Use it as an independent oracle for every range.
	auto legacy_string_count = [](const String &source, const String &needle, int from, int to, bool insensitive) -> int {
		if (needle.is_empty() || source.length() < needle.length() || from < 0 || to < 0) {
			return 0;
		}
		if (to == 0) {
			to = source.length();
		} else if (from >= to) {
			return 0;
		}
		const String section = source.substr(from, to - from);
		int result = 0;
		int offset = 0;
		while ((offset = insensitive ? section.findn(needle, offset) : section.find(needle, offset)) >= 0) {
			offset += needle.length();
			++result;
		}
		return result;
	};
	auto legacy_cstring_count = [](const String &source, const char *needle, int from, int to, bool insensitive) -> int {
		const int needle_len = strlen(needle);
		if (needle_len == 0 || source.length() < needle_len || from < 0 || to < 0) {
			return 0;
		}
		if (to == 0) {
			to = source.length();
		} else if (from >= to) {
			return 0;
		}
		const String section = source.substr(from, to - from);
		int result = 0;
		int offset = 0;
		while ((offset = insensitive ? section.findn(needle, offset) : section.find(needle, offset)) >= 0) {
			offset += needle_len;
			++result;
		}
		return result;
	};

	const String sources[] = { "ababA.baaABA", "TestTestTest", U"ÄbÄBbÄ", "", "aaaaaaa" };
	const String patterns[] = { "a", "A", "aa", "aba", "bA", "Test", "xyz", U"Ä", U"ä", "" };
	const char *byte_patterns[] = { "a", "A", "aa", "aba", "bA", "Test", "xyz", "" };
	for (const String &source : sources) {
		for (int from = -1; from <= source.length() + 2; ++from) {
			for (int to = -1; to <= source.length() + 2; ++to) {
				for (const String &pattern : patterns) {
					CHECK(source.count(pattern, from, to) == legacy_string_count(source, pattern, from, to, false));
					CHECK(source.countn(pattern, from, to) == legacy_string_count(source, pattern, from, to, true));
				}
				for (const char *pattern : byte_patterns) {
					CHECK(source.count(pattern, from, to) == legacy_cstring_count(source, pattern, from, to, false));
					CHECK(source.countn(pattern, from, to) == legacy_cstring_count(source, pattern, from, to, true));
				}
			}
		}
	}

	const String big = String("a").repeat(4096) + "b";
	CHECK(big.count("a", 1024, 3072) == 2048);
	CHECK(big.count("aa", 1024, 3072) == 1024);
	CHECK(big.count("b", 0, 4096) == 0);
	CHECK(big.count("b", 4096, 4097) == 1);
	CHECK(big.countn("A", 1024, 3072) == 2048);
}

TEST_CASE("[String] Count and countn functionality") {
	String s = String("");
	MULTICHECK_STRING_EQ(s, count, "Test", 0);

	s = "Test";
	MULTICHECK_STRING_EQ(s, count, "", 0);

	s = "Test";
	MULTICHECK_STRING_EQ(s, count, "test", 0);

	s = "Test";
	MULTICHECK_STRING_EQ(s, count, "TEST", 0);

	s = "TEST";
	MULTICHECK_STRING_EQ(s, count, "TEST", 1);

	s = "Test";
	MULTICHECK_STRING_EQ(s, count, "Test", 1);

	s = "aTest";
	MULTICHECK_STRING_EQ(s, count, "Test", 1);

	s = "Testa";
	MULTICHECK_STRING_EQ(s, count, "Test", 1);

	s = "TestTestTest";
	MULTICHECK_STRING_EQ(s, count, "Test", 3);

	s = "TestTestTest";
	MULTICHECK_STRING_EQ(s, count, "TestTest", 1);

	s = "TestGodotTestGodotTestGodot";
	MULTICHECK_STRING_EQ(s, count, "Test", 3);

	s = "TestTestTestTest";
	MULTICHECK_STRING_INT_INT_EQ(s, count, "Test", 4, 8, 1);

	s = "TestTestTestTest";
	MULTICHECK_STRING_INT_INT_EQ(s, count, "Test", 4, 12, 2);

	s = "TestTestTestTest";
	MULTICHECK_STRING_INT_INT_EQ(s, count, "Test", 4, 16, 3);

	s = "TestTestTestTest";
	MULTICHECK_STRING_INT_EQ(s, count, "Test", 4, 3);

	s = "Test";
	MULTICHECK_STRING_EQ(s, countn, "test", 1);

	s = "Test";
	MULTICHECK_STRING_EQ(s, countn, "TEST", 1);

	s = "testTest-Testatest";
	MULTICHECK_STRING_EQ(s, countn, "tEst", 4);

	s = "testTest-TeStatest";
	MULTICHECK_STRING_INT_INT_EQ(s, countn, "tEsT", 4, 16, 2);
}

TEST_CASE("[String] Bigrams") {
	String s = "abcd";
	Vector<String> bigr = s.bigrams();

	CHECK(bigr.size() == 3);
	CHECK(bigr[0] == "ab");
	CHECK(bigr[1] == "bc");
	CHECK(bigr[2] == "cd");
}

TEST_CASE("[String] c-escape/unescape") {
	String s = "\\1\a2\b\f3\n45\r6\t7\v8\'9\?0\"";
	CHECK(s.c_escape().c_unescape() == s);
}

TEST_CASE("[String] indent linear-time empty lines and Unicode") {
	CHECK(String().indent("  ").is_empty());
	CHECK(String("\n\n").indent("  ") == "\n\n");
	CHECK(String("a\n\nb\n").indent("  ") == "  a\n\n  b\n");
	CHECK(String("a\n\nb").indent("  ") == "  a\n\n  b");
	CHECK(String("\r\n\n").indent("\t") == "\t\r\n\n");
	CHECK(String(U"α\nβ\n").indent(U"▸") == U"▸α\n▸β\n");
	CHECK(String(U"α\nβ").indent(U"\n") == U"\nα\n\nβ");
	const String original = U"α\n\nβ";
	const String same = original.indent("");
	CHECK(same.ptr() == original.ptr());
	CHECK(same == original);
	const String blank = "\n\n";
	CHECK(blank.indent("\t").ptr() == blank.ptr());
}

TEST_CASE("[String] indent linear-time large multiline input") {
	String input;
	String expected;
	for (int i = 0; i < 4096; i++) {
		if (i % 3 == 0) {
			input += "\n";
			expected += "\n";
		} else {
			input += U"script α\n";
			expected += U"  script α\n";
		}
	}
	CHECK(input.indent("  ") == expected);
	CHECK(input.indent("") == input);
}

TEST_CASE("[String] indent") {
	static const char *input[] = {
		"",
		"aaa\nbbb",
		"\tcontains\n\tindent",
		"empty\n\nline",
	};
	static const char *expected[] = {
		"",
		"\taaa\n\tbbb",
		"\t\tcontains\n\t\tindent",
		"\tempty\n\n\tline",
	};

	for (int i = 0; i < 3; i++) {
		CHECK(String(input[i]).indent("\t") == expected[i]);
	}
}

TEST_CASE("[String] dedent linear-time whitespace and Unicode") {
	CHECK(String().dedent().is_empty());
	CHECK(String("   ").dedent().is_empty());
	CHECK(String("  \n \n").dedent() == "\n\n");
	CHECK(String("    first\n  second\n").dedent() == "first\nsecond\n");
	CHECK(String("    first\n     second").dedent() == "first\n second");
	CHECK(String(" \tfirst\n  second").dedent() == "first\n second");
	CHECK(String("\r\n  first\n\tsecond").dedent() == "\nfirst\n\tsecond");
	CHECK(String(U"  α\n β\n").dedent() == U"α\nβ\n");
	CHECK(String(U"    😀\n  α").dedent() == U"😀\nα");
	const String original = U"no indentation α\nsecond line";
	String unchanged = original.dedent();
	CHECK(unchanged.ptr() == original.ptr());
	CHECK(unchanged == original);
}

TEST_CASE("[String] dedent linear-time large multiline input") {
	String input;
	String expected;
	for (int i = 0; i < 2048; i++) {
		switch (i % 4) {
			case 0:
				input += "    \n";
				expected += "\n";
				break;
			case 1:
				input += U"    αβ and text\n";
				expected += U"αβ and text\n";
				break;
			case 2:
				input += U"  β\n";
				expected += U"β\n";
				break;
			default:
				input += "     more text\n";
				expected += " more text\n";
				break;
		}
	}
	CHECK(input.dedent() == expected);
}

TEST_CASE("[String] dedent") {
	String s = "      aaa\n    bbb";
	String t = "aaa\nbbb";
	CHECK(s.dedent() == t);
}

TEST_CASE("[String] Path functions") {
	static const char *path[8] = { "C:\\Godot\\project\\test.tscn", "/Godot/project/test.xscn", "../Godot/project/test.scn", "Godot\\test.doc", "C:\\test.", "res://test", "user://test", "/.test" };
	static const char *base_dir[8] = { "C:\\Godot\\project", "/Godot/project", "../Godot/project", "Godot", "C:\\", "res://", "user://", "/" };
	static const char *base_name[8] = { "C:\\Godot\\project\\test", "/Godot/project/test", "../Godot/project/test", "Godot\\test", "C:\\test", "res://test", "user://test", "/" };
	static const char *ext[8] = { "tscn", "xscn", "scn", "doc", "", "", "", "test" };
	static const char *file[8] = { "test.tscn", "test.xscn", "test.scn", "test.doc", "test.", "test", "test", ".test" };
	static const char *simplified[8] = { "C:/Godot/project/test.tscn", "/Godot/project/test.xscn", "../Godot/project/test.scn", "Godot/test.doc", "C:/test.", "res://test", "user://test", "/.test" };
	static const bool abs[8] = { true, true, false, false, true, true, true, true };

	for (int i = 0; i < 8; i++) {
		CHECK(String(path[i]).get_base_dir() == base_dir[i]);
		CHECK(String(path[i]).get_basename() == base_name[i]);
		CHECK(String(path[i]).get_extension() == ext[i]);
		CHECK(String(path[i]).get_file() == file[i]);
		CHECK(String(path[i]).is_absolute_path() == abs[i]);
		CHECK(String(path[i]).is_relative_path() != abs[i]);
		CHECK(String(path[i]).simplify_path() == String(simplified[i]));
		CHECK(String(path[i]).simplify_path().get_base_dir().path_join(file[i]) == String(path[i]).simplify_path());
	}

	CHECK(String("res://test.png").has_extension("png"));
	CHECK(String("res://test.PNG").has_extension("png"));
	CHECK_FALSE(String("res://test.png").has_extension("jpg"));
	CHECK_FALSE(String("res://test.png/README").has_extension("png"));
	CHECK_FALSE(String("res://test.").has_extension("png"));
	CHECK_FALSE(String("res://test").has_extension("png"));

	static const char *file_name[3] = { "test.tscn", "test://.xscn", "?tes*t.scn" };
	static const bool valid[3] = { true, false, false };
	for (int i = 0; i < 3; i++) {
		CHECK(String(file_name[i]).is_valid_filename() == valid[i]);
	}

	CHECK(String("res://texture.png") == String("res://folder/../folder/../texture.png").simplify_path());
	CHECK(String("res://texture.png") == String("res://folder/sub/../../texture.png").simplify_path());
	CHECK(String("res://../../texture.png") == String("res://../../texture.png").simplify_path());
}

TEST_CASE("[String] Path extraction single-pass regressions") {
	struct PathCase {
		const char *path;
		const char *base_dir;
		const char *file;
		const char *extension;
	};

	static const PathCase cases[] = {
		{ "", "", "", "" },
		{ "file", "", "file", "" },
		{ "file.tar.gz", "", "file.tar.gz", "gz" },
		{ "file.", "", "file.", "" },
		{ ".hidden", "", ".hidden", "hidden" },
		{ "folder/file.ext", "folder", "file.ext", "ext" },
		{ "folder/", "folder", "", "" },
		{ "folder\\sub/file.ext", "folder\\sub", "file.ext", "ext" },
		{ "file.txt/folder", "file.txt", "folder", "" },
		{ "/file", "/", "file", "" },
		{ "/", "/", "", "" },
		{ "res://", "res://", "", "" },
		{ "res://file", "res://", "file", "" },
		{ "res://folder/sub/", "res://folder/sub", "", "" },
		{ "user://addons\\script.gd", "user://addons", "script.gd", "gd" },
		{ "C:\\file", "C:\\", "file", "" },
		{ "C:\\folder\\file.txt", "C:\\folder", "file.txt", "txt" },
		{ "//server/share/file.txt", "//server/share/", "file.txt", "txt" },
		{ "//server/share/dir/file.txt", "//server/share/dir", "file.txt", "txt" },
		{ "\\\\server\\share\\file.txt", "\\\\server\\share\\", "file.txt", "txt" },
	};

	for (const PathCase &test : cases) {
		const String path(test.path);
		CHECK(path.get_base_dir() == test.base_dir);
		CHECK(path.get_file() == test.file);
		CHECK(path.get_extension() == test.extension);
	}
}

TEST_CASE("[String] hash") {
	String a = "Test";
	String b = "Test";
	String c = "West";
	CHECK(a.hash() == b.hash());
	CHECK(a.hash() != c.hash());

	CHECK(a.hash64() == b.hash64());
	CHECK(a.hash64() != c.hash64());
}

TEST_CASE("[String] uri_encode fast path preserves UTF-8 bytes and COW storage") {
	const String safe = "AbcXYZ_0123456789-._~";
	const char32_t *original = safe.ptr();
	CHECK(safe.uri_encode() == safe);
	CHECK(safe.uri_encode().ptr() == original);

	CHECK(String("").uri_encode() == "");
	CHECK(String(" /?#&+=:%").uri_encode() == "%20%2F%3F%23%26%2B%3D%3A%25");
	CHECK(String(U"é").uri_encode() == "%C3%A9");
	CHECK(String(U"😊").uri_encode() == "%F0%9F%98%8A");
	CHECK(String(U"Aé B").uri_encode() == "A%C3%A9%20B");

	const String unicode = U"żółć 😀/茶";
	CHECK(unicode.uri_encode().uri_decode() == unicode);
	CHECK(unicode == U"żółć 😀/茶");
}

TEST_CASE("[String] uri_encode randomized byte-for-byte equivalence") {
	static constexpr char HEX[] = "0123456789ABCDEF";
	uint32_t seed = 0x1E52C7AB;
	for (int trial = 0; trial < 384; trial++) {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		const int len = int(seed % 150);
		String input;
		input.resize_uninitialized(len + 1);
		char32_t *input_data = input.ptrw();
		for (int i = 0; i < len; i++) {
			const uint32_t n = (seed + uint32_t(i) * 11) % 37;
			input_data[i] = n == 0 ? U'😀' : (n == 1 ? U'β' : char32_t(32 + (n * 29) % 95));
		}
		input_data[len] = 0;

		// Independent reference implementation matching the original byte-wise loop.
		String expected;
		const CharString utf8 = input.utf8();
		for (int i = 0; i < utf8.length(); i++) {
			const uint8_t byte = uint8_t(utf8[i]);
			const bool unreserved = (byte >= 'a' && byte <= 'z') ||
					(byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') ||
					byte == '-' || byte == '_' || byte == '.' || byte == '~';
			if (unreserved) {
				expected += byte;
			} else {
				expected += '%';
				expected += HEX[byte >> 4];
				expected += HEX[byte & 0xF];
			}
		}
		CHECK(input.uri_encode() == expected);
		CHECK(input.length() == len);
	}
}

TEST_CASE("[String] uri_encode/unescape") {
	String s = "Godot Engine:'docs'";
	String t = "Godot%20Engine%3A%27docs%27";

	String x1 = "T%C4%93%C5%A1t";
	static const uint8_t u8str[] = { 0x54, 0xC4, 0x93, 0xC5, 0xA1, 0x74, 0x00 };
	String x2 = String::utf8((const char *)u8str);
	String x3 = U"Tēšt";
	String x4 = U"file+name";
	String x5 = U"%5B%5b+%5d%5D";

	CHECK(x1.uri_decode() == x2);
	CHECK(x1.uri_decode() == x3);
	CHECK((x1 + x3).uri_decode() == (x2 + x3)); // Mixed unicode and URL encoded string, e.g. GTK+ bookmark.
	CHECK(x2.uri_encode() == x1);
	CHECK(x3.uri_encode() == x1);

	CHECK(s.uri_encode() == t);
	CHECK(t.uri_decode() == s);
	CHECK(x4.uri_file_decode() == x4);
	CHECK(x4.uri_decode() == U"file name");
	CHECK(x5.uri_file_decode() == U"[[+]]");
	CHECK(x5.uri_decode() == U"[[ ]]");
}

TEST_CASE("[String] xml_escape single-buffer entities and COW no-op") {
	const String safe = U"unchanged σαβ text";
	const char32_t *safe_ptr = safe.ptr();
	CHECK(safe.xml_escape().ptr() == safe_ptr);
	CHECK(safe.xml_escape(false).ptr() == safe_ptr);

	const String special = "&<>'\"";
	CHECK(special.xml_escape(true) == "&amp;&lt;&gt;&apos;&quot;");
	CHECK(special.xml_escape(false) == "&amp;&lt;&gt;'\"");
	CHECK(String("&amp;").xml_escape() == "&amp;amp;");
	CHECK(String(U"🌍<&'\">").xml_escape() == U"🌍&lt;&amp;&apos;&quot;&gt;");
	CHECK(String("&&&&&&").xml_escape() == "&amp;&amp;&amp;&amp;&amp;&amp;");
	CHECK(special == "&<>'\"");
}

TEST_CASE("[String] xml_escape randomized equivalence to ordered substitutions") {
	uint32_t seed = 0x9812D45B;
	for (int trial = 0; trial < 384; trial++) {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		const int len = int(seed % 150);
		String input;
		input.resize_uninitialized(len + 1);
		char32_t *data = input.ptrw();
		for (int i = 0; i < len; i++) {
			static constexpr char32_t alphabet[] = U"A&B<'\">γ😀 -_";
			data[i] = alphabet[(seed + uint32_t(i) * 23) % (sizeof(alphabet) / sizeof(char32_t) - 1)];
		}
		data[len] = 0;
		const bool escape_quotes = trial % 2 == 0;

		String expected = input.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
		if (escape_quotes) {
			expected = expected.replace("'", "&apos;").replace("\"", "&quot;");
		}
		CHECK(input.xml_escape(escape_quotes) == expected);
		CHECK(input.length() == len);
	}
}

TEST_CASE("[String] xml_escape/unescape") {
	String s = "\"Test\" <test@test&'test'>";
	CHECK(s.xml_escape(true).xml_unescape() == s);
	CHECK(s.xml_escape(false).xml_unescape() == s);
}

TEST_CASE("[String] xml_unescape") {
	// Named entities
	String input = "&quot;&amp;&apos;&lt;&gt;";
	CHECK(input.xml_unescape() == "\"&\'<>");

	// Numeric entities
	input = "&#x41;&#66;";
	CHECK(input.xml_unescape() == "AB");

	input = "&#0;&x#0;More text";
	String result = input.xml_unescape();
	// Didn't put in a leading NUL and terminate the string
	CHECK(input.length() > 0);
	CHECK(input[0] != '\0');
	// Entity should be left as-is if invalid
	CHECK(input.xml_unescape() == input);

	// Check near char32_t range
	input = "&#xFFFFFFFF;";
	result = input.xml_unescape();
	CHECK(result.length() == 1);
	CHECK(result[0] == 0xFFFFFFFF);
	input = "&#4294967295;";
	result = input.xml_unescape();
	CHECK(result.length() == 1);
	CHECK(result[0] == 0xFFFFFFFF);

	// Check out of range of char32_t
	input = "&#xFFFFFFFFF;";
	CHECK(input.xml_unescape() == input);
	input = "&#4294967296;";
	CHECK(input.xml_unescape() == input);

	// Shouldn't consume without ending in a ';'
	input = "&#66";
	CHECK(input.xml_unescape() == input);
	input = "&#x41";
	CHECK(input.xml_unescape() == input);

	// Invalid characters should make the entity ignored
	input = "&#x41SomeIrrelevantText;";
	CHECK(input.xml_unescape() == input);
	input = "&#66SomeIrrelevantText;";
	CHECK(input.xml_unescape() == input);
}

TEST_CASE("[String] Strip escapes") {
	String s = "\t\tTest Test\r\n Test";
	CHECK(s.strip_escapes() == "Test Test Test");
}

TEST_CASE("[String] Strip escapes single allocation and unchanged COW") {
	const String plain = U"ASCII \u041f\u0440\u0438\u0432\u0435\u0442 \U0001F600";
	const String unchanged = plain.strip_escapes();
	CHECK(unchanged == plain);
	CHECK(unchanged.ptr() == plain.ptr());

	CHECK(String("").strip_escapes() == "");
	CHECK(String("\r\n\t").strip_escapes() == "");
	CHECK(String("A\x01""B\tC\r\nD").strip_escapes() == "ABCD");
	CHECK(String(U"\u041f\t\u0440\n\u0438").strip_escapes() == U"\u041f\u0440\u0438");
	CHECK(String("\x7f").strip_escapes() == "\x7f"); // DEL is not a C0 control character.

	const String input = String("a\t").repeat(8192) + "z";
	CHECK(input.strip_escapes() == String("a").repeat(8192) + "z");
	CHECK(input.length() == 16385); // The original COW source remains intact.
}

TEST_CASE("[String] Linear path normalization preserves prefixes and parent traversal") {
	static const char *const paths[] = {
		"a////b/./c/../d",
		"a/../../b",
		"res://a/../../b",
		"user://a/../../b",
		"/../../a///b",
		"a/..",
		"a/../..",
		"./a/./b/",
		"a\\b\\\\c\\..\\end",
		"a///b///c",
		"res://folder/../file",
		"",
		".",
		"..",
		"../..",
		"//server///share/../file",
	};
	static const char *const expected[] = {
		"a/b/d",
		"../b",
		"res://../b",
		"user://b",
		"/a/b",
		"",
		"..",
		"a/b",
		"a/b/end",
		"a/b/c",
		"res://file",
		"",
		"",
		"..",
		"../..",
		"//server/file",
	};
	static_assert(sizeof(paths) / sizeof(paths[0]) == sizeof(expected) / sizeof(expected[0]));
	for (unsigned int i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
		CHECK(String(paths[i]).simplify_path() == expected[i]);
	}

	// Long runs of separators and parent-directory components previously
	// performed multiple full-string replacements and O(n^2) vector shifts.
	const String separators = String("dir////").repeat(2048) + "file.tscn";
	CHECK(separators.simplify_path() == String("dir/").repeat(2048) + "file.tscn");

	const String parents = String("dir/").repeat(2048) + String("../").repeat(2048) + "file.tscn";
	CHECK(parents.simplify_path() == "file.tscn");
	CHECK((String("/") + parents).simplify_path() == "/file.tscn");
	CHECK((String("res://") + parents).simplify_path() == "res://file.tscn");
}

TEST_CASE("[String] Canonical paths reuse the original COW allocation") {
	const String relative = "folder/assets/scene.tscn";
	const String resource = U"res://\u041f\u0430\u043f\u043a\u0430/\u0444\u0430\u0439\u043b_\U0001F600.tscn";
	const String user = "user://saves/slot1.dat";
	const String unix_absolute = "/var/data/level.tscn";
	const String unc = "//server/share/file.tscn";
	for (const String &path : { relative, resource, user, unix_absolute, unc }) {
		const String normalized = path.simplify_path();
		CHECK(normalized == path);
		CHECK(normalized.ptr() == path.ptr());
	}

	// Non-canonical paths must still use the normalizer rather than the shortcut.
	CHECK(String("dir//file").simplify_path() == "dir/file");
	CHECK(String("dir\\file").simplify_path() == "dir/file");
	CHECK(String("dir/./file").simplify_path() == "dir/file");
	CHECK(String("dir/../file").simplify_path() == "file");
	CHECK(String("res://../file").simplify_path() == "res://../file");

	const String long_canonical = String("folder/").repeat(4096) + "file.tscn";
	const String long_result = long_canonical.simplify_path();
	CHECK(long_result == long_canonical);
	CHECK(long_result.ptr() == long_canonical.ptr());
}

TEST_CASE("[String] Similarity indexed bigram branch matches quadratic reference") {
	auto reference = [](const String &p_source, const String &p_target) -> float {
		if (p_source == p_target) {
			return 1.0f;
		}
		if (p_source.length() < 2 || p_target.length() < 2) {
			return 0.0f;
		}
		const int source_size = p_source.length() - 1;
		const int target_size = p_target.length() - 1;
		int matched = 0;
		for (int i = 0; i < source_size; ++i) {
			for (int j = 0; j < target_size; ++j) {
				if (p_source[i] == p_target[j] && p_source[i + 1] == p_target[j + 1]) {
					++matched;
					break;
				}
			}
		}
		return (2.0f * matched) / (source_size + target_size);
	};

	const String pool = U"abcXYZ:\u0416\u03A3\u00C4";
	uint32_t state = 0x41234123;
	for (int test = 0; test < 240; ++test) {
		state = state * 1664525U + 1013904223U;
		const int first_len = state % 185;
		state = state * 1664525U + 1013904223U;
		const int second_len = state % 185;
		String first;
		String second;
		for (int i = 0; i < first_len; ++i) {
			state = state * 1664525U + 1013904223U;
			first += String::chr(pool[state % pool.length()]);
		}
		for (int i = 0; i < second_len; ++i) {
			state = state * 1664525U + 1013904223U;
			second += String::chr(pool[state % pool.length()]);
		}
		CHECK(first.similarity(second) == reference(first, second));
		CHECK(second.similarity(first) == reference(second, first));
	}

	const String duplicate = String("a").repeat(160);
	const String mixed = String("a").repeat(80) + String("b").repeat(80);
	CHECK(duplicate.similarity(mixed) == reference(duplicate, mixed));
	CHECK(mixed.similarity(duplicate) == reference(mixed, duplicate));
	CHECK(String("a").repeat(1024).similarity(String("z").repeat(512)) == 0.0f);
}

TEST_CASE("[String] Case-insensitive subsequence exhaustive printable ASCII") {
	for (char32_t a = 32; a < 127; ++a) {
		for (char32_t b = 32; b < 127; ++b) {
			const bool expected = String::char_lowercase(a) == String::char_lowercase(b);
			CHECK(String::chr(a).is_subsequence_ofn(String::chr(b)) == expected);
		}
	}
}

TEST_CASE("[String] Case-insensitive subsequence mixed Unicode matching") {
	CHECK(String(U"k").is_subsequence_ofn(String(U"\u212A")));
	CHECK(String(U"\u212A").is_subsequence_ofn(String("K")));
	CHECK(String(U"\u03C3").is_subsequence_ofn(String(U"\u03A3")));
	CHECK(String(U"\u0436").is_subsequence_ofn(String(U"\u0416")));
	CHECK(String(U"\u00E4").is_subsequence_ofn(String(U"\u00C4")));
	CHECK(String(U"\u0416k\u03A3").is_subsequence_ofn(String(U"foo\u0436bar\u212Axyz\u03C3")));
	CHECK(!String(U"\u0416\u03A3").is_subsequence_of(String(U"\u0436\u03C3")));
	CHECK(!String("aC").is_subsequence_ofn("abbb"));
	CHECK(String().is_subsequence_ofn(String("abc")));
}

TEST_CASE("[String] Similarity") {
	String a = "Test";
	String b = "West";
	String c = "Toad";
	CHECK(a.similarity(b) > a.similarity(c));
}

TEST_CASE("[String] Strip edges") {
	String s = "\t Test Test   ";
	CHECK(s.strip_edges(true, false) == "Test Test   ");
	CHECK(s.strip_edges(false, true) == "\t Test Test");
	CHECK(s.strip_edges(true, true) == "Test Test");
}

TEST_CASE("[String] Trim") {
	String s = "aaaTestbbb";
	MULTICHECK_STRING_EQ(s, trim_prefix, "aaa", "Testbbb");
	MULTICHECK_STRING_EQ(s, trim_prefix, "Test", s);
	MULTICHECK_STRING_EQ(s, trim_prefix, "", s);
	MULTICHECK_STRING_EQ(s, trim_prefix, "aaaTestbbb", "");
	MULTICHECK_STRING_EQ(s, trim_prefix, "bbb", s);
	MULTICHECK_STRING_EQ(s, trim_prefix, "AAA", s);

	MULTICHECK_STRING_EQ(s, trim_suffix, "bbb", "aaaTest");
	MULTICHECK_STRING_EQ(s, trim_suffix, "Test", s);
	MULTICHECK_STRING_EQ(s, trim_suffix, "", s);
	MULTICHECK_STRING_EQ(s, trim_suffix, "aaaTestbbb", "");
	MULTICHECK_STRING_EQ(s, trim_suffix, "aaa", s);
	MULTICHECK_STRING_EQ(s, trim_suffix, "BBB", s);
}

TEST_CASE("[String] Right/Left") {
	String s = "aaaTestbbb";
	//                ^
	CHECK(s.right(6) == "estbbb");
	CHECK(s.right(-6) == "tbbb");
	CHECK(s.left(6) == "aaaTes");
	CHECK(s.left(-6) == "aaaT");
}

TEST_CASE("[String] Repeat") {
	String s = "abababab";
	String x = "ab";
	String t = x.repeat(4);
	CHECK(t == s);
}

TEST_CASE("[String] Repeat creates one independent output and preserves shared source") {
	const String original = U"тест🙂";
	const String shared = original;
	const char32_t *original_ptr = original.ptr();
	const String repeated = original.repeat(73);
	REQUIRE_EQ(repeated.length(), original.length() * 73);
	CHECK(original.ptr() == original_ptr);
	CHECK(shared.ptr() == original_ptr);
	CHECK(repeated.ptr() != original_ptr);
	for (int i = 0; i < 73; i++) {
		CHECK_EQ(repeated.substr(i * original.length(), original.length()), original);
	}
	CHECK_EQ(repeated[repeated.length()], char32_t(0));
}

TEST_CASE("[String] Repeat handles non power-of-two boundaries and long output") {
	const String token = "abcdEFGH";
	const String result = token.repeat(10001);
	REQUIRE_EQ(result.length(), token.length() * 10001);
	for (int i = 0; i < 10001; i += 137) {
		CHECK_EQ(result.substr(i * token.length(), token.length()), token);
	}
	CHECK_EQ(result.substr(result.length() - token.length()), token);
	CHECK_EQ(result[result.length()], char32_t(0));
}

TEST_CASE("[String] Repeat rejects signed overflow without allocating") {
	const String original = "abcdef";
	ERR_PRINT_OFF;
	CHECK(original.repeat(0x7fffffff).is_empty());
	CHECK(original.repeat(-1).is_empty());
	ERR_PRINT_ON;
	CHECK(original == "abcdef");
	CHECK(original.repeat(0).is_empty());
	CHECK(original.repeat(1).ptr() == original.ptr());
	CHECK(String().repeat(100000).is_empty());
}

TEST_CASE("[String] Repeat matches incremental concatenation over varied inputs") {
	const String cases[] = { "x", "hello", U"Ω", "a\nb", "0123456789ABCDEF" };
	for (const String &input : cases) {
		for (int count = 0; count < 81; count++) {
			String expected;
			for (int i = 0; i < count; i++) {
				expected += input;
			}
			CHECK(input.repeat(count) == expected);
		}
	}
}

TEST_CASE("[String] Reverse") {
	String s = "Abcd";
	CHECK(s.reverse() == "dcbA");
}

TEST_CASE("[String] SHA1/SHA256/MD5") {
	String s = "Godot";
	String sha1 = "a1e91f39b9fce6a9998b14bdbe2aa2b39dc2d201";
	static uint8_t sha1_buf[20] = {
		0xA1, 0xE9, 0x1F, 0x39, 0xB9, 0xFC, 0xE6, 0xA9, 0x99, 0x8B, 0x14, 0xBD, 0xBE, 0x2A, 0xA2, 0xB3,
		0x9D, 0xC2, 0xD2, 0x01
	};
	String sha256 = "2a02b2443f7985d89d09001086ae3dcfa6eb0f55c6ef170715d42328e16e6cb8";
	static uint8_t sha256_buf[32] = {
		0x2A, 0x02, 0xB2, 0x44, 0x3F, 0x79, 0x85, 0xD8, 0x9D, 0x09, 0x00, 0x10, 0x86, 0xAE, 0x3D, 0xCF,
		0xA6, 0xEB, 0x0F, 0x55, 0xC6, 0xEF, 0x17, 0x07, 0x15, 0xD4, 0x23, 0x28, 0xE1, 0x6E, 0x6C, 0xB8
	};
	String md5 = "4a336d087aeb0390da10ee2ea7cb87f8";
	static uint8_t md5_buf[16] = {
		0x4A, 0x33, 0x6D, 0x08, 0x7A, 0xEB, 0x03, 0x90, 0xDA, 0x10, 0xEE, 0x2E, 0xA7, 0xCB, 0x87, 0xF8
	};

	PackedByteArray buf = s.sha1_buffer();
	CHECK(memcmp(sha1_buf, buf.ptr(), 20) == 0);
	CHECK(s.sha1_text() == sha1);

	buf = s.sha256_buffer();
	CHECK(memcmp(sha256_buf, buf.ptr(), 32) == 0);
	CHECK(s.sha256_text() == sha256);

	buf = s.md5_buffer();
	CHECK(memcmp(md5_buf, buf.ptr(), 16) == 0);
	CHECK(s.md5_text() == md5);
}

TEST_CASE("[String] Join") {
	String comma = ", ";
	String empty = "";
	Vector<String> parts;

	CHECK(comma.join(parts) == "");
	CHECK(empty.join(parts) == "");

	parts.push_back("One");
	CHECK(comma.join(parts) == "One");
	CHECK(empty.join(parts) == "One");

	parts.push_back("B");
	parts.push_back("C");
	CHECK(comma.join(parts) == "One, B, C");
	CHECK(empty.join(parts) == "OneBC");

	parts.push_back("");
	CHECK(comma.join(parts) == "One, B, C, ");
	CHECK(empty.join(parts) == "OneBC");
}

TEST_CASE("[String] Is_*") {
	static const char *data[] = { "-30", "100", "10.1", "10,1", "1e2", "1e-2", "1e2e3", "0xAB", "AB", "Test1", "1Test", "Test*1", "文字", "1E2", "1E-2" };
	static bool isnum[] = { true, true, true, false, false, false, false, false, false, false, false, false, false, false, false };
	static bool isint[] = { true, true, false, false, false, false, false, false, false, false, false, false, false, false, false };
	static bool ishex[] = { true, true, false, false, true, false, true, false, true, false, false, false, false, true, false };
	static bool ishex_p[] = { false, false, false, false, false, false, false, true, false, false, false, false, false, false, false };
	static bool isflt[] = { true, true, true, false, true, true, false, false, false, false, false, false, false, true, true };
	static bool isaid[] = { false, false, false, false, false, false, false, false, true, true, false, false, false, false, false };
	static bool isuid[] = { false, false, false, false, false, false, false, false, true, true, false, false, true, false, false };
	for (unsigned int i = 0; i < std_size(data); i++) {
		String s = String::utf8(data[i]);
		CHECK(s.is_numeric() == isnum[i]);
		CHECK(s.is_valid_int() == isint[i]);
		CHECK(s.is_valid_hex_number(false) == ishex[i]);
		CHECK(s.is_valid_hex_number(true) == ishex_p[i]);
		CHECK(s.is_valid_float() == isflt[i]);
		CHECK(s.is_valid_ascii_identifier() == isaid[i]);
		CHECK(s.is_valid_unicode_identifier() == isuid[i]);
	}
}

TEST_CASE("[String] humanize_size") {
	CHECK(String::humanize_size(1000) == "1000 B");
	CHECK(String::humanize_size(1025) == "1.00 KiB");
	CHECK(String::humanize_size(1025300) == "1001.2 KiB");
	CHECK(String::humanize_size(100523550) == "95.86 MiB");
	CHECK(String::humanize_size(5345555000) == "4.97 GiB");
}

TEST_CASE("[String] validate_node_name") {
	String numeric_only = "12345";
	CHECK(numeric_only.validate_node_name() == "12345");

	String name_with_spaces = "Name with spaces";
	CHECK(name_with_spaces.validate_node_name() == "Name with spaces");

	String name_with_kana = U"Name with kana ゴドツ";
	CHECK(name_with_kana.validate_node_name() == U"Name with kana ゴドツ");

	String name_with_invalid_chars = "Name with invalid characters :.@%removed!";
	CHECK(name_with_invalid_chars.validate_node_name() == "Name with invalid characters ____removed!");
}

TEST_CASE("[String] validate_ascii_identifier") {
	String empty_string;
	CHECK(empty_string.validate_ascii_identifier() == "_");

	String numeric_only = "12345";
	CHECK(numeric_only.validate_ascii_identifier() == "_12345");

	String name_with_spaces = "Name with spaces";
	CHECK(name_with_spaces.validate_ascii_identifier() == "Name_with_spaces");

	String name_with_invalid_chars = U"Invalid characters:@*#&世界";
	CHECK(name_with_invalid_chars.validate_ascii_identifier() == "Invalid_characters_______");
}

TEST_CASE("[String] validate_unicode_identifier") {
	String empty_string;
	CHECK(empty_string.validate_unicode_identifier() == "_");

	String numeric_only = "12345";
	CHECK(numeric_only.validate_unicode_identifier() == "_12345");

	String name_with_spaces = "Name with spaces";
	CHECK(name_with_spaces.validate_unicode_identifier() == "Name_with_spaces");

	String name_with_invalid_chars = U"Invalid characters:@*#&世界";
	CHECK(name_with_invalid_chars.validate_unicode_identifier() == U"Invalid_characters_____世界");
}

TEST_CASE("[String] Variant indexed get") {
	Variant s = String("abcd");
	bool valid = false;
	bool oob = true;

	String r = s.get_indexed(1, valid, oob);

	CHECK(valid);
	CHECK_FALSE(oob);
	CHECK_EQ(r, String("b"));
}

TEST_CASE("[String] Variant validated indexed get") {
	Variant s = String("abcd");

	Variant::ValidatedIndexedGetter getter = Variant::get_member_validated_indexed_getter(Variant::STRING);

	Variant r;
	bool oob = true;
	getter(&s, 1, &r, &oob);

	CHECK_FALSE(oob);
	CHECK_EQ(r, String("b"));
}

TEST_CASE("[String] Variant ptr indexed get") {
	String s("abcd");

	Variant::PTRIndexedGetter getter = Variant::get_member_ptr_indexed_getter(Variant::STRING);

	String r;
	getter(&s, 1, &r);

	CHECK_EQ(r, String("b"));
}

TEST_CASE("[String] Variant indexed set") {
	Variant s = String("abcd");
	bool valid = false;
	bool oob = true;

	s.set_indexed(1, String("z"), valid, oob);

	CHECK(valid);
	CHECK_FALSE(oob);
	CHECK_EQ(s, String("azcd"));
}

TEST_CASE("[String] Variant validated indexed set") {
	Variant s = String("abcd");

	Variant::ValidatedIndexedSetter setter = Variant::get_member_validated_indexed_setter(Variant::STRING);

	Variant v = String("z");
	bool oob = true;
	setter(&s, 1, &v, &oob);

	CHECK_FALSE(oob);
	CHECK_EQ(s, String("azcd"));
}

TEST_CASE("[String] Variant ptr indexed set") {
	String s("abcd");

	Variant::PTRIndexedSetter setter = Variant::get_member_ptr_indexed_setter(Variant::STRING);

	String v("z");
	setter(&s, 1, &v);

	CHECK_EQ(s, String("azcd"));
}

TEST_CASE("[String][URL] Parse URL") {
#define CHECK_URL(m_url_to_parse, m_expected_schema, m_expected_host, m_expected_port, m_expected_path, m_expected_fragment, m_expected_error) \
	if (true) { \
		int port; \
		String url(m_url_to_parse), schema, host, path, fragment; \
\
		CHECK_EQ(url.parse_url(schema, host, port, path, fragment), m_expected_error); \
		CHECK_EQ(schema, m_expected_schema); \
		CHECK_EQ(host, m_expected_host); \
		CHECK_EQ(path, m_expected_path); \
		CHECK_EQ(fragment, m_expected_fragment); \
		CHECK_EQ(port, m_expected_port); \
	} else \
		((void)0)

	// All elements.
	CHECK_URL("https://www.example.com:8080/path/to/file.html#fragment", "https://", "www.example.com", 8080, "/path/to/file.html", "fragment", Error::OK);

	// Valid URLs.
	CHECK_URL("https://godotengine.org", "https://", "godotengine.org", 0, "", "", Error::OK);
	CHECK_URL("https://godotengine.org/", "https://", "godotengine.org", 0, "/", "", Error::OK);
	CHECK_URL("godotengine.org/", "", "godotengine.org", 0, "/", "", Error::OK);
	CHECK_URL("HTTPS://godotengine.org/", "https://", "godotengine.org", 0, "/", "", Error::OK);
	CHECK_URL("https://GODOTENGINE.ORG/", "https://", "godotengine.org", 0, "/", "", Error::OK);
	CHECK_URL("http://godotengine.org", "http://", "godotengine.org", 0, "", "", Error::OK);
	CHECK_URL("https://godotengine.org:8080", "https://", "godotengine.org", 8080, "", "", Error::OK);
	CHECK_URL("https://godotengine.org/blog", "https://", "godotengine.org", 0, "/blog", "", Error::OK);
	CHECK_URL("https://godotengine.org/blog/", "https://", "godotengine.org", 0, "/blog/", "", Error::OK);
	CHECK_URL("https://docs.godotengine.org/en/stable", "https://", "docs.godotengine.org", 0, "/en/stable", "", Error::OK);
	CHECK_URL("https://docs.godotengine.org/en/stable/", "https://", "docs.godotengine.org", 0, "/en/stable/", "", Error::OK);
	CHECK_URL("https://me:secret@godotengine.org", "https://", "godotengine.org", 0, "", "", Error::OK);
	CHECK_URL("https://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]/ipv6", "https://", "fedc:ba98:7654:3210:fedc:ba98:7654:3210", 0, "/ipv6", "", Error::OK);

	// Scheme vs Fragment.
	CHECK_URL("google.com/#goto=http://redirect_url/", "", "google.com", 0, "/", "goto=http://redirect_url/", Error::OK);

	// Invalid URLs.

	// Invalid Scheme.
	CHECK_URL("https_://godotengine.org", "", "https_", 0, "//godotengine.org", "", Error::ERR_INVALID_PARAMETER);

	// Multiple ports.
	CHECK_URL("https://godotengine.org:8080:433", "https://", "", 0, "", "", Error::ERR_INVALID_PARAMETER);
	// Missing ] on literal IPv6.
	CHECK_URL("https://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210/ipv6", "https://", "", 0, "/ipv6", "", Error::ERR_INVALID_PARAMETER);
	// Missing host.
	CHECK_URL("https:///blog", "https://", "", 0, "/blog", "", Error::ERR_INVALID_PARAMETER);
	// Invalid ports.
	CHECK_URL("https://godotengine.org:notaport", "https://", "godotengine.org", 0, "", "", Error::ERR_INVALID_PARAMETER);
	CHECK_URL("https://godotengine.org:-8080", "https://", "godotengine.org", -8080, "", "", Error::ERR_INVALID_PARAMETER);
	CHECK_URL("https://godotengine.org:88888", "https://", "godotengine.org", 88888, "", "", Error::ERR_INVALID_PARAMETER);

#undef CHECK_URL
}

static String get_with_code_lines_reference(const String &p_source) {
	const Vector<String> lines = p_source.split("\n");
	String result;
	for (int i = 0; i < lines.size(); i++) {
		if (i > 0) {
			result += "\n";
		}
		result += vformat("%4d | %s", i + 1, lines[i]);
	}
	return result;
}

TEST_CASE("[String] get_with_code_lines matches original formatting without per-line allocations") {
	const String samples[] = {
		String(),
		"one",
		"one\ntwo",
		"\n",
		"one\n",
		"\none",
		"one\n\ntwo\n",
		"one\r\ntwo",
		String::utf8("Привет\n🎮 Unicode"),
		String("x").repeat(1200),
	};
	for (const String &sample : samples) {
		CHECK(sample.get_with_code_lines() == get_with_code_lines_reference(sample));
	}

	// Above 9,999 lines, prefixes grow as needed. The legacy formatting
	// uses four spaces of minimum width, not one global widened column.
	const String large_source = String("x\n").repeat(10001);
	const String expected = get_with_code_lines_reference(large_source);
	const String actual = large_source.get_with_code_lines();
	CHECK(actual == expected);
	CHECK(actual.contains("10000 | x"));
	CHECK(actual.contains("10002 | "));
}

TEST_CASE("[String] strip_edges_span matches String::strip_edges for empty, Unicode, and whitespace") {
	const String inputs[] = {
		String(),
		" ",
		"  \t\r\n",
		" a ",
		" \tHello world\t ",
		String::utf8(" \tПривет 🌎 \t"),
		"\ttrailing\n",
		String("x").repeat(1000),
	};
	for (const String &value : inputs) {
		for (bool left : { false, true }) {
			for (bool right : { false, true }) {
				const Span<char32_t> span = String::strip_edges_span(value.span(), left, right);
				const String expected = value.strip_edges(left, right);
				CHECK(span == expected.span());
			}
		}
	}
}

TEST_CASE("[String] strip_edges_span trims a single trailing whitespace character") {
	const String lone = " ";
	CHECK(String::strip_edges_span(lone.span(), false, true).is_empty());
	CHECK(String::strip_edges_span(lone.span(), true, false).is_empty());
	const String spaces = " \t\n";
	CHECK(String::strip_edges_span(spaces.span(), false, true).is_empty());
	CHECK(String::strip_edges_span(spaces.span(), true, true).is_empty());
	const String leading = " text ";
	CHECK(String::strip_edges_span(leading.span(), false, true) == Span<char32_t>(U" text"));
	CHECK(String::strip_edges_span(leading.span(), true, false) == Span<char32_t>(U"text "));
	CHECK(String::strip_edges_span(leading.span(), true, true) == Span<char32_t>(U"text"));
}


TEST_CASE("[String] Quoted strings use zero-temporary fast path") {
	CHECK_FALSE(String().is_quoted());
	CHECK_FALSE(String("\"").is_quoted());
	CHECK_FALSE(String("'").is_quoted());
	CHECK(String("\"\"").is_quoted());
	CHECK(String("''").is_quoted());
	CHECK(String("\"hello\"").is_quoted());
	CHECK(String("'hello'").is_quoted());
	CHECK_FALSE(String("\"hello'").is_quoted());
	CHECK_FALSE(String("'hello\"").is_quoted());
	CHECK_FALSE(String("hello").is_quoted());
	CHECK(String("abba").is_enclosed_in("a"));
	CHECK(String("ababab").is_enclosed_in("ab"));
	CHECK(String("abba").is_enclosed_in(""));
	CHECK_FALSE(String("abax").is_enclosed_in("ab"));
	CHECK(String("abba").is_enclosed_in('a', 'a'));
	CHECK_FALSE(String("a").is_enclosed_in('a', 'a'));
}

TEST_CASE("[String] shared UTF32 buffer comparison fast paths") {
	const String original = String("AbC unicode \u00e9").repeat(256);
	String copy = original;
	CHECK(original == copy);
	CHECK_EQ(original.casecmp_to(copy), 0);
	CHECK_EQ(original.nocasecmp_to(copy), 0);
	CHECK_FALSE(original != copy);

	const String separate = String("AbC unicode \u00e9").repeat(256);
	CHECK(original == separate);
	CHECK_EQ(original.casecmp_to(separate), 0);
	CHECK_EQ(original.nocasecmp_to(separate), 0);

	copy += "!";
	CHECK_FALSE(original == copy);
	CHECK(original != copy);
	CHECK_EQ(original.casecmp_to(String("AbC unicode \u00e9").repeat(256)), 0);
	CHECK(String().nocasecmp_to(String()) == 0);
	CHECK(String().casecmp_to(String()) == 0);
}

TEST_CASE("[String] simplify_path linear parser matches legacy algorithm") {
	// Independent pre-optimization oracle: keep the legacy splitting and
	// repeated-collapse algorithm exclusively in this regression test.
	auto reference = [](const String &p_input) -> String {
		String s = p_input;
		String drive;
		int p = s.find("://");
		bool found = false;
		if (p > 0) {
			bool only_chars = true;
			for (int i = 0; i < p; i++) {
				if (!is_ascii_alphanumeric_char(s[i])) {
					only_chars = false;
					break;
				}
			}
			if (only_chars) {
				found = true;
				drive = s.substr(0, p + 3);
				s = s.substr(p + 3);
			}
		}
		if (!found) {
			if (p_input.is_network_share_path()) {
				drive = s.substr(0, 2);
				s = s.substr(2);
			} else if (s.begins_with("/") || s.begins_with("\\")) {
				drive = s.substr(0, 1);
				s = s.substr(1);
			} else {
				p = s.find(":/");
				if (p == -1) {
					p = s.find(":\\");
				}
				if (p != -1 && p < s.find_char('/')) {
					drive = s.substr(0, p + 2);
					s = s.substr(p + 2);
				}
			}
		}
		s = s.replace_char('\\', '/');
		while (true) {
			String compare = s.replace("//", "/");
			if (s == compare) {
				break;
			}
			s = compare;
		}
		Vector<String> dirs = s.split("/", false);
		bool absolute_path = p_input.is_absolute_path() && !p_input.begins_with("res://");
		for (int i = 0; i < dirs.size(); i++) {
			String d = dirs[i];
			if (d == ".") {
				dirs.remove_at(i);
				i--;
			} else if (d == "..") {
				if (i != 0 && dirs[i - 1] != "..") {
					dirs.remove_at(i);
					dirs.remove_at(i - 1);
					i -= 2;
				} else if (absolute_path && i == 0) {
					dirs.remove_at(i);
					i--;
				}
			}
		}
		s = "";
		for (int i = 0; i < dirs.size(); i++) {
			if (i > 0) {
				s += "/";
			}
			s += dirs[i];
		}
		return drive + s;
	};

	static const char *inputs[] = {
		"", ".", "..", "a/b/../../..", "../a/../b",
		"res://../../texture.png", "res://a//b", "res://a/../..",
		"/../a", "/a/../../b", "//server/share/a",
		"C:/../b", "C:\\a\\..\\b", "http://example.com/../p",
		"foo\\bar/../baz", "a////b/./c", "a/../..",
	};
	for (const char *input : inputs) {
		CHECK_EQ(String(input).simplify_path(), reference(input));
	}
	static const char *pieces[] = { "a", "b", ".", "..", "...", "/", "\\", "//", "C:", "res:", "http:" };
	uint32_t state = 0x3792ABCDu;
	auto next_random = [&state]() {
		state ^= state << 13;
		state ^= state >> 17;
		state ^= state << 5;
		return state;
	};
	for (int trial = 0; trial < 1500; trial++) {
		String path;
		const int count = next_random() % 25;
		for (int i = 0; i < count; i++) {
			path += pieces[next_random() % 11];
		}
		CHECK_EQ(path.simplify_path(), reference(path));
	}
	String deep = "res://";
	for (int i = 0; i < 256; i++) {
		deep += "directory/./sub/../";
	}
	deep += "texture.png";
	CHECK_EQ(deep.simplify_path(), reference(deep));
}

} // namespace TestString
