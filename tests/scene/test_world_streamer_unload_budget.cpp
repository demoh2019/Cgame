/**************************************************************************/
/*  test_world_streamer_unload_budget.cpp                                  */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_unload_budget)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerUnloadBudget {

TEST_CASE("[WorldStreamer] Unload cleanup budget is opt-in and bounded") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	CHECK(streamer->get_max_unloads_per_update() == 0);
	CHECK(streamer->get_effective_unloads_per_update() == 0);
	CHECK(streamer->get_last_unload_count() == 0);
	CHECK(streamer->get_last_deferred_unload_count() == 0);

	streamer->set_max_unloads_per_update(-1000);
	CHECK(streamer->get_max_unloads_per_update() == 0);
	streamer->set_max_unloads_per_update(1000);
	CHECK(streamer->get_max_unloads_per_update() == 64);
	streamer->set_max_unloads_per_update(2);
	CHECK(streamer->get_max_unloads_per_update() == 2);
	CHECK(streamer->get_effective_unloads_per_update() == 2);
	streamer->set_adaptive_chunk_budget_enabled(true);
	CHECK(streamer->get_effective_unloads_per_update() == 2);
	streamer->set_adaptive_chunk_budget_enabled(false);
	streamer->set_max_unloads_per_update(2);
	CHECK(streamer->get_max_unloads_per_update() == 2);
	streamer->unload_all();
	CHECK(streamer->get_last_unload_count() == 0);
	CHECK(streamer->get_last_deferred_unload_count() == 0);
	memdelete(streamer);
}

} // namespace TestWorldStreamerUnloadBudget
