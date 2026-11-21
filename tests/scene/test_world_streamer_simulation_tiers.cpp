/**************************************************************************/
/*  test_world_streamer_simulation_tiers.cpp                               */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_simulation_tiers)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerSimulationTiers {

TEST_CASE("[WorldStreamer] Simulation tiers are opt-in and have bounded settings") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	CHECK(streamer->get_simulation_radius() == -1.0);
	CHECK(streamer->get_simulation_hysteresis() == 16.0);
	CHECK(streamer->get_max_simulation_transitions_per_update() == 4);
	CHECK(streamer->get_simulation_active_count() == 0);
	CHECK_FALSE(streamer->is_cell_simulation_active(Vector3i(42, 0, 42)));

	streamer->set_simulation_radius(110.0);
	CHECK(streamer->get_simulation_radius() == 110.0);
	streamer->set_simulation_radius(-10.0);
	CHECK(streamer->get_simulation_radius() == -1.0);
	streamer->set_simulation_radius(200000.0);
	CHECK(streamer->get_simulation_radius() == 100000.0);

	streamer->set_simulation_hysteresis(-100.0);
	CHECK(streamer->get_simulation_hysteresis() == 0.0);
	streamer->set_simulation_hysteresis(2000.0);
	CHECK(streamer->get_simulation_hysteresis() == 1000.0);

	streamer->set_max_simulation_transitions_per_update(0);
	CHECK(streamer->get_max_simulation_transitions_per_update() == 1);
	streamer->set_max_simulation_transitions_per_update(100);
	CHECK(streamer->get_max_simulation_transitions_per_update() == 64);
	memdelete(streamer);
}

} // namespace TestWorldStreamerSimulationTiers
