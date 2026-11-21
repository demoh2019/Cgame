/**************************************************************************/
/*  test_adaptive_network_jitter_buffer.cpp                                              */
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

TEST_FORCE_LINK(test_adaptive_network_jitter_buffer)

#include "scene/main/adaptive_network_jitter_buffer.h"

namespace TestAdaptiveNetworkJitterBuffer {

TEST_CASE("[AdaptiveNetworkJitterBuffer] Stable arrivals, jitter spikes and gradual release") {
	Ref<AdaptiveNetworkJitterBuffer> buffer;
	buffer.instantiate();
	CHECK(buffer->get_delay() == doctest::Approx(0.12));
	CHECK(buffer->observe(1.0, 10.0) == doctest::Approx(0.12));
	for (int i = 0; i < 60; i++) {
		buffer->observe(1.1 + i * 0.1, 10.1 + i * 0.1);
	}
	CHECK(buffer->get_delay() == doctest::Approx(0.12));
	CHECK(buffer->observe(7.1, 19.5) == doctest::Approx(0.12));
	buffer->observe(7.1, 20.0);
	CHECK(buffer->get_delay() == doctest::Approx(0.12));
	CHECK(int64_t(buffer->get_stats()["ignored_packets"]) >= 1);
	buffer->reset();
	buffer->observe(1.0, 10.0);
	buffer->observe(1.1, 10.27);
	CHECK(buffer->get_delay() > 0.27);
	CHECK(buffer->get_delay() <= 0.35);
	const double delayed = buffer->get_delay();
	buffer->observe(1.1, 10.30);
	CHECK(buffer->get_delay() == doctest::Approx(delayed));
	for (int i = 0; i < 300; i++) {
		buffer->observe(1.2 + i * 0.1, 10.37 + i * 0.1);
	}
	CHECK(buffer->get_delay() == doctest::Approx(0.12).epsilon(0.05));
}

TEST_CASE("[AdaptiveNetworkJitterBuffer] Epoch changes, missing ticks, invalid input and counters") {
	Ref<AdaptiveNetworkJitterBuffer> buffer;
	buffer.instantiate();
	buffer->observe(1.0, 10.0);
	buffer->observe(1.3, 10.3);
	CHECK(buffer->get_delay() > 0.12);
	buffer->observe(0.9, 10.31);
	CHECK(buffer->get_delay() > 0.12); // Out of order is ignored.
	buffer->observe(0.2, 10.4);
	CHECK(buffer->get_delay() == doctest::Approx(0.12)); // New epoch.
	CHECK(int64_t(buffer->get_stats()["resets"]) == 1);
	buffer->observe(Math::NaN, 10.5);
	buffer->observe(0.2, Math::INF);
	CHECK(int64_t(buffer->get_stats()["ignored_packets"]) == 3);
	buffer->observe(1.0, 10.6);
	CHECK(buffer->get_delay() == doctest::Approx(0.12));
	CHECK(int64_t(buffer->get_stats()["network_gaps"]) == 1);
	buffer->reset();
	CHECK(int64_t(buffer->get_stats()["accepted_packets"]) == 0);
	CHECK(int64_t(buffer->get_stats()["ignored_packets"]) == 0);
	CHECK(int64_t(buffer->get_stats()["resets"]) == 0);
}

TEST_CASE("[AdaptiveNetworkJitterBuffer] Configurable rates and invalid profiles") {
	Ref<AdaptiveNetworkJitterBuffer> buffer;
	buffer.instantiate();
	CHECK_FALSE(buffer->configure(-1.0, 0.35, 0.1));
	CHECK_FALSE(buffer->configure(0.12, 0.05, 0.1));
	CHECK_FALSE(buffer->configure(0.12, 0.35, Math::NaN));
	CHECK_FALSE(buffer->configure(0.12, 0.35, 0.0));
	CHECK(buffer->configure(0.06, 0.20, 0.05)); // 20Hz game.
	CHECK(buffer->get_delay() == doctest::Approx(0.06));
	buffer->observe(1.0, 10.0);
	buffer->observe(1.05, 10.16); // Late by 0.11s.
	CHECK(buffer->get_delay() == doctest::Approx(0.20));
	CHECK(double(buffer->get_stats()["expected_snapshot_step"]) == doctest::Approx(0.05));
	CHECK(bool(buffer->get_stats()["native_backend"]));
}
} // namespace TestAdaptiveNetworkJitterBuffer
