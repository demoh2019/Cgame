/**************************************************************************/
/*  test_json.cpp                                                         */
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

TEST_FORCE_LINK(test_json)

#include "core/io/json.h"
#include "core/variant/typed_array.h"

#include <cfloat> // DBL_MAX

namespace TestJSON {

TEST_CASE("[JSON] Stringify single data types") {
	CHECK(JSON::stringify(Variant()) == "null");
	CHECK(JSON::stringify(false) == "false");
	CHECK(JSON::stringify(true) == "true");
	CHECK(JSON::stringify(0) == "0");
	CHECK(JSON::stringify(12345) == "12345");
	CHECK(JSON::stringify(0.75) == "0.75");
	CHECK(JSON::stringify("test") == "\"test\"");
	CHECK(JSON::stringify("\\\b\f\n\r\t\v\"") == "\"\\\\\\b\\f\\n\\r\\t\\v\\\"\"");
}

TEST_CASE("[JSON] Stringify arrays") {
	CHECK(JSON::stringify(Array()) == "[]");

	Array int_array;
	for (int i = 0; i < 10; i++) {
		int_array.push_back(i);
	}
	CHECK(JSON::stringify(int_array) == "[0,1,2,3,4,5,6,7,8,9]");

	Array str_array;
	str_array.push_back("Hello");
	str_array.push_back("World");
	str_array.push_back("!");
	CHECK(JSON::stringify(str_array) == "[\"Hello\",\"World\",\"!\"]");

	Array indented_array;
	Array nested_array;
	for (int i = 0; i < 5; i++) {
		indented_array.push_back(i);
		nested_array.push_back(i);
	}
	indented_array.push_back(nested_array);
	CHECK(JSON::stringify(indented_array, "\t") == "[\n\t0,\n\t1,\n\t2,\n\t3,\n\t4,\n\t[\n\t\t0,\n\t\t1,\n\t\t2,\n\t\t3,\n\t\t4\n\t]\n]");

	Array full_precision_array;
	full_precision_array.push_back(0.12345678901234568);
	CHECK(JSON::stringify(full_precision_array, "", true, true) == "[0.12345678901234568]");

	Array non_finite_array;
	non_finite_array.push_back(Math::INF);
	non_finite_array.push_back(-Math::INF);
	non_finite_array.push_back(Math::NaN);
	ERR_PRINT_OFF
	CHECK(JSON::stringify(non_finite_array) == "[1e99999,-1e99999,null]");

	Array non_finite_round_trip = JSON::parse_string(JSON::stringify(non_finite_array));
	CHECK(non_finite_round_trip[0] == Variant(Math::INF));
	CHECK(non_finite_round_trip[1] == Variant(-Math::INF));
	CHECK(non_finite_round_trip[2].get_type() == Variant::NIL);

	Array self_array;
	self_array.push_back(self_array);
	CHECK(JSON::stringify(self_array) == "[\"[...]\"]");
	self_array.clear();

	Array max_recursion_array;
	for (int i = 0; i < Variant::MAX_RECURSION_DEPTH + 1; i++) {
		Array next;
		next.push_back(max_recursion_array);
		max_recursion_array = next;
	}
	CHECK(JSON::stringify(max_recursion_array).contains("[...]"));
	ERR_PRINT_ON
}

TEST_CASE("[JSON] Stringify dictionaries") {
	CHECK(JSON::stringify(Dictionary()) == "{}");

	Dictionary single_entry;
	single_entry["key"] = "value";
	CHECK(JSON::stringify(single_entry) == "{\"key\":\"value\"}");

	Dictionary indented;
	indented["key1"] = "value1";
	indented["key2"] = 2;
	CHECK(JSON::stringify(indented, "\t") == "{\n\t\"key1\": \"value1\",\n\t\"key2\": 2\n}");

	Dictionary outer;
	Dictionary inner;
	inner["key"] = "value";
	outer["inner"] = inner;
	CHECK(JSON::stringify(outer) == "{\"inner\":{\"key\":\"value\"}}");

	Dictionary full_precision_dictionary;
	full_precision_dictionary["key"] = 0.12345678901234568;
	CHECK(JSON::stringify(full_precision_dictionary, "", true, true) == "{\"key\":0.12345678901234568}");

	Dictionary non_finite_dictionary;
	non_finite_dictionary["-inf"] = -Math::INF;
	non_finite_dictionary["inf"] = Math::INF;
	non_finite_dictionary["nan"] = Math::NaN;
	ERR_PRINT_OFF
	CHECK(JSON::stringify(non_finite_dictionary) == "{\"-inf\":-1e99999,\"inf\":1e99999,\"nan\":null}");

	Dictionary non_finite_round_trip = JSON::parse_string(JSON::stringify(non_finite_dictionary));
	CHECK(non_finite_round_trip["-inf"] == Variant(-Math::INF));
	CHECK(non_finite_round_trip["inf"] == Variant(Math::INF));
	CHECK(non_finite_round_trip["nan"].get_type() == Variant::NIL);

	Dictionary self_dictionary;
	self_dictionary["key"] = self_dictionary;
	CHECK(JSON::stringify(self_dictionary) == "{\"key\":\"{...}\"}");
	self_dictionary.clear();

	Dictionary max_recursion_dictionary;
	for (int i = 0; i < Variant::MAX_RECURSION_DEPTH + 1; i++) {
		Dictionary next;
		next["key"] = max_recursion_dictionary;
		max_recursion_dictionary = next;
	}
	CHECK(JSON::stringify(max_recursion_dictionary).contains("{...:...}"));
	ERR_PRINT_ON
}

// NOTE: The current JSON parser accepts many non-conformant strings such as
// single-quoted strings, duplicate commas and trailing commas.
// This is intentionally not tested as users shouldn't rely on this behavior.

TEST_CASE("[JSON] Parsing single data types") {
	// Parsing a single data type as JSON is valid per the JSON specification.

	JSON json;

	json.parse("null");
	CHECK_MESSAGE(
			json.get_error_line() == 0,
			"Parsing `null` as JSON should parse successfully.");
	CHECK_MESSAGE(
			json.get_data() == Variant(),
			"Parsing a double quoted string as JSON should return the expected value.");

	json.parse("true");
	CHECK_MESSAGE(
			json.get_error_line() == 0,
			"Parsing boolean `true` as JSON should parse successfully.");
	CHECK_MESSAGE(
			json.get_data(),
			"Parsing boolean `true` as JSON should return the expected value.");

	json.parse("false");
	CHECK_MESSAGE(
			json.get_error_line() == 0,
			"Parsing boolean `false` as JSON should parse successfully.");
	CHECK_MESSAGE(
			!json.get_data(),
			"Parsing boolean `false` as JSON should return the expected value.");

	json.parse("123456");
	CHECK_MESSAGE(
			json.get_error_line() == 0,
			"Parsing an integer number as JSON should parse successfully.");
	CHECK_MESSAGE(
			(int)(json.get_data()) == 123456,
			"Parsing an integer number as JSON should return the expected value.");

	json.parse("0.123456");
	CHECK_MESSAGE(
			json.get_error_line() == 0,
			"Parsing a floating-point number as JSON should parse successfully.");
	CHECK_MESSAGE(
			double(json.get_data()) == doctest::Approx(0.123456),
			"Parsing a floating-point number as JSON should return the expected value.");

	json.parse("\"hello\"");
	CHECK_MESSAGE(
			json.get_error_line() == 0,
			"Parsing a double quoted string as JSON should parse successfully.");
	CHECK_MESSAGE(
			json.get_data() == "hello",
			"Parsing a double quoted string as JSON should return the expected value.");
}

TEST_CASE("[JSON] Parsing arrays") {
	JSON json;

	// JSON parsing fails if it's split over several lines (even if leading indentation is removed).
	json.parse(R"(["Hello", "world.", "This is",["a","json","array.",[]], "Empty arrays ahoy:", [[["Gotcha!"]]]])");

	const Array array = json.get_data();
	CHECK_MESSAGE(
			json.get_error_line() == 0,
			"Parsing a JSON array should parse successfully.");
	CHECK_MESSAGE(
			array[0] == "Hello",
			"The parsed JSON should contain the expected values.");
	const Array sub_array = array[3];
	CHECK_MESSAGE(
			sub_array.size() == 4,
			"The parsed JSON should contain the expected values.");
	CHECK_MESSAGE(
			sub_array[1] == "json",
			"The parsed JSON should contain the expected values.");
	CHECK_MESSAGE(
			sub_array[3].hash() == Array().hash(),
			"The parsed JSON should contain the expected values.");
	const Array deep_array = Array(Array(array[5])[0])[0];
	CHECK_MESSAGE(
			deep_array[0] == "Gotcha!",
			"The parsed JSON should contain the expected values.");
}

TEST_CASE("[JSON] Parsing objects (dictionaries)") {
	JSON json;

	json.parse(R"({"name": "Godot Engine", "is_free": true, "bugs": null, "apples": {"red": 500, "green": 0, "blue": -20}, "empty_object": {}})");

	const Dictionary dictionary = json.get_data();
	CHECK_MESSAGE(
			dictionary["name"] == "Godot Engine",
			"The parsed JSON should contain the expected values.");
	CHECK_MESSAGE(
			dictionary["is_free"],
			"The parsed JSON should contain the expected values.");
	CHECK_MESSAGE(
			dictionary["bugs"] == Variant(),
			"The parsed JSON should contain the expected values.");
	CHECK_MESSAGE(
			(int)Dictionary(dictionary["apples"])["blue"] == -20,
			"The parsed JSON should contain the expected values.");
	CHECK_MESSAGE(
			dictionary["empty_object"].hash() == Dictionary().hash(),
			"The parsed JSON should contain the expected values.");
}

TEST_CASE("[JSON] Parsing escape sequences") {
	// Only certain escape sequences are valid according to the JSON specification.
	// Others must result in a parsing error instead.

	JSON json;

	TypedArray<String> valid_escapes = { "\";\"", "\\;\\", "/;/", "b;\b", "f;\f", "n;\n", "r;\r", "t;\t" };

	SUBCASE("Basic valid escape sequences") {
		for (int i = 0; i < valid_escapes.size(); i++) {
			String valid_escape = valid_escapes[i];
			String valid_escape_string = valid_escape.get_slicec(';', 0);
			String valid_escape_value = valid_escape.get_slicec(';', 1);

			String json_string = "\"\\";
			json_string += valid_escape_string;
			json_string += "\"";
			json.parse(json_string);

			CHECK_MESSAGE(
					json.get_error_line() == 0,
					vformat("Parsing valid escape sequence `%s` as JSON should parse successfully.", valid_escape_string));

			String json_value = json.get_data();
			CHECK_MESSAGE(
					json_value == valid_escape_value,
					vformat("Parsing valid escape sequence `%s` as JSON should return the expected value.", valid_escape_string));
		}
	}

	SUBCASE("Valid unicode escape sequences") {
		String json_string = "\"\\u0020\"";
		json.parse(json_string);

		CHECK_MESSAGE(
				json.get_error_line() == 0,
				vformat("Parsing valid unicode escape sequence with value `0020` as JSON should parse successfully."));

		String json_value = json.get_data();
		CHECK_MESSAGE(
				json_value == " ",
				vformat("Parsing valid unicode escape sequence with value `0020` as JSON should return the expected value."));
	}

	SUBCASE("Invalid escape sequences") {
		ERR_PRINT_OFF
		for (char32_t i = 0; i < 128; i++) {
			bool skip = false;
			for (int j = 0; j < valid_escapes.size(); j++) {
				String valid_escape = valid_escapes[j];
				String valid_escape_string = valid_escape.get_slicec(';', 0);
				if (valid_escape_string[0] == i) {
					skip = true;
					break;
				}
			}

			if (skip) {
				continue;
			}

			String json_string = "\"\\";
			json_string += i;
			json_string += "\"";
			Error err = json.parse(json_string);

			// TODO: Line number is currently kept on 0, despite an error occurring. This should be fixed in the JSON parser.
			// CHECK_MESSAGE(
			// 		json.get_error_line() != 0,
			// 		vformat("Parsing invalid escape sequence with ASCII value `%d` as JSON should fail to parse.", i));
			CHECK_MESSAGE(
					err == ERR_PARSE_ERROR,
					vformat("Parsing invalid escape sequence with ASCII value `%d` as JSON should fail to parse with ERR_PARSE_ERROR.", i));
		}
		ERR_PRINT_ON
	}
}

TEST_CASE("[JSON] Serialization") {
	JSON json;

	struct FpTestCase {
		double number;
		String json;
	};

	struct IntTestCase {
		int64_t number;
		String json;
	};

	struct UIntTestCase {
		uint64_t number;
		String json;
	};

	static FpTestCase fp_tests_default_precision[] = {
		{ 0.0, "0.0" },
		{ 1000.1234567890123456789, "1000.12345678901" },
		{ -1000.1234567890123456789, "-1000.12345678901" },
		{ DBL_MAX, "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368.0" },
		{ DBL_MAX - 1, "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368.0" },
		{ std::pow(2, 53), "9007199254740992.0" },
		{ -std::pow(2, 53), "-9007199254740992.0" },
		{ 0.00000000000000011, "0.00000000000000011" },
		{ -0.00000000000000011, "-0.00000000000000011" },
		{ 1.0 / 3.0, "0.333333333333333" },
		{ 0.9999999999999999, "1.0" },
		{ 1.0000000000000001, "1.0" },
	};

	static FpTestCase fp_tests_full_precision[] = {
		{ 0.0, "0.0" },
		{ 1000.1234567890123456789, "1000.1234567890124" },
		{ -1000.1234567890123456789, "-1000.1234567890124" },
		{ DBL_MAX, "1.7976931348623157e+308" },
		{ DBL_MAX - 1, "1.7976931348623157e+308" },
		{ std::pow(2, 53), "9.007199254740992e+15" },
		{ -std::pow(2, 53), "-9.007199254740992e+15" },
		{ 0.00000000000000011, "1.1e-16" },
		{ -0.00000000000000011, "-1.1e-16" },
		{ 1.0 / 3.0, "0.3333333333333333" },
		{ 0.9999999999999999, "0.9999999999999999" },
		{ 1.0000000000000001, "1.0" },
	};

	static IntTestCase int_tests[] = {
		{ 0, "0" },
		{ INT64_MAX, "9223372036854775807" },
		{ INT64_MIN, "-9223372036854775808" },
	};

	SUBCASE("Floating point default precision") {
		for (FpTestCase &test : fp_tests_default_precision) {
			String json_value = json.stringify(test.number, "", true, false);

			CHECK_MESSAGE(
					json_value == test.json,
					vformat("Serializing `%.20d` to JSON should return the expected value.", test.number));
		}
	}

	SUBCASE("Floating point full precision") {
		for (FpTestCase &test : fp_tests_full_precision) {
			String json_value = json.stringify(test.number, "", true, true);

			CHECK_MESSAGE(
					json_value == test.json,
					vformat("Serializing `%20f` to JSON should return the expected value.", test.number));
		}
	}

	SUBCASE("Signed integer") {
		for (IntTestCase &test : int_tests) {
			String json_value = json.stringify(test.number, "", true, true);

			CHECK_MESSAGE(
					json_value == test.json,
					vformat("Serializing `%d` to JSON should return the expected value.", test.number));
		}
	}
}

TEST_CASE("[JSON] Native serialization preserves large packed arrays and dictionaries") {
	PackedByteArray bytes;
	PackedInt32Array ints;
	PackedInt64Array big_ints;
	PackedFloat32Array floats;
	PackedFloat64Array doubles;
	PackedStringArray strings;
	PackedVector2Array vector2s;
	PackedVector3Array vector3s;
	PackedVector4Array vector4s;
	PackedColorArray colors;
	for (int i = 0; i < 256; i++) {
		bytes.push_back(uint8_t(i % 251));
		ints.push_back(i * 7 - 83);
		big_ints.push_back(int64_t(i) * 10000000 - 1500);
		floats.push_back(i * 0.25f);
		doubles.push_back(double(i) * 0.125);
		strings.push_back(String("item_") + itos(i));
		vector2s.push_back(Vector2(i, -i));
		vector3s.push_back(Vector3(i, i * 2, -i));
		vector4s.push_back(Vector4(i, i + 1, -i, 2));
		colors.push_back(Color(i / 256.0f, 0.25f, 0.5f, 1.0f));
	}

	Array packed_inputs;
	packed_inputs.push_back(bytes);
	packed_inputs.push_back(ints);
	packed_inputs.push_back(big_ints);
	packed_inputs.push_back(floats);
	packed_inputs.push_back(doubles);
	packed_inputs.push_back(strings);
	packed_inputs.push_back(vector2s);
	packed_inputs.push_back(vector3s);
	packed_inputs.push_back(vector4s);
	packed_inputs.push_back(colors);

	for (int i = 0; i < packed_inputs.size(); i++) {
		const Variant source = packed_inputs[i];
		const Variant encoded = JSON::from_native(source);
		const Variant decoded = JSON::to_native(encoded);
		CHECK_EQ(decoded.get_type(), source.get_type());
		CHECK_EQ(decoded, source);
	}

	Dictionary source_dictionary;
	Array nested_array;
	for (int i = 0; i < 256; i++) {
		source_dictionary[itos(i)] = i * 13;
		nested_array.push_back(i * 5);
	}
	source_dictionary["nested"] = nested_array;
	const Variant encoded_dictionary = JSON::from_native(source_dictionary);
	const Variant decoded_dictionary = JSON::to_native(encoded_dictionary);
	REQUIRE_EQ(decoded_dictionary.get_type(), Variant::DICTIONARY);
	const Dictionary result = decoded_dictionary;
	REQUIRE_EQ(result.size(), source_dictionary.size());
	for (int i = 0; i < 256; i++) {
		CHECK_EQ(result[itos(i)], Variant(i * 13));
	}
	const Array decoded_array = result["nested"];
	REQUIRE_EQ(decoded_array.size(), 256);
	for (int i = 0; i < 256; i++) {
		CHECK_EQ(decoded_array[i], Variant(i * 5));
	}
}


TEST_CASE("[JSON] StringBuilder serialization preserves large arrays and nested dictionaries") {
	Array values;
	for (int i = 0; i < 1024; i++) {
		Dictionary entry;
		entry["index"] = i;
		entry["enabled"] = (i % 2) == 0;
		entry["name"] = String("item_") + itos(i);
		values.push_back(entry);
	}
	const String compact = JSON::stringify(values);
	CHECK(compact.begins_with("[{"));
	CHECK(compact.ends_with("}]"));
	const Variant decoded = JSON::parse_string(compact);
	REQUIRE(decoded.get_type() == Variant::ARRAY);
	const Array result = decoded;
	REQUIRE(result.size() == values.size());
	for (int i = 0; i < result.size(); i++) {
		const Dictionary item = result[i];
		CHECK(item["index"] == Variant(i));
		CHECK(item["enabled"] == Variant((i % 2) == 0));
		CHECK(item["name"] == Variant(String("item_") + itos(i)));
	}
}

TEST_CASE("[JSON] StringBuilder serialization keeps exact pretty-print formatting") {
	Array inner_array;
	inner_array.push_back(1);
	inner_array.push_back(2);
	Dictionary inner;
	inner["numbers"] = inner_array;
	Dictionary outer;
	outer["y"] = inner;
	outer["a"] = true;
	const String result = JSON::stringify(outer, "--");
	CHECK(result == "{\n--\"a\": true,\n--\"y\": {\n----\"numbers\": [\n------1,\n------2\n----]\n--}\n}");
	const Variant parsed = JSON::parse_string(result);
	CHECK(parsed.get_type() == Variant::DICTIONARY);
	CHECK(JSON::stringify(parsed, "--") == result);
}

TEST_CASE("[JSON] StringBuilder serialization preserves escaping and key sorting") {
	Dictionary source;
	source["z"] = String("backslash\\ quote\" newline\n tab\t");
	source["a"] = String("first");
	source["nested"] = Array();
	const String compact = JSON::stringify(source);
	CHECK(compact.begins_with("{\"a\":\"first\""));
	const Dictionary roundtrip = JSON::parse_string(compact);
	CHECK(roundtrip["a"] == source["a"]);
	CHECK(roundtrip["z"] == source["z"]);
	CHECK(roundtrip["nested"] == source["nested"]);
	CHECK(JSON::stringify(source, "\t", true) == JSON::stringify(roundtrip, "\t", true));
}

TEST_CASE("[JSON] UTF32 batch parser accepts long plain string values and keys") {
	const String long_string = String("abcdefgh0123456789").repeat(4096);
	const String text = "{\"long_key_" + String("x").repeat(4096) + "\":\"" + long_string + "\"}";
	const Variant parsed = JSON::parse_string(text);
	REQUIRE(parsed.get_type() == Variant::DICTIONARY);
	const Dictionary result = parsed;
	REQUIRE(result.size() == 1);
	CHECK(result["long_key_" + String("x").repeat(4096)] == Variant(long_string));
	CHECK(JSON::parse_string(JSON::stringify(result)) == parsed);
}

TEST_CASE("[JSON] UTF32 batch parser keeps escape boundaries and UTF16 pairs") {
	const String left = String("qwerty").repeat(2048);
	const String right = String("abc123").repeat(2048);
	const String source = "\"" + left + "\\t" + right + "\\u0041" + "\"";
	const Variant parsed = JSON::parse_string(source);
	REQUIRE(parsed.get_type() == Variant::STRING);
	CHECK(parsed == Variant(left + "\t" + right + "A"));

	const String unicode_source = "\"start\\uD83D\\uDE00end\"";
	const Variant unicode = JSON::parse_string(unicode_source);
	REQUIRE(unicode.get_type() == Variant::STRING);
	const String unicode_text = unicode;
	CHECK(unicode_text.length() == 9);
	CHECK(unicode_text[5] == char32_t(0x1F600));
	CHECK(unicode_text.substr(6) == "end");
}

TEST_CASE("[JSON] UTF32 batch parser keeps invalid escapes and identifiers rejected") {
	JSON json;
	CHECK(json.parse("\"abc\\xdef\"") == ERR_PARSE_ERROR);
	CHECK(json.parse("\"unterminated\\") == ERR_PARSE_ERROR);
	CHECK(json.parse(String("invalididentifier").repeat(512)) == ERR_PARSE_ERROR);
	CHECK(json.parse("true") == OK);
	CHECK(json.get_data() == Variant(true));
	CHECK(json.parse("false") == OK);
	CHECK(json.get_data() == Variant(false));
	CHECK(json.parse("null") == OK);
	CHECK(json.get_data().get_type() == Variant::NIL);
}


TEST_CASE("[JSON] Dictionary serialization preserves sorted and insertion key order") {
	Dictionary input;
	input["z"] = 3;
	input["a"] = 1;
	input["m"] = 2;

	CHECK_EQ(JSON::stringify(input, "", false), "{\"z\":3,\"a\":1,\"m\":2}");
	CHECK_EQ(JSON::stringify(input, "", true), "{\"a\":1,\"m\":2,\"z\":3}");
	CHECK_EQ(JSON::stringify(input, "  ", false), "{\n  \"z\": 3,\n  \"a\": 1,\n  \"m\": 2\n}");
	CHECK_EQ(JSON::stringify(input, "  ", true), "{\n  \"a\": 1,\n  \"m\": 2,\n  \"z\": 3\n}");

	Dictionary nested;
	nested["contents"] = input;
	nested["unicode"] = String(U"Путь/雪/🚀");
	for (bool sorted : { false, true }) {
		const Dictionary decoded = JSON::parse_string(JSON::stringify(nested, "", sorted));
		CHECK_EQ(decoded["unicode"], Variant(String(U"Путь/雪/🚀")));
		const Dictionary contents = decoded["contents"];
		CHECK_EQ(contents["z"], Variant(3));
		CHECK_EQ(contents["a"], Variant(1));
		CHECK_EQ(contents["m"], Variant(2));
	}
}

TEST_CASE("[JSON] Large dictionary serializes without missing or reordered values") {
	Dictionary entries;
	for (int i = 1535; i >= 0; i--) {
		entries[String("res://entry_") + itos(i)] = i * 13 - 17;
	}

	for (bool sorted : { false, true }) {
		const String json = JSON::stringify(entries, "", sorted);
		CHECK_FALSE(json.is_empty());
		const Dictionary decoded = JSON::parse_string(json);
		REQUIRE_EQ(decoded.size(), entries.size());
		for (int i = 0; i < 1536; i += 13) {
			CHECK_EQ(decoded[String("res://entry_") + itos(i)], Variant(i * 13 - 17));
		}
	}

	const String compact = JSON::stringify(entries, "", false);
	const int first = compact.find("\"res://entry_1535\"");
	const int second = compact.find("\"res://entry_1534\"");
	CHECK(first >= 0);
	CHECK(second > first);
}


TEST_CASE("[JSON] Native Array and Dictionary Variants retain contents across serialization") {
	Array nested;
	nested.push_back(2);
	nested.push_back(3);
	Dictionary object;
	object["ok"] = true;
	Array source;
	source.push_back(1);
	source.push_back(String(U"雪"));
	source.push_back(nested);
	source.push_back(object);

	const Variant root(source);
	for (int i = 0; i < 128; i++) {
		CHECK_EQ(JSON::stringify(root), "[1,\"雪\",[2,3],{\"ok\":true}]");
		CHECK_EQ(source.size(), 4);
		CHECK_EQ(nested.size(), 2);
		CHECK_EQ(object["ok"], Variant(true));
	}
}

TEST_CASE("[JSON] Packed arrays still use the converted Array representation") {
	PackedInt32Array ints;
	ints.push_back(-1);
	ints.push_back(0);
	ints.push_back(32768);
	CHECK_EQ(JSON::stringify(Variant(ints)), "[-1,0,32768]");

	PackedStringArray labels;
	labels.push_back(String(U"雪"));
	labels.push_back(String(U"🚀"));
	CHECK_EQ(JSON::stringify(Variant(labels)), "[\"雪\",\"🚀\"]");

	PackedFloat64Array numbers;
	numbers.push_back(0.5);
	numbers.push_back(-1.25);
	const Array decoded = JSON::parse_string(JSON::stringify(Variant(numbers)));
	REQUIRE_EQ(decoded.size(), 2);
	CHECK_EQ(decoded[0], Variant(0.5));
	CHECK_EQ(decoded[1], Variant(-1.25));
}

TEST_CASE("[JSON] Deep nested native arrays stringify repeatedly without corruption") {
	Array root;
	for (int i = 0; i < 32; i++) {
		Array outer;
		for (int j = 0; j < 32; j++) {
			outer.push_back(i * 32 + j);
		}
		root.push_back(outer);
	}
	const Variant root_variant(root);
	for (int run = 0; run < 16; run++) {
		const Array decoded = JSON::parse_string(JSON::stringify(root_variant));
		REQUIRE_EQ(decoded.size(), 32);
		for (int i = 0; i < 32; i++) {
			const Array values = decoded[i];
			REQUIRE_EQ(values.size(), 32);
			CHECK_EQ(values[0], Variant(i * 32));
			CHECK_EQ(values[31], Variant(i * 32 + 31));
		}
	}
}

template <typename T>
static void check_packed_array_json_equivalent(const T &p_values) {
	// Previous stringify behavior converted every packed element to a Variant
	// by constructing a full Array. Keep that conversion as the test oracle.
	const Variant packed(p_values);
	const Array reference = packed;
	CHECK_EQ(JSON::stringify(packed), JSON::stringify(reference));
	CHECK_EQ(JSON::stringify(packed, "\t", false, true), JSON::stringify(reference, "\t", false, true));
}

TEST_CASE("[JSON] Packed arrays stream with the same formatting as an Array") {
	PackedInt32Array int32_values;
	PackedInt64Array int64_values;
	PackedFloat32Array float32_values;
	PackedFloat64Array float64_values;
	PackedStringArray string_values;

	check_packed_array_json_equivalent(int32_values);
	check_packed_array_json_equivalent(int64_values);
	check_packed_array_json_equivalent(float32_values);
	check_packed_array_json_equivalent(float64_values);
	check_packed_array_json_equivalent(string_values);

	for (int i = 0; i < 1024; i++) {
		int32_values.push_back((i % 2 == 0 ? 1 : -1) * i);
		int64_values.push_back((int64_t(1) << 42) + i);
		float32_values.push_back((i % 7) * 0.5f);
		float64_values.push_back((i % 9) * -0.125);
		string_values.push_back(String(U"ресурс/雪/") + itos(i));
	}
	check_packed_array_json_equivalent(int32_values);
	check_packed_array_json_equivalent(int64_values);
	check_packed_array_json_equivalent(float32_values);
	check_packed_array_json_equivalent(float64_values);
	check_packed_array_json_equivalent(string_values);

	const Array parsed = JSON::parse_string(JSON::stringify(Variant(int32_values)));
	REQUIRE_EQ(parsed.size(), int32_values.size());
	CHECK_EQ(parsed[0], Variant(0));
	CHECK_EQ(parsed[1], Variant(-1));
	CHECK_EQ(parsed[1023], Variant(-1023));
}

TEST_CASE("[JSON] Large packed primitive arrays do not lose elements or ordering") {
	PackedInt32Array values;
	REQUIRE_EQ(values.resize(16384), OK);
	int32_t *ptr = values.ptrw();
	for (int i = 0; i < values.size(); i++) {
		ptr[i] = i * 7 - 1234;
	}
	const String encoded = JSON::stringify(Variant(values));
	const Array decoded = JSON::parse_string(encoded);
	REQUIRE_EQ(decoded.size(), values.size());
	for (int i = 0; i < values.size(); i += 113) {
		CHECK_EQ(decoded[i], Variant(i * 7 - 1234));
	}
}

} // namespace TestJSON
