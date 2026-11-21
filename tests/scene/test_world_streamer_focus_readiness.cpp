/**************************************************************************/
/*  test_world_streamer_focus_readiness.cpp                               */
/**************************************************************************/
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_focus_readiness)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerFocusReadiness {

TEST_CASE("[WorldStreamer] focus completion reports bounded pending and fails closed") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	streamer->set_cell_size(64.0);
	streamer->set_axes(WorldStreamer::AXES_XZ);
	streamer->set_load_radius(0.0);
	streamer->set_focus_position(Vector3(8, 0, 8));

	Dictionary status = streamer->get_focus_streaming_status();
	CHECK(int(status["total"]) == 1);
	CHECK(int(status["pending"]) == 1);
	CHECK(int(status["completed"]) == 0);
	CHECK(int(status["failed"]) == 0);
	CHECK_FALSE(bool(status["ready"]));
	CHECK_FALSE(bool(status["truncated"]));
	CHECK(double(status["progress"]) == 0.0);
	CHECK(int(streamer->get_focus_streaming_status(true)["pending"]) == 1);

	streamer->set_load_radius(65.0);
	status = streamer->get_focus_streaming_status();
	CHECK(int(status["total"]) > 1);
	CHECK(int(status["pending"]) == int(status["total"]));
	CHECK_FALSE(bool(status["ready"]));
	CHECK(double(status["progress"]) == 0.0);
	CHECK_FALSE(bool(status["truncated"]));

	streamer->set_focus_position(Vector3(Math::INF, 0, 0));
	status = streamer->get_focus_streaming_status();
	CHECK(int(status["total"]) == 0);
	CHECK_FALSE(bool(status["ready"]));

	streamer->set_focus_position(Vector3(8, 0, 8));
	streamer->set_enabled(false);
	status = streamer->get_focus_streaming_status();
	CHECK(int(status["total"]) == 0);
	CHECK(int(status["pending"]) == 0);
	CHECK_FALSE(bool(status["ready"]));
	CHECK(double(status["progress"]) == 0.0);

	memdelete(streamer);
}

} // namespace TestWorldStreamerFocusReadiness
