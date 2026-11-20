/**************************************************************************/
/*  test_skin_subsurface.cpp                                              */
/**************************************************************************/
/*  This file is part of: GODOT ENGINE                                    */
/*  Distributed under the MIT license, as in the rest of the engine.      */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_skin_subsurface)

#include "scene/resources/material.h"

namespace TestSkinSubsurface {

TEST_CASE("[SceneTree][BaseMaterial3D] Native SSS skin preset is atomic and idempotent") {
	Ref<StandardMaterial3D> skin;
	skin.instantiate();
	skin->set_roughness(0.65f);
	skin->set_metallic(0.02f);
	skin->set_albedo(Color(0.73f, 0.52f, 0.40f, 1.0f));

	CHECK_FALSE(skin->get_feature(BaseMaterial3D::FEATURE_SUBSURFACE_SCATTERING));
	CHECK_FALSE(skin->get_flag(BaseMaterial3D::FLAG_SUBSURFACE_MODE_SKIN));

	skin->configure_skin_subsurface(true, 0.29f);
	CHECK(skin->get_feature(BaseMaterial3D::FEATURE_SUBSURFACE_SCATTERING));
	CHECK(skin->get_flag(BaseMaterial3D::FLAG_SUBSURFACE_MODE_SKIN));
	CHECK(skin->get_subsurface_scattering_strength() == doctest::Approx(0.29f));
	CHECK(skin->get_roughness() == doctest::Approx(0.65f));
	CHECK(skin->get_metallic() == doctest::Approx(0.02f));
	CHECK(skin->get_albedo() == Color(0.73f, 0.52f, 0.40f, 1.0f));

	// Repeated GraphicsQuality applies must not queue more shader work.
	skin->configure_skin_subsurface(true, 0.29f);
	skin->configure_skin_subsurface(true, 0.19f);
	CHECK(skin->get_subsurface_scattering_strength() == doctest::Approx(0.19f));
	CHECK(skin->get_feature(BaseMaterial3D::FEATURE_SUBSURFACE_SCATTERING));

	ERR_PRINT_OFF;
	skin->configure_skin_subsurface(true, Math::INF);
	skin->configure_skin_subsurface(true, -1.0f);
	skin->configure_skin_subsurface(true, 1.5f);
	ERR_PRINT_ON;
	// Invalid input must not partially change flags or brightness.
	CHECK(skin->get_subsurface_scattering_strength() == doctest::Approx(0.19f));
	CHECK(skin->get_flag(BaseMaterial3D::FLAG_SUBSURFACE_MODE_SKIN));

	skin->configure_skin_subsurface(false, 0.0f);
	CHECK_FALSE(skin->get_feature(BaseMaterial3D::FEATURE_SUBSURFACE_SCATTERING));
	CHECK_FALSE(skin->get_flag(BaseMaterial3D::FLAG_SUBSURFACE_MODE_SKIN));
	CHECK(skin->get_subsurface_scattering_strength() == doctest::Approx(0.0f));
	CHECK(skin->get_roughness() == doctest::Approx(0.65f));
}

} // namespace TestSkinSubsurface
