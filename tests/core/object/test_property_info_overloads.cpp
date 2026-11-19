/**************************************************************************/
/*  test_property_info_overloads.cpp                                      */
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

TEST_FORCE_LINK(test_property_info_overloads)

#include "core/object/class_db.h"
#include "core/object/property_info.h"

namespace TestPropertyInfoOverloads {

TEST_CASE("[PropertyInfoOverloads] Simple literal matches String constructor") {
	const PropertyInfo literal(Variant::INT, "speed");
	const PropertyInfo owned(Variant::INT, String("speed"));
	CHECK(literal == owned);
	CHECK(literal.type == Variant::INT);
	CHECK(literal.name == "speed");
	CHECK(literal.hint == PROPERTY_HINT_NONE);
	CHECK(literal.hint_string.is_empty());
	CHECK(literal.class_name.is_empty());
	CHECK(literal.usage == PROPERTY_USAGE_DEFAULT);
}

TEST_CASE("[PropertyInfoOverloads] Literal range and usage preserve semantics") {
	const PropertyInfo literal(Variant::FLOAT, "volume", PROPERTY_HINT_RANGE, "0,1,0.01", PROPERTY_USAGE_STORAGE, "Node");
	const PropertyInfo owned(Variant::FLOAT, String("volume"), PROPERTY_HINT_RANGE, String("0,1,0.01"), PROPERTY_USAGE_STORAGE, StringName("Node"));
	CHECK(literal == owned);
	CHECK(literal.name == "volume");
	CHECK(literal.hint == PROPERTY_HINT_RANGE);
	CHECK(literal.hint_string == "0,1,0.01");
	CHECK(literal.class_name == StringName("Node"));
	CHECK(literal.usage == PROPERTY_USAGE_STORAGE);
}

TEST_CASE("[PropertyInfoOverloads] Resource type overrides class name") {
	const PropertyInfo literal(Variant::OBJECT, "texture", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D", PROPERTY_USAGE_DEFAULT, "Node");
	const PropertyInfo owned(Variant::OBJECT, String("texture"), PROPERTY_HINT_RESOURCE_TYPE, String("Texture2D"), PROPERTY_USAGE_DEFAULT, StringName("Node"));
	CHECK(literal == owned);
	CHECK(literal.class_name == StringName("Texture2D"));
	CHECK(literal.hint_string == "Texture2D");
	CHECK(literal.name == "texture");
}

TEST_CASE("[PropertyInfoOverloads] Null class literal remains empty") {
	const PropertyInfo literal(Variant::OBJECT, "parent", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT, nullptr);
	const PropertyInfo owned(Variant::OBJECT, String("parent"), PROPERTY_HINT_NONE, String(), PROPERTY_USAGE_DEFAULT, StringName());
	CHECK(literal == owned);
	CHECK(literal.class_name.is_empty());
	CHECK(literal.hint_string.is_empty());
}

TEST_CASE("[PropertyInfoOverloads] Empty literal values retain defaults") {
	const PropertyInfo literal(Variant::STRING, "", PROPERTY_HINT_NONE, "");
	const PropertyInfo owned(Variant::STRING, String(), PROPERTY_HINT_NONE, String());
	CHECK(literal == owned);
	CHECK(literal.name.is_empty());
	CHECK(literal.hint_string.is_empty());
	CHECK(literal.class_name.is_empty());
}

TEST_CASE("[PropertyInfoOverloads] Const char pointer and StringName overloads both exist") {
	using LiteralPropertyAdder = void (*)(const StringName &, const PropertyInfo &, const char *, const char *, int);
	using InternedPropertyAdder = void (*)(const StringName &, const PropertyInfo &, const StringName &, const StringName &, int);
	const LiteralPropertyAdder literal = static_cast<LiteralPropertyAdder>(&ClassDB::add_property);
	const InternedPropertyAdder interned = static_cast<InternedPropertyAdder>(&ClassDB::add_property);
	CHECK(literal != nullptr);
	CHECK(interned != nullptr);
}

} // namespace TestPropertyInfoOverloads
