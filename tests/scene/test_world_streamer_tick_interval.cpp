/**************************************************************************/
/*  test_world_streamer_tick_interval.cpp                                  */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_tick_interval)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerTickInterval {

TEST_CASE("[WorldStreamer] Cosmetic update interval is opt-in and bounded") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	CHECK(streamer->get_tick_throttle_radius() == -1.0);
	CHECK(streamer->get_tick_throttle_interval() == doctest::Approx(0.125));
	CHECK(streamer->get_tick_throttle_hysteresis() == 8.0);
	CHECK(streamer->get_max_tick_throttle_transitions_per_update() == 4);
	CHECK(streamer->get_tick_throttled_count() == 0);
	CHECK_FALSE(streamer->is_cell_tick_throttled(Vector3i(0, 0, 0)));

	streamer->set_tick_throttle_radius(-100.0);
	CHECK(streamer->get_tick_throttle_radius() == -1.0);
	streamer->set_tick_throttle_radius(100001.0);
	CHECK(streamer->get_tick_throttle_radius() == 100000.0);

	streamer->set_tick_throttle_interval(-1.0);
	CHECK(streamer->get_tick_throttle_interval() == 0.0);
	streamer->set_tick_throttle_interval(2.0);
	CHECK(streamer->get_tick_throttle_interval() == 1.0);
	streamer->set_tick_throttle_interval(0.125);
	CHECK(streamer->get_tick_throttle_interval() == doctest::Approx(0.125));

	streamer->set_tick_throttle_hysteresis(-10.0);
	CHECK(streamer->get_tick_throttle_hysteresis() == 0.0);
	streamer->set_tick_throttle_hysteresis(4000.0);
	CHECK(streamer->get_tick_throttle_hysteresis() == 1000.0);

	streamer->set_max_tick_throttle_transitions_per_update(0);
	CHECK(streamer->get_max_tick_throttle_transitions_per_update() == 1);
	streamer->set_max_tick_throttle_transitions_per_update(9000);
	CHECK(streamer->get_max_tick_throttle_transitions_per_update() == 64);
	streamer->unload_all();
	CHECK(streamer->get_tick_throttled_count() == 0);
	memdelete(streamer);
}

} // namespace TestWorldStreamerTickInterval
