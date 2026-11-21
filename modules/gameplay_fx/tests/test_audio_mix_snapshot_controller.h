/**************************************************************************/
/*  test_audio_mix_snapshot_controller.h                                   */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "../audio_mix_snapshot_controller.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestAudioMixSnapshotController {

TEST_CASE("[AudioMixSnapshot] parallel bus stages and reversible fades") {
	Ref<AudioMixSnapshotController> mixes;
	mixes.instantiate();
	Dictionary cavern;
	cavern[StringName("Music")] = -4.0;
	cavern[StringName("Ambience")] = -5.0;
	CHECK(mixes->activate_mix("Zone.Underground", cavern, 2.0));
	CHECK(mixes->get_bus_offset_db("Music") == 0.0);
	mixes->tick(0.5);
	CHECK(mixes->get_mix_weight("Zone.Underground") == doctest::Approx(0.25));
	CHECK(mixes->get_bus_offset_db("Music") == doctest::Approx(-1.0));
	CHECK(mixes->get_bus_offset_db("Ambience") == doctest::Approx(-1.25));
	Dictionary storm;
	storm[StringName("Music")] = -2.0;
	storm[StringName("SFX")] = -1.0;
	CHECK(mixes->activate_mix("Weather.Storm", storm, 1.0));
	mixes->tick(0.5);
	CHECK(mixes->get_bus_offset_db("Music") == doctest::Approx(-3.0));
	CHECK(mixes->get_bus_offset_db("SFX") == doctest::Approx(-0.5));
	CHECK(mixes->deactivate_mix("Zone.Underground", 1.0));
	mixes->tick(0.25);
	CHECK(mixes->get_bus_offset_db("Music") == doctest::Approx(-2.5));
	CHECK(mixes->get_mix_count() == 2);
	CHECK(mixes->activate_mix("Zone.Underground", cavern, 1.0));
	CHECK(mixes->get_mix_count() == 2); // Reversing a fade never duplicates.
	mixes->tick(0.75);
	CHECK(mixes->get_mix_weight("Zone.Underground") == doctest::Approx(1.0));
	CHECK(mixes->get_bus_offset_db("Music") == doctest::Approx(-6.0));
	CHECK(mixes->deactivate_mix("Zone.Underground", 0.0));
	CHECK(mixes->get_bus_offset_db("Music") == doctest::Approx(-2.0));
	mixes->clear();
	CHECK(mixes->get_mix_count() == 0);
	CHECK(mixes->get_bus_offset_db("Music") == 0.0);
}

TEST_CASE("[AudioMixSnapshot] atomic validation, saturation and bounded capacity") {
	Ref<AudioMixSnapshotController> mixes;
	mixes.instantiate();
	Dictionary valid;
	valid[StringName("Music")] = -4.0;
	CHECK(mixes->activate_mix("Zone.Forest", valid, 0.0));
	CHECK(mixes->get_bus_offset_db("Music") == -4.0);
	CHECK_FALSE(mixes->activate_mix("", valid));
	CHECK_FALSE(mixes->activate_mix("Invalid", Dictionary()));
	CHECK_FALSE(mixes->activate_mix("Invalid", valid, Math::NaN));
	CHECK_FALSE(mixes->activate_mix("Invalid", valid, -1.0));
	CHECK_FALSE(mixes->activate_mix("Invalid", valid, 16.0));
	Dictionary invalid;
	invalid[StringName("Music")] = Math::NaN;
	CHECK_FALSE(mixes->activate_mix("Zone.Forest", invalid));
	invalid[StringName("Music")] = 1.0;
	CHECK_FALSE(mixes->activate_mix("Zone.Forest", invalid));
	invalid[StringName("Music")] = -31.0;
	CHECK_FALSE(mixes->activate_mix("Zone.Forest", invalid));
	invalid[StringName("Music")] = "too loud";
	CHECK_FALSE(mixes->activate_mix("Zone.Forest", invalid));
	CHECK(mixes->get_bus_offset_db("Music") == -4.0);
	CHECK(mixes->get_mix_count() == 1);
	CHECK_FALSE(mixes->deactivate_mix("Zone.Forest", -1.0));
	CHECK_FALSE(mixes->deactivate_mix("Missing", 1.0));
	mixes->tick(Math::NaN);
	mixes->tick(-4.0);
	CHECK(mixes->get_bus_offset_db("Music") == -4.0);

	Dictionary heavy;
	heavy[StringName("Music")] = -30.0;
	for (int i = 0; i < 15; ++i) {
		CHECK(mixes->activate_mix(StringName(String("Extra") + itos(i)), heavy, 0.0));
	}
	CHECK(mixes->get_mix_count() == 16);
	CHECK(mixes->get_bus_offset_db("Music") == -60.0);
	CHECK_FALSE(mixes->activate_mix("Overflow", heavy, 0.0));
	CHECK(mixes->activate_mix("Zone.Forest", valid, 0.0)); // Reconfigure allowed at capacity.
	CHECK(mixes->get_mix_count() == 16);
}

} // namespace TestAudioMixSnapshotController
