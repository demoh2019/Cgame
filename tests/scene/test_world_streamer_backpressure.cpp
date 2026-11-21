/**************************************************************************/
/*  test_world_streamer_backpressure.cpp                                  */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_backpressure)

#include "scene/main/world_streamer.h"

#include <limits>

namespace TestWorldStreamerBackpressure {

TEST_CASE("[WorldStreamer] Adaptive chunk frame pressure is bounded and recovers") {
	double pressure = 0.0;
	for (int i = 0; i < 6; ++i) {
		pressure = WorldStreamer::advance_chunk_pressure(pressure, 0.040);
	}
	CHECK(pressure > 0.9);
	CHECK(pressure <= 1.0);
	for (int i = 0; i < 25; ++i) {
		pressure = WorldStreamer::advance_chunk_pressure(pressure, 0.016);
	}
	CHECK(pressure == doctest::Approx(0.0));
	CHECK(WorldStreamer::advance_chunk_pressure(0.7, 0.025) == doctest::Approx(0.7));
	CHECK(WorldStreamer::advance_chunk_pressure(0.7, 0.0) == doctest::Approx(0.7));
	CHECK(WorldStreamer::advance_chunk_pressure(0.7, std::numeric_limits<double>::infinity()) == doctest::Approx(0.7));
	CHECK(WorldStreamer::advance_chunk_pressure(std::numeric_limits<double>::quiet_NaN(), 0.025) == 0.0);
	CHECK(WorldStreamer::advance_chunk_pressure(-5.0, 0.036) >= 0.0);
	CHECK(WorldStreamer::advance_chunk_pressure(5.0, 0.036) <= 1.0);
}

TEST_CASE("[WorldStreamer] Effective slots and time budgets never exceed configured limits") {
	CHECK(WorldStreamer::calculate_adaptive_instantiation_slots(3, 0.0) == 3);
	CHECK(WorldStreamer::calculate_adaptive_instantiation_slots(3, 0.39) == 3);
	CHECK(WorldStreamer::calculate_adaptive_instantiation_slots(3, 0.4) == 2);
	CHECK(WorldStreamer::calculate_adaptive_instantiation_slots(3, 0.8) == 1);
	CHECK(WorldStreamer::calculate_adaptive_instantiation_slots(1, 0.99) == 1);
	CHECK(WorldStreamer::calculate_adaptive_chunk_work_usec(2500, 0.0) == 2500);
	CHECK(WorldStreamer::calculate_adaptive_chunk_work_usec(2500, 0.4) == 1875);
	CHECK(WorldStreamer::calculate_adaptive_chunk_work_usec(2500, 0.8) == 1250);
	CHECK(WorldStreamer::calculate_adaptive_chunk_work_usec(100, 1.0) == 100);
	CHECK(WorldStreamer::calculate_adaptive_chunk_work_usec(0, 1.0) == 0);
	CHECK(WorldStreamer::calculate_adaptive_chunk_work_usec(-1, 1.0) == 0);
	CHECK(WorldStreamer::calculate_adaptive_instantiation_slots(3, std::numeric_limits<double>::quiet_NaN()) == 3);
}

TEST_CASE("[WorldStreamer] Frame pressure scales unload cleanup without starvation") {
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(0, 1.0) == 0);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(-10, 1.0) == 0);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(12, 0.39) == 12);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(12, 0.4) == 9);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(12, 0.8) == 6);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(48, 0.8) == 24);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(1, 1.0) == 1);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(2, 0.8) == 1);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(200, 0.8) == 32);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(12, std::numeric_limits<double>::quiet_NaN()) == 12);
	CHECK(WorldStreamer::calculate_adaptive_unload_slots(12, std::numeric_limits<double>::infinity()) == 12);
}

TEST_CASE("[WorldStreamer] Adaptive backpressure is opt-in and reversible") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	streamer->set_max_instantiations_per_frame(3);
	streamer->set_max_chunk_work_usec(2500);
	CHECK_FALSE(streamer->is_adaptive_chunk_budget_enabled());
	CHECK(streamer->get_effective_instantiations_per_frame() == 3);
	CHECK(streamer->get_effective_chunk_work_usec() == 2500);
	CHECK(streamer->get_last_frame_chunk_attempt_count() == 0);
	CHECK(streamer->get_last_frame_chunk_work_usec() == 0);
	streamer->set_adaptive_chunk_budget_enabled(true);
	CHECK(streamer->is_adaptive_chunk_budget_enabled());
	CHECK(streamer->get_effective_instantiations_per_frame() == 3);
	streamer->set_adaptive_chunk_budget_enabled(false);
	CHECK(streamer->get_streaming_frame_pressure_percent() == 0.0);
	CHECK(streamer->get_effective_chunk_work_usec() == 2500);
	memdelete(streamer);
}

TEST_CASE("[WorldStreamer] Predictive cell admission is opt-in and bounded") {
	WorldStreamer *s = memnew(WorldStreamer);
	CHECK_FALSE(s->is_predictive_chunk_work_budget_enabled());
	CHECK(s->get_estimated_generator_work_usec() == 0);
	CHECK(s->get_estimated_finalization_work_usec() == 0);
	CHECK(s->get_last_predicted_deferred_chunk_count() == 0);
	s->set_predictive_chunk_work_budget_enabled(true);
	CHECK(s->is_predictive_chunk_work_budget_enabled());
	s->set_max_chunk_work_usec(2500);
	CHECK_FALSE(WorldStreamer::should_defer_predicted_chunk_work(2500, 0, 2000, 2000));
	CHECK_FALSE(WorldStreamer::should_defer_predicted_chunk_work(0, 1, 2000, 2000));
	CHECK_FALSE(WorldStreamer::should_defer_predicted_chunk_work(2500, 1, 400, 0));
	CHECK_FALSE(WorldStreamer::should_defer_predicted_chunk_work(2500, 1, 400, 1800));
	CHECK(WorldStreamer::should_defer_predicted_chunk_work(2500, 1, 1600, 1200));
	CHECK(WorldStreamer::should_defer_predicted_chunk_work(2500, 1, 2500, 1));
	CHECK(WorldStreamer::should_defer_predicted_chunk_work(2500, 1, 999999999999LL, 999999999999LL));
	CHECK(WorldStreamer::update_chunk_work_estimate(0, 1600) == 1600);
	CHECK(WorldStreamer::update_chunk_work_estimate(1600, 800) == 1400);
	CHECK(WorldStreamer::update_chunk_work_estimate(1400, 0) == 1400);
	CHECK(WorldStreamer::update_chunk_work_estimate(0, 100000000) == 1000000);
	CHECK(WorldStreamer::update_chunk_work_estimate(-100, -30) == 0);
	CHECK(WorldStreamer::update_chunk_work_estimate(100000000, 100000000) == 1000000);
	s->set_chunk_generator(Callable()); // Changing the callback clears learned generator costs.
	CHECK(s->get_estimated_generator_work_usec() == 0);
	s->set_predictive_chunk_work_budget_enabled(false);
	CHECK_FALSE(s->is_predictive_chunk_work_budget_enabled());
	memdelete(s);
}

} // namespace TestWorldStreamerBackpressure
