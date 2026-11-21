/**************************************************************************/
/*  test_world_streamer_auxiliary_readiness.cpp                            */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_auxiliary_readiness)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerAuxiliaryReadiness {

TEST_CASE("[WorldStreamer] Auxiliary source completion queries fail closed") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	CHECK(streamer->get_auxiliary_source_progress() == 0.0);
	CHECK_FALSE(streamer->is_auxiliary_source_ready());
	CHECK(streamer->get_auxiliary_source_pending_count() == 0);
	CHECK(streamer->get_auxiliary_source_failed_count() == 0);

	streamer->set_cell_size(16.0);
	streamer->set_load_radius(24.0);
	streamer->set_focus_position(Vector3(8, 0, 8));
	streamer->set_auxiliary_source(Vector3(600, 0, 8), 200.0);
	CHECK_FALSE(streamer->is_auxiliary_source_ready());
	CHECK(streamer->get_auxiliary_source_progress() == 0.0);
	CHECK(streamer->get_auxiliary_source_pending_count() == 0);

	streamer->set_auxiliary_source(Vector3(40, 0, 8), 12.0);
	CHECK(streamer->get_auxiliary_source_pending_count() > 0);
	CHECK(streamer->get_auxiliary_source_pending_count() <= 64);
	CHECK(streamer->get_auxiliary_source_progress(true) == 0.0);
	CHECK_FALSE(streamer->is_auxiliary_source_ready(true));
	CHECK(streamer->get_auxiliary_source_failed_count() == 0);

	streamer->set_enabled(false);
	CHECK_FALSE(streamer->is_auxiliary_source_ready());
	CHECK(streamer->get_auxiliary_source_pending_count() == 0);
	streamer->set_enabled(true);
	streamer->clear_auxiliary_source();
	CHECK_FALSE(streamer->is_auxiliary_source_ready());
	CHECK(streamer->get_auxiliary_source_progress() == 0.0);
	memdelete(streamer);
}

} // namespace TestWorldStreamerAuxiliaryReadiness
