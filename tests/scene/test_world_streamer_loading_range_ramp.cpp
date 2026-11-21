/**************************************************************************/
/*  test_world_streamer_loading_range_ramp.cpp                              */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_loading_range_ramp)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerLoadingRangeRamp {

TEST_CASE("[WorldStreamer] Startup loading area ramp is opt-in and bounded") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	streamer->set_load_radius(80.0);
	CHECK(streamer->get_effective_load_radius() == real_t(80.0));
	CHECK(streamer->get_loading_range_area_percent() == real_t(100.0));
	CHECK_FALSE(streamer->is_loading_range_ramping());

	streamer->begin_loading_range_ramp(0.25, 0.5, 2.0);
	CHECK(streamer->is_loading_range_ramping());
	CHECK(Math::abs(streamer->get_effective_load_radius() - real_t(40.0)) < real_t(0.001));
	streamer->advance_loading_range_ramp(0.5);
	CHECK(streamer->get_loading_range_area_percent() == real_t(25.0));
	streamer->advance_loading_range_ramp(1.0);
	CHECK(Math::abs(streamer->get_loading_range_area_percent() - real_t(62.5)) < real_t(0.001));
	streamer->advance_loading_range_ramp(1.0);
	CHECK_FALSE(streamer->is_loading_range_ramping());
	CHECK(streamer->get_effective_load_radius() == real_t(80.0));

	streamer->set_axes(WorldStreamer::AXES_XYZ);
	streamer->begin_loading_range_ramp(0.125, 0.0, 2.0);
	CHECK(Math::abs(streamer->get_effective_load_radius() - real_t(40.0)) < real_t(0.001));
	streamer->cancel_loading_range_ramp();
	CHECK(streamer->get_loading_range_area_percent() == real_t(100.0));
	CHECK(streamer->get_effective_load_radius() == real_t(80.0));

	streamer->begin_loading_range_ramp(-1.0, 0.0, 2.0);
	CHECK(streamer->get_loading_range_area_percent() == real_t(5.0));
	streamer->advance_loading_range_ramp(-1.0);
	CHECK(streamer->get_loading_range_area_percent() == real_t(5.0));
	streamer->advance_loading_range_ramp(3.0);
	CHECK_FALSE(streamer->is_loading_range_ramping());
	memdelete(streamer);
}

} // namespace TestWorldStreamerLoadingRangeRamp
