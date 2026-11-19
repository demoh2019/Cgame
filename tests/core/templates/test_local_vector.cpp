/**************************************************************************/
/*  test_local_vector.cpp                                                 */
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

TEST_FORCE_LINK(test_local_vector)

#include "core/templates/local_vector.h"

#include <vector>

namespace TestLocalVector {

TEST_CASE("[LocalVector] List Initialization.") {
	LocalVector<int> vector{ 0, 1, 2, 3, 4 };

	CHECK(vector.size() == 5);
	CHECK(vector[0] == 0);
	CHECK(vector[1] == 1);
	CHECK(vector[2] == 2);
	CHECK(vector[3] == 3);
	CHECK(vector[4] == 4);
}

TEST_CASE("[LocalVector] Push Back.") {
	LocalVector<int> vector;
	vector.push_back(0);
	vector.push_back(1);
	vector.push_back(2);
	vector.push_back(3);
	vector.push_back(4);

	CHECK(vector[0] == 0);
	CHECK(vector[1] == 1);
	CHECK(vector[2] == 2);
	CHECK(vector[3] == 3);
	CHECK(vector[4] == 4);
}

TEST_CASE("[LocalVector] Find, has.") {
	LocalVector<int> vector;
	vector.push_back(3);
	vector.push_back(1);
	vector.push_back(4);
	vector.push_back(0);
	vector.push_back(2);

	CHECK(vector[0] == 3);
	CHECK(vector[1] == 1);
	CHECK(vector[2] == 4);
	CHECK(vector[3] == 0);
	CHECK(vector[4] == 2);

	CHECK(vector.find(0) == 3);
	CHECK(vector.find(1) == 1);
	CHECK(vector.find(2) == 4);
	CHECK(vector.find(3) == 0);
	CHECK(vector.find(4) == 2);

	CHECK(vector.find(-1) == -1);
	CHECK(vector.find(5) == -1);

	CHECK(vector.has(0));
	CHECK(vector.has(1));
	CHECK(vector.has(2));
	CHECK(vector.has(3));
	CHECK(vector.has(4));

	CHECK(!vector.has(-1));
	CHECK(!vector.has(5));
}

TEST_CASE("[LocalVector] Remove.") {
	LocalVector<int> vector;
	vector.push_back(0);
	vector.push_back(1);
	vector.push_back(2);
	vector.push_back(3);
	vector.push_back(4);

	vector.remove_at(0);

	CHECK(vector[0] == 1);
	CHECK(vector[1] == 2);
	CHECK(vector[2] == 3);
	CHECK(vector[3] == 4);

	vector.remove_at(2);

	CHECK(vector[0] == 1);
	CHECK(vector[1] == 2);
	CHECK(vector[2] == 4);

	vector.remove_at(1);

	CHECK(vector[0] == 1);
	CHECK(vector[1] == 4);

	vector.remove_at(0);

	CHECK(vector[0] == 4);
}

TEST_CASE("[LocalVector] Remove Unordered.") {
	LocalVector<int> vector;
	vector.push_back(0);
	vector.push_back(1);
	vector.push_back(2);
	vector.push_back(3);
	vector.push_back(4);

	CHECK(vector.size() == 5);

	vector.remove_at_unordered(0);

	CHECK(vector.size() == 4);

	CHECK(vector.find(0) == -1);
	CHECK(vector.find(1) != -1);
	CHECK(vector.find(2) != -1);
	CHECK(vector.find(3) != -1);
	CHECK(vector.find(4) != -1);

	// Now the vector is no more ordered.
	vector.remove_at_unordered(vector.find(3));

	CHECK(vector.size() == 3);

	CHECK(vector.find(3) == -1);
	CHECK(vector.find(1) != -1);
	CHECK(vector.find(2) != -1);
	CHECK(vector.find(4) != -1);

	vector.remove_at_unordered(vector.find(2));

	CHECK(vector.size() == 2);

	CHECK(vector.find(2) == -1);
	CHECK(vector.find(1) != -1);
	CHECK(vector.find(4) != -1);

	vector.remove_at_unordered(vector.find(4));

	CHECK(vector.size() == 1);

	CHECK(vector.find(4) == -1);
	CHECK(vector.find(1) != -1);

	// Remove the last one.
	vector.remove_at_unordered(0);

	CHECK(vector.is_empty());
	CHECK(vector.size() == 0);
}

TEST_CASE("[LocalVector] Erase Unordered.") {
	LocalVector<int> vector;
	vector.push_back(1);
	vector.push_back(3);
	vector.push_back(0);
	vector.push_back(2);
	vector.push_back(4);

	CHECK(vector.find(1) == 0);

	vector.erase_unordered(1);

	CHECK(vector.find(1) == -1);
	CHECK(vector.size() == 4);
	CHECK(vector[0] == 4);
}

TEST_CASE("[LocalVector] Erase.") {
	LocalVector<int> vector;
	vector.push_back(1);
	vector.push_back(3);
	vector.push_back(0);
	vector.push_back(2);
	vector.push_back(4);

	CHECK(vector.find(2) == 3);

	vector.erase(2);

	CHECK(vector.find(2) == -1);
	CHECK(vector.size() == 4);
}

TEST_CASE("[LocalVector] Size / Resize / Reserve.") {
	LocalVector<int> vector;

	CHECK(vector.is_empty());
	CHECK(vector.size() == 0);
	CHECK(vector.get_capacity() == 0);

	vector.resize(10);

	CHECK(vector.size() == 10);
	CHECK(vector.get_capacity() >= 10);

	vector.resize(5);

	CHECK(vector.size() == 5);
	// Capacity is supposed to change only when the size increase.
	CHECK(vector.get_capacity() >= 10);

	vector.remove_at(0);
	vector.remove_at(0);
	vector.remove_at(0);

	CHECK(vector.size() == 2);
	// Capacity is supposed to change only when the size increase.
	CHECK(vector.get_capacity() >= 10);

	vector.reset();

	CHECK(vector.size() == 0);
	CHECK(vector.get_capacity() == 0);

	vector.reserve(3);

	CHECK(vector.is_empty());
	CHECK(vector.size() == 0);
	CHECK(vector.get_capacity() >= 3);

	vector.push_back(0);
	vector.push_back(0);
	vector.push_back(0);

	CHECK(vector.size() == 3);
	CHECK(vector.get_capacity() >= 3);

	vector.push_back(0);

	CHECK(vector.size() == 4);
	CHECK(vector.get_capacity() >= 4);
}

TEST_CASE("[LocalVector] Bulk trivial insert and remove match reference vector") {
	LocalVector<int> actual;
	std::vector<int> expected;
	for (int i = 0; i < 512; i++) {
		const size_t position = size_t(i * 23) % (expected.size() + 1);
		actual.insert(uint32_t(position), i);
		expected.insert(expected.begin() + position, i);
	}
	for (int i = 0; i < 256; i++) {
		const size_t position = size_t(i * 17) % expected.size();
		actual.remove_at(uint32_t(position));
		expected.erase(expected.begin() + position);
	}
	CHECK(actual.size() == expected.size());
	for (size_t i = 0; i < expected.size(); i++) {
		CHECK(actual[uint32_t(i)] == expected[i]);
	}
	actual.remove_at(0);
	CHECK(actual.size() == expected.size() - 1);
	actual.remove_at(actual.size() - 1);
	CHECK(actual.size() == expected.size() - 2);
}

TEST_CASE("[LocalVector] Byte find handles offsets and signed characters") {
	LocalVector<uint8_t> bytes;
	bytes.resize(4096);
	for (uint32_t i = 0; i < bytes.size(); i++) {
		bytes[i] = uint8_t(i & 255);
	}
	CHECK(bytes.find(uint8_t(201)) == 201);
	CHECK(bytes.find(uint8_t(201), 202) == 457);
	CHECK(bytes.find(uint8_t(255), -1) == 4095);
	CHECK(bytes.find(uint8_t(0), 4096) == -1);
	CHECK(bytes.find(uint8_t(0), -4097) == -1);

	LocalVector<int8_t> signed_bytes{ -128, -10, 0, 10, 127 };
	CHECK(signed_bytes.find(int8_t(-128)) == 0);
	CHECK(signed_bytes.find(int8_t(127), 1) == 4);
	CHECK(signed_bytes.find(int8_t(-10), 2) == -1);
}

TEST_CASE("[LocalVector] Nontrivial insert and erase preserve element order") {
	LocalVector<String> names;
	names.push_back("alpha");
	names.push_back("gamma");
	names.insert(1, String("beta"));
	CHECK(names.size() == 3);
	CHECK(names[0] == "alpha");
	CHECK(names[1] == "beta");
	CHECK(names[2] == "gamma");
	CHECK(names.find(String("gamma")) == 2);
	names.remove_at(0);
	CHECK(names[0] == "beta");
	CHECK(names[1] == "gamma");
}

} // namespace TestLocalVector
