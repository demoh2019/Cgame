/**************************************************************************/
/*  test_ring_buffer.cpp                                                  */
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

TEST_FORCE_LINK(test_ring_buffer)

#include "core/templates/ring_buffer.h"

#include <string>

namespace TestRingBuffer {

TEST_CASE("[RingBuffer] Initialization") {
	constexpr int RB_SIZE_POW = 4;
	RingBuffer<int> rb = RB_SIZE_POW;

	CHECK(rb.size() == (1 << RB_SIZE_POW));
	CHECK(rb.data_left() == 0);
	CHECK(rb.space_left() == rb.size() - 1);

	for (int i = 1; i < rb.size(); i++) {
		rb.write(i);

		CHECK(rb.size() == (1 << RB_SIZE_POW));
		CHECK(rb.data_left() == i);
		CHECK(rb.space_left() == (rb.size() - 1 - i));
	}

	for (int i = 1; rb.data_left() > 0; i++) {
		CHECK(rb.read() == i);
		CHECK(rb.data_left() == (rb.size() - 1 - i));
		CHECK(rb.space_left() == i);
	}
}

TEST_CASE("[RingBuffer] Copy Assignment 1") {
	constexpr int RB_SIZE_POW = 4;
	RingBuffer<int> rb1 = RB_SIZE_POW;
	RingBuffer<int> rb2 = rb1;

	CHECK(rb1.size() == rb2.size());
	CHECK(rb1.data_left() == rb2.data_left());
	CHECK(rb1.space_left() == rb2.space_left());

	for (int i = 1; i < rb1.size(); i++) {
		rb1.write(i);
	}

	CHECK(rb1.data_left() != rb2.data_left());
	CHECK(rb1.space_left() != rb2.space_left());

	for (int i = 1; i < rb2.size(); i++) {
		// rb1 and rb2 have separate heap allocated buffers. These writes should not effect rb1.
		rb2.write(i + rb2.size());
	}

	CHECK(rb1.size() == rb2.size());
	CHECK(rb1.data_left() == rb2.data_left());
	CHECK(rb1.space_left() == rb2.space_left());
	while (rb1.data_left() > 0) {
		CHECK(rb1.size() == rb2.size());
		CHECK(rb1.data_left() == rb2.data_left());
		CHECK(rb1.space_left() == rb2.space_left());
		CHECK(rb1.read() != rb2.read());
	}
}

TEST_CASE("[RingBuffer] Copy Assignment 2") {
	constexpr int RB_SIZE_POW = 4;
	RingBuffer<int> rb1 = RB_SIZE_POW;

	for (int i = 1; i < rb1.size(); i++) {
		rb1.write(i);
	}
	RingBuffer<int> rb2 = rb1;

	CHECK(rb1.size() == rb2.size());
	CHECK(rb1.data_left() == rb2.data_left());
	CHECK(rb1.space_left() == rb2.space_left());
	while (rb1.data_left() > 0) {
		CHECK(rb1.size() == rb2.size());
		CHECK(rb1.data_left() == rb2.data_left());
		CHECK(rb1.space_left() == rb2.space_left());
		CHECK(rb1.read() == rb2.read());
	}
}

TEST_CASE("[RingBuffer] Copy Assignment 3") {
	constexpr int RB_SIZE_POW = 4;
	RingBuffer<int> rb1 = RB_SIZE_POW;

	for (int i = 1; i < rb1.size(); i++) {
		rb1.write(i);
	}
	RingBuffer<int> rb2 = rb1;

	rb2.read();
	CHECK(rb1.data_left() > rb2.data_left());
	CHECK(rb1.space_left() < rb2.space_left());
}

TEST_CASE("[RingBuffer] Read 1") {
	RingBuffer<int> rb1 = 2;
	int buf[3] = { 7, 7, 7 };

	// Looping to test wrapping
	for (int _i = 0; _i < 4; _i++) {
		for (int i = 0; i < 3; i++) {
			rb1.write(i);
		}

		int r = rb1.read(buf, 3);
		CHECK(r == 3);

		for (int i = 0; i < 3; i++) {
			CHECK(buf[i] == i);
		}
	}
}

TEST_CASE("[RingBuffer] Read 2") {
	RingBuffer<int> rb1 = 2;
	int buf1[3] = { 7, 7, 7 };
	int buf2[3] = { 7, 7, 7 };

	for (int i = 0; i < 3; i++) {
		rb1.write(i);
	}

	int r1 = rb1.read(buf1, 3, false);
	CHECK(r1 == 3);
	CHECK(rb1.data_left() == 3);
	int r2 = rb1.read(buf2, 3);
	CHECK(r2 == 3);
	CHECK(rb1.data_left() == 0);

	for (int i = 0; i < 3; i++) {
		CHECK(buf1[i] == i);
		CHECK(buf1[i] == buf2[i]);
	}
}

TEST_CASE("[RingBuffer] Write 1") {
	RingBuffer<int> rb1 = 4;
	int buf1[6] = { 72, 48, 49, 93, 64, 74 };

	rb1.write(buf1, 6);
	CHECK(rb1.data_left() == 6);
	CHECK(rb1.space_left() == rb1.size() - 1 - rb1.data_left());

	for (int i = 0; i < 6; i++) {
		CHECK(rb1.read() == buf1[i]);
	}
}

TEST_CASE("[RingBuffer] Copy 1") {
	RingBuffer<int> rb1 = 2;
	int buf[3] = { 7, 7, 7 };

	for (int i = 0; i < 3; i++) {
		rb1.write(i);
	}

	int r = rb1.copy(buf, 0, 3);
	CHECK(r == 3);

	for (int i = 0; i < 3; i++) {
		CHECK(buf[i] == i);
	}
}

TEST_CASE("[RingBuffer] Copy 2") {
	RingBuffer<int> rb1 = 4;
	int buf[6] = { 7, 7, 7, 7, 7, 7 };

	for (int i = 0; i < 6; i++) {
		rb1.write(i);
	}

	int r = rb1.copy(buf, 4, 6);
	CHECK(r == 2);

	for (int i = 0; i < 2; i++) {
		CHECK(buf[i] == i + 4);
	}

	for (int i = 2; i < 6; i++) {
		CHECK(buf[i] == 7);
	}
}

TEST_CASE("[RingBuffer] Find 1") {
	RingBuffer<int> rb1 = 4;

	for (int i = 0; i < 6; i++) {
		rb1.write(i);
	}

	for (int i = 0; i < 6; i++) {
		int r = rb1.find(i, 0, 6);
		CHECK(r == i);
	}

	int r = rb1.find(7, 0, 6);
	CHECK(r == -1);
}

TEST_CASE("[RingBuffer] Advance read") {
	RingBuffer<int> rb1 = 4;

	for (int i = 0; i < 9; i++) {
		for (int ii = 0; ii < 8; ii++) {
			rb1.write(ii);
		}

		int len = rb1.data_left();
		int r = rb1.advance_read(i);
		CHECK(r == MIN(len, i));
		CHECK(rb1.data_left() == MAX(len - i, 0));

		for (int ii = i; ii < 8; ii++) {
			CHECK(rb1.read() == ii);
		}
	}
}

TEST_CASE("[RingBuffer] Decrease write") {
	RingBuffer<int> rb1 = 4;

	for (int i = 0; i < 9; i++) {
		for (int ii = 0; ii < 8; ii++) {
			rb1.write(ii);
		}

		int len = rb1.data_left();
		int r = rb1.decrease_write(i);
		CHECK(r == MIN(len, i));
		CHECK(rb1.data_left() == MAX(len - i, 0));

		for (int ii = 0; ii < 8 - i; ii++) {
			CHECK(rb1.read() == ii);
		}
	}
}

TEST_CASE("[RingBuffer] Resize 1") {
	RingBuffer<int> rb1 = 2;
	CHECK(rb1.size() == 1 << 2);
	CHECK(rb1.space_left() == rb1.size() - 1);

	rb1.resize(5);
	CHECK(rb1.size() == 1 << 5);
	CHECK(rb1.space_left() == rb1.size() - 1);

	rb1.resize(1);
	CHECK(rb1.size() == 1 << 1);
	CHECK(rb1.space_left() == rb1.size() - 1);
}

TEST_CASE("[RingBuffer] Resize 2") {
	RingBuffer<int> rb1 = 4;
	CHECK(rb1.size() == 1 << 4);
	CHECK(rb1.data_left() == 0);
	CHECK(rb1.space_left() == (1 << 4) - 1);

	for (int i = 0; i < rb1.size() - 1; i++) {
		rb1.write(i);
	}
	CHECK(rb1.data_left() == (1 << 4) - 1);
	CHECK(rb1.space_left() == 0);

	rb1.resize(5);
	CHECK(rb1.size() == 1 << 5);
	CHECK(rb1.data_left() == (1 << 4) - 1);
	CHECK(rb1.space_left() == ((1 << 5) - 1) - ((1 << 4) - 1));

	rb1.resize(1);
	CHECK(rb1.size() == 1 << 1);
	CHECK(rb1.data_left() == (1 << 1) - 1);
	CHECK(rb1.space_left() == 0);
}


TEST_CASE("[RingBuffer] Bulk trivial copy across wrap") {
	RingBuffer<uint8_t> rb(3);
	const uint8_t first[] = { 1, 2, 3, 4, 5, 6 };
	CHECK(rb.write(first, 6) == 6);
	uint8_t drop[5] = {};
	CHECK(rb.read(drop, 5) == 5);
	for (int i = 0; i < 5; i++) {
		CHECK(drop[i] == first[i]);
	}
	const uint8_t second[] = { 7, 8, 9, 10, 11, 12 };
	CHECK(rb.write(second, 6) == 6);
	CHECK(rb.data_left() == 7);
	uint8_t peek[7] = {};
	CHECK(rb.copy(peek, 0, 7) == 7);
	CHECK(peek[0] == 6);
	for (int i = 1; i < 7; i++) {
		CHECK(peek[i] == second[i - 1]);
	}
	uint8_t popped[7] = {};
	CHECK(rb.read(popped, 7) == 7);
	for (int i = 0; i < 7; i++) {
		CHECK(popped[i] == peek[i]);
	}
}

TEST_CASE("[RingBuffer] Bulk nontrivial strings preserve values") {
	RingBuffer<std::string> rb(3);
	const std::string first[] = { "alpha", "beta", "gamma", "delta", "epsilon", "zeta" };
	CHECK(rb.write(first, 6) == 6);
	std::string prefix[4];
	CHECK(rb.read(prefix, 4) == 4);
	for (int i = 0; i < 4; i++) {
		CHECK(prefix[i] == first[i]);
	}
	const std::string second[] = { "eta", "theta", "iota", "kappa" };
	CHECK(rb.write(second, 4) == 4);
	std::string values[6];
	CHECK(rb.read(values, 6, false) == 6);
	CHECK(values[0] == "epsilon");
	CHECK(values[1] == "zeta");
	for (int i = 0; i < 4; i++) {
		CHECK(values[i + 2] == second[i]);
	}
	CHECK(rb.data_left() == 6);
	CHECK(rb.read(values, 6) == 6);
}

TEST_CASE("[RingBuffer] Empty and invalid bulk lengths do not change state") {
	RingBuffer<int> rb(3);
	const int values[] = { 1, 2, 3 };
	int out[] = { 99, 99, 99 };
	CHECK(rb.write(values, 0) == 0);
	CHECK(rb.write(values, -2) == 0);
	CHECK(rb.read(out, 0) == 0);
	CHECK(rb.read(out, -2) == 0);
	CHECK(rb.data_left() == 0);
	CHECK(out[0] == 99);
}

TEST_CASE("[RingBuffer] Bulk wrapped resize preserves sequence") {
	RingBuffer<uint8_t> rb(3);
	const uint8_t first[] = { 1, 2, 3, 4, 5, 6 };
	CHECK(rb.write(first, 6) == 6);
	CHECK(rb.advance_read(5) == 5);
	const uint8_t second[] = { 7, 8, 9, 10, 11 };
	CHECK(rb.write(second, 5) == 5);
	rb.resize(4);
	uint8_t output[6] = {};
	CHECK(rb.read(output, 6) == 6);
	CHECK(output[0] == 6);
	for (int i = 1; i < 6; i++) {
		CHECK(output[i] == second[i - 1]);
	}
}

TEST_CASE("[RingBuffer] Byte search covers wrapped storage and offsets") {
	RingBuffer<uint8_t> rb(3);
	const uint8_t first[] = { 10, 20, 30, 40, 50, 60 };
	CHECK(rb.write(first, 6) == 6);
	CHECK(rb.advance_read(5) == 5);
	const uint8_t second[] = { 70, 80, 90, 100, 110 };
	CHECK(rb.write(second, 5) == 5);

	CHECK(rb.find(uint8_t(60), 0, 6) == 0);
	CHECK(rb.find(uint8_t(70), 0, 6) == 1);
	CHECK(rb.find(uint8_t(90), 0, 6) == 3);
	CHECK(rb.find(uint8_t(110), 0, 6) == 5);
	CHECK(rb.find(uint8_t(90), 2, 4) == 1);
	CHECK(rb.find(uint8_t(90), 4, 2) == -1);
	CHECK(rb.find(uint8_t(10), 0, 6) == -1);
	CHECK(rb.data_left() == 6);
}

TEST_CASE("[RingBuffer] Signed byte searches match raw byte values") {
	RingBuffer<int8_t> rb(3);
	const int8_t data[] = { -128, -7, 0, 42, 127 };
	CHECK(rb.write(data, 5) == 5);
	CHECK(rb.find(int8_t(-128), 0, 5) == 0);
	CHECK(rb.find(int8_t(-7), 0, 5) == 1);
	CHECK(rb.find(int8_t(127), 1, 4) == 3);
	CHECK(rb.find(int8_t(5), 0, 5) == -1);
}

TEST_CASE("[RingBuffer] Invalid byte search ranges do not access memory") {
	RingBuffer<uint8_t> rb(3);
	const uint8_t data[] = { 1, 2, 3 };
	CHECK(rb.write(data, 3) == 3);
	CHECK(rb.find(uint8_t(1), -1, 2) == -1);
	CHECK(rb.find(uint8_t(1), 0, -1) == -1);
	CHECK(rb.find(uint8_t(1), 0, 0) == -1);
	CHECK(rb.find(uint8_t(1), 3, 1) == -1);
	CHECK(rb.find(uint8_t(2), 1, 2147483647) == 0);
	CHECK(rb.data_left() == 3);
}

TEST_CASE("[RingBuffer] Nontrivial element search keeps equality semantics") {
	RingBuffer<std::string> rb(3);
	const std::string values[] = { "one", "two", "three", "four" };
	CHECK(rb.write(values, 4) == 4);
	CHECK(rb.find(std::string("three"), 0, 4) == 2);
	CHECK(rb.find(std::string("two"), 1, 2) == 0);
	CHECK(rb.find(std::string("absent"), 0, 4) == -1);
}

} //namespace TestRingBuffer