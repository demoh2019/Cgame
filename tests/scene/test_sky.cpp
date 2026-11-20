/**************************************************************************/
/*  test_sky.cpp                                                          */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_sky)

#ifndef _3D_DISABLED

#include "core/config/project_settings.h"
#include "scene/resources/sky.h"
#include "scene/resources/environment.h"
#include "servers/rendering/rendering_server.h"

namespace TestSky {

TEST_CASE("[SceneTree][Sky] Reflection roughness minimum is exposed in ProjectSettings") {
	List<PropertyInfo> properties;
	ProjectSettings::get_singleton()->get_property_list(&properties);
	bool found = false;
	for (const PropertyInfo &property : properties) {
		if (property.name == "rendering/reflections/sky_reflections/roughness_layers") {
			found = true;
			CHECK_EQ(property.hint, PROPERTY_HINT_RANGE);
			CHECK_EQ(property.hint_string, "2,32,1");
			break;
		}
	}
	CHECK(found);
}

TEST_CASE("[SceneTree][Sky] Constructor") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	CHECK(test_sky->get_process_mode() == Sky::PROCESS_MODE_AUTOMATIC);
	CHECK(test_sky->get_radiance_size() == Sky::RADIANCE_SIZE_256);
	CHECK(test_sky->get_material().is_null());
}

TEST_CASE("[SceneTree][Sky] Radiance size setter and getter") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	// Check default.
	CHECK(test_sky->get_radiance_size() == Sky::RADIANCE_SIZE_256);

	test_sky->set_radiance_size(Sky::RADIANCE_SIZE_1024);
	CHECK(test_sky->get_radiance_size() == Sky::RADIANCE_SIZE_1024);

	ERR_PRINT_OFF;
	// Check setting invalid radiance size.
	test_sky->set_radiance_size(Sky::RADIANCE_SIZE_MAX);
	ERR_PRINT_ON;

	CHECK(test_sky->get_radiance_size() == Sky::RADIANCE_SIZE_1024);
}

TEST_CASE("[SceneTree][Sky] Process mode setter and getter") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	// Check default.
	CHECK(test_sky->get_process_mode() == Sky::PROCESS_MODE_AUTOMATIC);

	test_sky->set_process_mode(Sky::PROCESS_MODE_INCREMENTAL);
	CHECK(test_sky->get_process_mode() == Sky::PROCESS_MODE_INCREMENTAL);
}

TEST_CASE("[SceneTree][Sky] Material setter and getter") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	Ref<Material> material;
	material.instantiate();

	SUBCASE("Material passed to the class should remain the same") {
		test_sky->set_material(material);
		CHECK(test_sky->get_material() == material);
	}
	SUBCASE("Material passed many times to the class should remain the same") {
		test_sky->set_material(material);
		test_sky->set_material(material);
		test_sky->set_material(material);
		CHECK(test_sky->get_material() == material);
	}
	SUBCASE("Material rewrite testing") {
		Ref<Material> material1;
		Ref<Material> material2;
		material1.instantiate();
		material2.instantiate();

		test_sky->set_material(material1);
		test_sky->set_material(material2);
		CHECK_MESSAGE(test_sky->get_material() != material1,
				"After rewrite, second material should be in class.");
		CHECK_MESSAGE(test_sky->get_material() == material2,
				"After rewrite, second material should be in class.");
	}

	SUBCASE("Assign same material to two skys") {
		Ref<Sky> sky2;
		sky2.instantiate();

		test_sky->set_material(material);
		sky2->set_material(material);
		CHECK_MESSAGE(test_sky->get_material() == sky2->get_material(),
				"Both skys should have the same material.");
	}

	SUBCASE("Swapping materials between two skys") {
		Ref<Sky> sky2;
		sky2.instantiate();
		Ref<Material> material1;
		Ref<Material> material2;
		material1.instantiate();
		material2.instantiate();

		test_sky->set_material(material1);
		sky2->set_material(material2);
		CHECK(test_sky->get_material() == material1);
		CHECK(sky2->get_material() == material2);

		// Do the swap.
		Ref<Material> temp = test_sky->get_material();
		test_sky->set_material(sky2->get_material());
		sky2->set_material(temp);

		CHECK(test_sky->get_material() == material2);
		CHECK(sky2->get_material() == material1);
	}
}

TEST_CASE("[SceneTree][Sky] Invalid radiance size handling") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	// Attempt to set an invalid radiance size.
	ERR_PRINT_OFF;
	test_sky->set_radiance_size(Sky::RADIANCE_SIZE_MAX);
	ERR_PRINT_ON;

	// Verify that the radiance size remains unchanged.
	CHECK(test_sky->get_radiance_size() == Sky::RADIANCE_SIZE_256);
}

TEST_CASE("[SceneTree][Sky] Process mode variations") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	// Test all process modes.
	const Sky::ProcessMode process_modes[] = {
		Sky::PROCESS_MODE_AUTOMATIC,
		Sky::PROCESS_MODE_QUALITY,
		Sky::PROCESS_MODE_INCREMENTAL,
		Sky::PROCESS_MODE_REALTIME
	};

	for (Sky::ProcessMode mode : process_modes) {
		test_sky->set_process_mode(mode);
		CHECK(test_sky->get_process_mode() == mode);
	}
}

TEST_CASE("[SceneTree][Sky] Radiance size variations") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	// Test all radiance sizes except MAX.
	const Sky::RadianceSize radiance_sizes[] = {
		Sky::RADIANCE_SIZE_32,
		Sky::RADIANCE_SIZE_64,
		Sky::RADIANCE_SIZE_128,
		Sky::RADIANCE_SIZE_256,
		Sky::RADIANCE_SIZE_512,
		Sky::RADIANCE_SIZE_1024,
		Sky::RADIANCE_SIZE_2048
	};

	for (Sky::RadianceSize size : radiance_sizes) {
		test_sky->set_radiance_size(size);
		CHECK(test_sky->get_radiance_size() == size);
	}
}

TEST_CASE("[SceneTree][Sky] Null material handling") {
	Ref<Sky> test_sky;
	test_sky.instantiate();

	SUBCASE("Setting null material") {
		test_sky->set_material(Ref<Material>());
		CHECK(test_sky->get_material().is_null());
	}

	SUBCASE("Overwriting existing material with null") {
		Ref<Material> material;
		material.instantiate();
		test_sky->set_material(material);
		test_sky->set_material(Ref<Material>());

		CHECK(test_sky->get_material().is_null());
	}
}

TEST_CASE("[SceneTree][Sky] RID generation") {
	Ref<Sky> test_sky;
	test_sky.instantiate();
	// Check validity.
	CHECK(!test_sky->get_rid().is_valid());
}


TEST_CASE("[SceneTree][Environment] Filmic AgX and ACES ignore invalid exposure inputs") {
	// Environment needs a real RenderingServer RID, not just a math singleton.
	if (RenderingServer::get_singleton() == nullptr) {
		return;
	}
	Ref<Environment> scene_environment;
	scene_environment.instantiate();

	scene_environment->set_tonemapper(Environment::TONE_MAPPER_AGX);
	CHECK(scene_environment->get_tonemapper() == Environment::TONE_MAPPER_AGX);
	scene_environment->set_tonemap_exposure(0.91f);
	CHECK(scene_environment->get_tonemap_exposure() == 0.91f);
	scene_environment->set_tonemap_exposure(-2.0f);
	CHECK(scene_environment->get_tonemap_exposure() == 0.91f);
	scene_environment->set_tonemap_exposure(0.91f);
	CHECK(scene_environment->get_tonemap_exposure() == 0.91f);

	scene_environment->set_tonemap_agx_white(12.5f);
	scene_environment->set_tonemap_agx_contrast(1.2f);
	CHECK(scene_environment->get_tonemap_agx_white() == 12.5f);
	CHECK(scene_environment->get_tonemap_agx_contrast() == 1.2f);
	scene_environment->set_tonemap_agx_white(-5.0f);
	scene_environment->set_tonemap_agx_contrast(-2.0f);
	CHECK(scene_environment->get_tonemap_agx_white() == 12.5f);
	CHECK(scene_environment->get_tonemap_agx_contrast() == 1.2f);

	scene_environment->set_tonemapper(Environment::TONE_MAPPER_ACES);
	scene_environment->set_tonemap_white(6.0f);
	scene_environment->set_tonemap_white(-1.0f);
	CHECK(scene_environment->get_tonemap_white() == 6.0f);
	CHECK(scene_environment->get_tonemapper() == Environment::TONE_MAPPER_ACES);
}

TEST_CASE("[SceneTree][Environment] Indirect volumetric light injection is bounded and idempotent") {
	if (RenderingServer::get_singleton() == nullptr) {
		return;
	}
	Ref<Environment> env;
	env.instantiate();

	// A conservative Ultra blend adds SDFGI light to existing froxels.
	env->set_volumetric_fog_gi_inject(0.24f);
	CHECK(env->get_volumetric_fog_gi_inject() == 0.24f);
	env->set_volumetric_fog_gi_inject(0.24f); // No redundant renderer update.
	CHECK(env->get_volumetric_fog_gi_inject() == 0.24f);

	// Bad authoring inputs never replace the current GPU GI strength.
	env->set_volumetric_fog_gi_inject(-0.2f);
	CHECK(env->get_volumetric_fog_gi_inject() == 0.24f);
	env->set_volumetric_fog_gi_inject(0.0f);
	CHECK(env->get_volumetric_fog_gi_inject() == 0.0f);
	CHECK(env->get_volumetric_fog_ambient_inject() == 0.0f);
}

TEST_CASE("[SceneTree][Environment] Volumetric fog history is finite and bounded") {
	if (RenderingServer::get_singleton() == nullptr) {
		return;
	}
	Ref<Environment> scene_environment;
	scene_environment.instantiate();
	scene_environment->set_volumetric_fog_temporal_reprojection_amount(0.66f);
	CHECK(scene_environment->get_volumetric_fog_temporal_reprojection_amount() == 0.66f);
	scene_environment->set_volumetric_fog_temporal_reprojection_amount(2.0f);
	CHECK(scene_environment->get_volumetric_fog_temporal_reprojection_amount() == 1.0f);
	scene_environment->set_volumetric_fog_temporal_reprojection_amount(-0.5f);
	CHECK(scene_environment->get_volumetric_fog_temporal_reprojection_amount() == 0.0f);
	scene_environment->set_volumetric_fog_temporal_reprojection_amount(0.74f);
	scene_environment->set_volumetric_fog_temporal_reprojection_amount(0.74f);
	CHECK(scene_environment->get_volumetric_fog_temporal_reprojection_amount() == 0.74f);
	scene_environment->set_volumetric_fog_density(0.008f);
	scene_environment->set_volumetric_fog_density(-1.0f);
	CHECK(scene_environment->get_volumetric_fog_density() == 0.008f);
	scene_environment->set_volumetric_fog_detail_spread(2.35f);
	scene_environment->set_volumetric_fog_detail_spread(2.35f);
	CHECK(scene_environment->get_volumetric_fog_detail_spread() == 2.35f);
	scene_environment->set_volumetric_fog_enabled(true);
	scene_environment->set_volumetric_fog_enabled(true);
	CHECK(scene_environment->is_volumetric_fog_enabled());
	scene_environment->set_volumetric_fog_temporal_reprojection_enabled(false);
	scene_environment->set_volumetric_fog_temporal_reprojection_enabled(false);
	CHECK(!scene_environment->is_volumetric_fog_temporal_reprojection_enabled());
}

TEST_CASE("[SceneTree][Environment] Dungeon SDFGI visibility is atomic and reversible") {
	if (RenderingServer::get_singleton() == nullptr) {
		return;
	}
	Ref<Environment> env;
	env.instantiate();

	// Outdoor profile avoids occlusion artifacts and reads the sky.
	env->configure_sdfgi_visibility(false, true, 1.1f, 1.1f);
	CHECK(!env->is_sdfgi_using_occlusion());
	CHECK(env->is_sdfgi_reading_sky_light());
	CHECK(env->get_sdfgi_normal_bias() == 1.1f);
	CHECK(env->get_sdfgi_probe_bias() == 1.1f);

	// In an enclosed dungeon, occlusion rays reject leaks through walls.
	// Disable the sky contribution at the same time, without rendering
	// four intermediate incomplete states.
	env->configure_sdfgi_visibility(true, false, 0.95f, 0.95f);
	CHECK(env->is_sdfgi_using_occlusion());
	CHECK(!env->is_sdfgi_reading_sky_light());
	CHECK(env->get_sdfgi_normal_bias() == 0.95f);
	CHECK(env->get_sdfgi_probe_bias() == 0.95f);
	env->configure_sdfgi_visibility(true, false, 0.95f, 0.95f);

	// Bad samples do not mutate a subset of the renderer's GI settings.
	ERR_PRINT_OFF;
	env->configure_sdfgi_visibility(false, true, -0.1f, 1.1f);
	env->configure_sdfgi_visibility(false, true, 1.1f, -0.1f);
	env->configure_sdfgi_visibility(false, true, 4.1f, 1.1f);
	env->configure_sdfgi_visibility(false, true, 1.1f, 4.1f);
	ERR_PRINT_ON;
	CHECK(env->is_sdfgi_using_occlusion());
	CHECK(!env->is_sdfgi_reading_sky_light());
	CHECK(env->get_sdfgi_normal_bias() == 0.95f);
	CHECK(env->get_sdfgi_probe_bias() == 0.95f);

	// Exiting to the open world immediately releases the extra rays.
	env->configure_sdfgi_visibility(false, true, 1.1f, 1.1f);
	CHECK(!env->is_sdfgi_using_occlusion());
	CHECK(env->is_sdfgi_reading_sky_light());
}

TEST_CASE("[SceneTree][Environment] SDFGI quality profile is atomic and validated") {
	if (RenderingServer::get_singleton() == nullptr) {
		return;
	}
	Ref<Environment> env;
	env.instantiate();

	// One native call enables two local cascades. Repeated Auto quality
	// applications must not re-upload unchanged settings to the renderer.
	env->configure_sdfgi(true, 2, 0.5f, true, 0.32f, 0.72f);
	CHECK(env->is_sdfgi_enabled());
	CHECK(env->get_sdfgi_cascades() == 2);
	CHECK(env->get_sdfgi_min_cell_size() == 0.5f);
	CHECK(env->is_sdfgi_reading_sky_light());
	CHECK(env->get_sdfgi_bounce_feedback() == 0.32f);
	CHECK(env->get_sdfgi_energy() == 0.72f);
	env->configure_sdfgi(true, 2, 0.5f, true, 0.32f, 0.72f);

	// Invalid input fails as a transaction: no halfway-enabled GI or
	// cascades changed by an invalid graphics preset.
	ERR_PRINT_OFF;
	env->configure_sdfgi(false, 0, 0.5f, false, 0.1f, 0.1f);
	env->configure_sdfgi(false, 2, -1.0f, false, 0.1f, 0.1f);
	env->configure_sdfgi(false, 2, 0.5f, false, 1.2f, 0.1f);
	env->configure_sdfgi(false, 2, 0.5f, false, 0.1f, -0.1f);
	ERR_PRINT_ON;
	CHECK(env->is_sdfgi_enabled());
	CHECK(env->get_sdfgi_cascades() == 2);
	CHECK(env->get_sdfgi_energy() == 0.72f);

	// On a renderer switch, one operation clears SDFGI while keeping a
	// valid profile ready for a later return to Ultra.
	env->configure_sdfgi(false, 2, 0.5f, true, 0.32f, 0.72f);
	CHECK(!env->is_sdfgi_enabled());
}

} // namespace TestSky

#endif // _3D_DISABLED
