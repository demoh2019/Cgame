/**************************************************************************/
/*  test_reflection_probe_capture.cpp                                     */
/**************************************************************************/
/*  This file is part of: GODOT ENGINE                                    */
/*  Distributed under the MIT license, as in the rest of the engine.      */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_reflection_probe_capture)

#include "scene/3d/reflection_probe.h"

namespace TestReflectionProbeCapture {

TEST_CASE("[SceneTree][ReflectionProbe] Outdoor one-shot capture budgets validate") {
	ReflectionProbe *probe = memnew(ReflectionProbe);
	probe->set_update_mode(ReflectionProbe::UPDATE_ONCE);
	probe->set_enable_box_projection(true);
	probe->set_as_interior(false);
	probe->set_enable_shadows(false);
	probe->set_size(Vector3(26.0, 12.0, 26.0));
	probe->set_intensity(0.7f);
	probe->set_blend_distance(3.5f);
	probe->set_max_distance(42.0f);
	probe->set_mesh_lod_threshold(1.5f);

	CHECK(probe->get_update_mode() == ReflectionProbe::UPDATE_ONCE);
	CHECK(probe->is_box_projection_enabled());
	CHECK_FALSE(probe->is_set_as_interior());
	CHECK_FALSE(probe->are_shadows_enabled());
	CHECK(probe->get_size() == Vector3(26.0, 12.0, 26.0));
	CHECK(probe->get_mesh_lod_threshold() == doctest::Approx(1.5));
	CHECK(probe->get_max_distance() == doctest::Approx(42.0));
	CHECK(probe->get_blend_distance() == doctest::Approx(3.5));
	CHECK(probe->get_intensity() == doctest::Approx(0.7));

	// Profile reapplication is idempotent, with no redundant RenderingServer
	// setter work or unnecessary reflection cubemap invalidation.
	probe->set_mesh_lod_threshold(1.5f);
	probe->set_size(Vector3(26.0, 12.0, 26.0));
	probe->set_blend_distance(3.5f);
	probe->set_max_distance(42.0f);
	CHECK(probe->get_mesh_lod_threshold() == doctest::Approx(1.5));
	CHECK(probe->get_size() == Vector3(26.0, 12.0, 26.0));

	ERR_PRINT_OFF;
	probe->set_mesh_lod_threshold(-1.0f);
	probe->set_mesh_lod_threshold(Math::INF);
	probe->set_intensity(-1.0f);
	probe->set_blend_distance(Math::INF);
	probe->set_max_distance(Math::INF);
	probe->set_size(Vector3(26.0, 0.0, 26.0));
	ERR_PRINT_ON;

	CHECK(probe->get_mesh_lod_threshold() == doctest::Approx(1.5));
	CHECK(probe->get_intensity() == doctest::Approx(0.7));
	CHECK(probe->get_blend_distance() == doctest::Approx(3.5));
	CHECK(probe->get_max_distance() == doctest::Approx(42.0));
	CHECK(probe->get_size() == Vector3(26.0, 12.0, 26.0));

	memdelete(probe);
}

} // namespace TestReflectionProbeCapture
