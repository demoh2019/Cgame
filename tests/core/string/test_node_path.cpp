/**************************************************************************/
/*  test_node_path.cpp                                                    */
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

TEST_FORCE_LINK(test_node_path)

#include "core/string/node_path.h"

namespace TestNodePath {

TEST_CASE("[NodePath] Relative path") {
	const NodePath node_path_relative = NodePath("Path2D/PathFollow2D/Sprite2D:position:x");

	CHECK_MESSAGE(
			node_path_relative.get_as_property_path() == NodePath(":Path2D/PathFollow2D/Sprite2D:position:x"),
			"The returned property path should match the expected value.");
	CHECK_MESSAGE(
			node_path_relative.get_concatenated_subnames() == "position:x",
			"The returned concatenated subnames should match the expected value.");

	CHECK_MESSAGE(
			node_path_relative.get_name(0) == "Path2D",
			"The returned name at index 0 should match the expected value.");
	CHECK_MESSAGE(
			node_path_relative.get_name(1) == "PathFollow2D",
			"The returned name at index 1 should match the expected value.");
	CHECK_MESSAGE(
			node_path_relative.get_name(2) == "Sprite2D",
			"The returned name at index 2 should match the expected value.");
	ERR_PRINT_OFF;
	CHECK_MESSAGE(
			node_path_relative.get_name(3) == "",
			"The returned name at invalid index 3 should match the expected value.");
	CHECK_MESSAGE(
			node_path_relative.get_name(-1) == "",
			"The returned name at invalid index -1 should match the expected value.");
	ERR_PRINT_ON;

	CHECK_MESSAGE(
			node_path_relative.get_name_count() == 3,
			"The returned number of names should match the expected value.");

	CHECK_MESSAGE(
			node_path_relative.get_subname(0) == "position",
			"The returned subname at index 0 should match the expected value.");
	CHECK_MESSAGE(
			node_path_relative.get_subname(1) == "x",
			"The returned subname at index 1 should match the expected value.");
	ERR_PRINT_OFF;
	CHECK_MESSAGE(
			node_path_relative.get_subname(2) == "",
			"The returned subname at invalid index 2 should match the expected value.");
	CHECK_MESSAGE(
			node_path_relative.get_subname(-1) == "",
			"The returned subname at invalid index -1 should match the expected value.");
	ERR_PRINT_ON;

	CHECK_MESSAGE(
			node_path_relative.get_subname_count() == 2,
			"The returned number of subnames should match the expected value.");

	CHECK_MESSAGE(
			!node_path_relative.is_absolute(),
			"The node path should be considered relative.");

	CHECK_MESSAGE(
			!node_path_relative.is_empty(),
			"The node path shouldn't be considered empty.");
}

TEST_CASE("[NodePath] Absolute path") {
	const NodePath node_path_absolute = NodePath("/root/Sprite2D");

	CHECK_MESSAGE(
			node_path_absolute.get_as_property_path() == NodePath(":root/Sprite2D"),
			"The returned property path should match the expected value.");
	CHECK_MESSAGE(
			node_path_absolute.get_concatenated_subnames() == "",
			"The returned concatenated subnames should match the expected value.");

	CHECK_MESSAGE(
			node_path_absolute.get_name(0) == "root",
			"The returned name at index 0 should match the expected value.");
	CHECK_MESSAGE(
			node_path_absolute.get_name(1) == "Sprite2D",
			"The returned name at index 1 should match the expected value.");
	ERR_PRINT_OFF;
	CHECK_MESSAGE(
			node_path_absolute.get_name(2) == "",
			"The returned name at invalid index 2 should match the expected value.");
	CHECK_MESSAGE(
			node_path_absolute.get_name(-1) == "",
			"The returned name at invalid index -1 should match the expected value.");
	ERR_PRINT_ON;

	CHECK_MESSAGE(
			node_path_absolute.get_name_count() == 2,
			"The returned number of names should match the expected value.");

	CHECK_MESSAGE(
			node_path_absolute.get_subname_count() == 0,
			"The returned number of subnames should match the expected value.");

	CHECK_MESSAGE(
			node_path_absolute.is_absolute(),
			"The node path should be considered absolute.");

	CHECK_MESSAGE(
			!node_path_absolute.is_empty(),
			"The node path shouldn't be considered empty.");
}

TEST_CASE("[NodePath] Empty path") {
	const NodePath node_path_empty = NodePath();

	CHECK_MESSAGE(
			node_path_empty.get_as_property_path() == NodePath(),
			"The returned property path should match the expected value.");
	ERR_PRINT_OFF;
	CHECK_MESSAGE(
			node_path_empty.get_concatenated_subnames() == "",
			"The returned concatenated subnames should match the expected value.");
	ERR_PRINT_ON;

	CHECK_MESSAGE(
			node_path_empty.get_name_count() == 0,
			"The returned number of names should match the expected value.");

	CHECK_MESSAGE(
			node_path_empty.get_subname_count() == 0,
			"The returned number of subnames should match the expected value.");

	CHECK_MESSAGE(
			!node_path_empty.is_absolute(),
			"The node path shouldn't be considered absolute.");

	CHECK_MESSAGE(
			node_path_empty.is_empty(),
			"The node path should be considered empty.");
}

TEST_CASE("[NodePath] Slice") {
	const NodePath node_path_relative = NodePath("Parent/Child:prop:subprop");
	const NodePath node_path_absolute = NodePath("/root/Parent/Child:prop");
	CHECK_MESSAGE(
			node_path_relative.slice(0, 2) == NodePath("Parent/Child"),
			"The slice lower bound should be inclusive and the slice upper bound should be exclusive.");
	CHECK_MESSAGE(
			node_path_relative.slice(3) == NodePath(":subprop"),
			"Slicing on the last index (length - 1) should return the last entry.");
	CHECK_MESSAGE(
			node_path_relative.slice(1) == NodePath("Child:prop:subprop"),
			"Slicing without upper bound should return remaining entries after index.");
	CHECK_MESSAGE(
			node_path_relative.slice(1, 3) == NodePath("Child:prop"),
			"Slicing should include names and subnames.");
	CHECK_MESSAGE(
			node_path_relative.slice(-1) == NodePath(":subprop"),
			"Slicing on -1 should return the last entry.");
	CHECK_MESSAGE(
			node_path_relative.slice(0, -1) == NodePath("Parent/Child:prop"),
			"Slicing up to -1 should include the second-to-last entry.");
	CHECK_MESSAGE(
			node_path_relative.slice(-2, -1) == NodePath(":prop"),
			"Slicing from negative to negative should treat lower bound as inclusive and upper bound as exclusive.");
	CHECK_MESSAGE(
			node_path_relative.slice(0, 10) == NodePath("Parent/Child:prop:subprop"),
			"Slicing past the length of the path should work like slicing up to the last entry.");
	CHECK_MESSAGE(
			node_path_relative.slice(-10, 2) == NodePath("Parent/Child"),
			"Slicing negatively past the length of the path should work like slicing from the first entry.");
	CHECK_MESSAGE(
			node_path_relative.slice(1, 1) == NodePath(""),
			"Slicing with a lower bound equal to upper bound should return empty path.");

	CHECK_MESSAGE(
			node_path_absolute.slice(0, 2) == NodePath("/root/Parent"),
			"Slice from beginning of an absolute path should be an absolute path.");
	CHECK_MESSAGE(
			node_path_absolute.slice(1, 4) == NodePath("Parent/Child:prop"),
			"Slice of an absolute path that does not start at the beginning should be a relative path.");
	CHECK_MESSAGE(
			node_path_absolute.slice(3, 4) == NodePath(":prop"),
			"Slice of an absolute path that does not start at the beginning should be a relative path.");

	CHECK_MESSAGE(
			NodePath("").slice(0, 1) == NodePath(""),
			"Slice of an empty path should be an empty path.");
	CHECK_MESSAGE(
			NodePath("").slice(-1, 2) == NodePath(""),
			"Slice of an empty path should be an empty path.");
	CHECK_MESSAGE(
			NodePath("/").slice(-1, 2) == NodePath("/"),
			"Slice of an empty absolute path should be an empty absolute path.");
}


TEST_CASE("[NodePath] Long component and subname joins preserve Unicode and separators") {
	String source;
	String expected_names;
	String expected_subnames;
	for (int i = 0; i < 256; i++) {
		const String name = String(U"узел雪") + itos(i);
		if (i > 0) {
			source += "/";
			expected_names += "/";
		}
		source += name;
		expected_names += name;
	}
	for (int i = 0; i < 64; i++) {
		const String subname = String(U"属性") + itos(i);
		source += ":";
		source += subname;
		if (i > 0) {
			expected_subnames += ":";
		}
		expected_subnames += subname;
	}

	const NodePath path(source);
	CHECK_EQ(path.get_name_count(), 256);
	CHECK_EQ(path.get_subname_count(), 64);
	CHECK_EQ(path.get_concatenated_names().string(), expected_names);
	CHECK_EQ(path.get_concatenated_subnames().string(), expected_subnames);
	CHECK_EQ(String(path), source);
	CHECK_EQ(String(path.get_as_property_path()), ":" + source);
	// The interned name and subname strings should be reusable without recomputing.
	const StringName cached_name = path.get_concatenated_names();
	const StringName cached_subname = path.get_concatenated_subnames();
	CHECK(path.get_concatenated_names() == cached_name);
	CHECK(path.get_concatenated_subnames() == cached_subname);
}

TEST_CASE("[NodePath] Joined paths survive copy on write and invalidation") {
	const NodePath original("root/./child:position:x");
	NodePath modified = original;
	CHECK_EQ(original.get_concatenated_names().string(), "root/./child");
	CHECK_EQ(modified.get_concatenated_names().string(), "root/./child");

	modified.simplify();
	CHECK_EQ(modified.get_concatenated_names().string(), "root/child");
	CHECK_EQ(modified.get_concatenated_subnames().string(), "position:x");
	CHECK_EQ(original.get_concatenated_names().string(), "root/./child");

	modified.prepend_period();
	CHECK_EQ(modified.get_concatenated_names().string(), "./root/child");
	CHECK_EQ(original.get_concatenated_names().string(), "root/./child");
	CHECK_EQ(String(modified.get_as_property_path()), ":./root/child:position:x");
}

TEST_CASE("[NodePath] Single and empty components retain path shape") {
	const NodePath single("Sprite2D");
	CHECK_EQ(single.get_concatenated_names().string(), "Sprite2D");
	CHECK_EQ(single.get_concatenated_subnames().string(), "");
	CHECK_EQ(String(single.get_as_property_path()), ":Sprite2D");

	const NodePath only_subnames(":position:x");
	CHECK_EQ(only_subnames.get_concatenated_names().string(), "");
	CHECK_EQ(only_subnames.get_concatenated_subnames().string(), "position:x");
	CHECK_EQ(String(only_subnames), ":position:x");

	const NodePath absolute("/root/Sprite2D:position");
	CHECK_EQ(absolute.get_concatenated_names().string(), "root/Sprite2D");
	CHECK_EQ(String(absolute), "/root/Sprite2D:position");
	CHECK_EQ(String(absolute.get_as_property_path()), ":root/Sprite2D:position");
}


TEST_CASE("[NodePath] Linear simplify matches the legacy removal algorithm") {
	const StringName parts[] = { ".", "..", "root", "child", "leaf" };
	uint32_t seed = 0x91736EBD;
	for (int run = 0; run < 2048; run++) {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		const int count = 2 + int(seed % 48);

		Vector<StringName> reference;
		for (int i = 0; i < count; i++) {
			seed ^= seed << 13;
			seed ^= seed >> 17;
			seed ^= seed << 5;
			reference.push_back(parts[seed % 5]);
		}
		NodePath path(reference, false);

		// Independent reference implementation of the previous behavior.
		for (int i = 0; i < reference.size(); i++) {
			if (reference.size() == 1) {
				break;
			}
			if (reference[i].string() == ".") {
				reference.remove_at(i);
				i--;
			} else if (i > 0 && reference[i].string() == ".." && reference[i - 1].string() != "." && reference[i - 1].string() != "..") {
				reference.remove_at(i - 1);
				reference.remove_at(i - 1);
				i -= 2;
				if (reference.is_empty()) {
					reference.push_back(".");
					break;
				}
			}
		}

		path.simplify();
		CHECK_EQ(path.get_name_count(), reference.size());
		for (int i = 0; i < MIN(path.get_name_count(), reference.size()); i++) {
			CHECK(path.get_name(i) == reference[i]);
		}
	}
}

TEST_CASE("[NodePath] Linear simplify handles deep cancellation and property subnames") {
	String source;
	for (int i = 0; i < 1024; i++) {
		source += "segment/..";
		if (i + 1 < 1024) {
			source += "/";
		}
	}
	const NodePath original(source + ":position:x");
	NodePath simplified = original;
	const StringName old_names = simplified.get_concatenated_names();
	simplified.simplify();

	CHECK_EQ(simplified.get_concatenated_names().string(), ".");
	CHECK_EQ(simplified.get_concatenated_subnames().string(), "position:x");
	CHECK_EQ(String(simplified), ".:position:x");
	CHECK_EQ(String(simplified.get_as_property_path()), ":.:position:x");
	CHECK_EQ(original.get_concatenated_names(), old_names);
	CHECK_EQ(original.get_name_count(), 2048);
}

TEST_CASE("[NodePath] Simplify normalized shared path preserves cache and references") {
	const NodePath original("/root/parent/child:position:x");
	NodePath copy = original;
	const StringName names = original.get_concatenated_names();
	const uint32_t hash_before = original.hash();
	for (int i = 0; i < 32; i++) {
		copy.simplify();
	}
	CHECK_EQ(copy.get_concatenated_names(), names);
	CHECK_EQ(copy.hash(), hash_before);
	CHECK_EQ(original.get_concatenated_names(), names);
	CHECK_EQ(String(copy), "/root/parent/child:position:x");
}


TEST_CASE("[NodePath] Simple relative paths stringify without a new string buffer") {
	const NodePath path(U"Сцена/Node2D/雪");
	const StringName cached = path.get_concatenated_names();
	const String &canonical = cached.string();

	for (int i = 0; i < 128; i++) {
		const String value = String(path);
		CHECK_EQ(value, canonical);
		CHECK(value.ptr() == canonical.ptr());
	}
}

TEST_CASE("[NodePath] Stringify absolute and property paths with one output buffer") {
	const NodePath paths[] = {
		NodePath("/"),
		NodePath("/root/Node2D"),
		NodePath("/root/Node2D:position:x"),
		NodePath("root/Node2D:position:x"),
		NodePath(":position:x"),
		NodePath(U"/Сцена/雪:属性:x"),
		NodePath("."),
		NodePath(".."),
	};
	const String expected[] = {
		"/", "/root/Node2D", "/root/Node2D:position:x",
		"root/Node2D:position:x", ":position:x",
		U"/Сцена/雪:属性:x", ".", "..",
	};
	for (int i = 0; i < 8; i++) {
		for (int repeat = 0; repeat < 16; repeat++) {
			CHECK_EQ(String(paths[i]), expected[i]);
		}
	}
}

TEST_CASE("[NodePath] Long stringified paths preserve all codepoints") {
	String source = "/";
	for (int i = 0; i < 400; i++) {
		if (i > 0) {
			source += "/";
		}
		source += String(U"дочерний雪") + itos(i);
	}
	source += ":position:属性:x";
	NodePath path(source);
	for (int i = 0; i < 32; i++) {
		CHECK_EQ(String(path), source);
	}
	CHECK_EQ(String(path.get_as_property_path()), ":" + source.substr(1));
}

} // namespace TestNodePath
