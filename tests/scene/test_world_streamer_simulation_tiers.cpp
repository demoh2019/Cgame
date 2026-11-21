/**************************************************************************/
/*  test_world_streamer_simulation_tiers.cpp                               */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_simulation_tiers)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerSimulationTiers {

TEST_CASE("[WorldStreamer] Named cosmetic simulation layers are bounded and default enabled") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	CHECK(streamer->get_simulation_layer_count() == 0);
	CHECK(streamer->is_simulation_layer_enabled("SurfaceCosmetics"));
	CHECK(streamer->get_cell_simulation_layer(Vector3i(0, 0, 0)).is_empty());
	CHECK(streamer->set_simulation_layer_enabled("SurfaceCosmetics", false));
	CHECK_FALSE(streamer->is_simulation_layer_enabled("SurfaceCosmetics"));
	CHECK(streamer->set_simulation_layer_enabled("SurfaceCosmetics", false)); // No-op.
	CHECK(streamer->get_simulation_layer_count() == 1);
	CHECK(streamer->set_simulation_layer_enabled("SurfaceCosmetics", true));
	CHECK(streamer->is_simulation_layer_enabled("SurfaceCosmetics"));
	CHECK(streamer->get_simulation_layer_count() == 1);
	// The namespace limit prevents untrusted scripts from growing a global table.
	for (int i = 0; i < 15; i++) {
		const String name = String("Layer_") + itos(i);
		CHECK(streamer->set_simulation_layer_enabled(StringName(name), true));
	}
	CHECK(streamer->get_simulation_layer_count() == 16);
	CHECK_FALSE(streamer->set_simulation_layer_enabled("Layer_TooMany", false));
	CHECK(streamer->get_simulation_layer_count() == 16);
	CHECK(streamer->set_simulation_layer_enabled("SurfaceCosmetics", false));
	CHECK_FALSE(streamer->is_simulation_layer_enabled("SurfaceCosmetics"));
	CHECK(streamer->set_simulation_layer_enabled("SurfaceCosmetics", true));
	CHECK(streamer->is_simulation_layer_enabled("SurfaceCosmetics"));
	CHECK_FALSE(streamer->set_simulation_layer_enabled(StringName(), false));
	CHECK_FALSE(streamer->set_simulation_layer_enabled("..", false));
	CHECK_FALSE(streamer->set_simulation_layer_enabled(".Unsafe", false));
	CHECK_FALSE(streamer->set_simulation_layer_enabled("Unsafe.", false));
	CHECK(streamer->get_simulation_layer_count() == 16);
	memdelete(streamer);
}

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
