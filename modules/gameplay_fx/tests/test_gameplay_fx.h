/**************************************************************************/
/*  test_gameplay_fx.h                                                  */
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
#pragma once

#include "../audio_duck_mix.h"
#include "../gameplay_attribute_set.h"
#include "../gameplay_cooldown_tracker.h"
#include "../gameplay_cue_queue.h"
#include "../gameplay_effect_timeline.h"
#include "../radial_force_field_3d.h"
#include "../sound_concurrency.h"

#include "tests/test_macros.h"

namespace TestGameplayFX {

typedef SoundConcurrency::Voice Voice;

static Voice make_voice(uint64_t p_start, float p_distance, float p_volume) {
	Voice v;
	v.start_msec = p_start;
	v.distance = p_distance;
	v.volume = p_volume;
	return v;
}

TEST_CASE("[GameplayFX] SoundConcurrency::pick_victim") {
	const Voice voices[3] = {
		make_voice(200, 5.0f, 0.5f),
		make_voice(100, 20.0f, 1.0f),
		make_voice(300, 10.0f, 0.2f),
	};

	SUBCASE("Stop oldest picks the smallest start time") {
		CHECK(SoundConcurrency::pick_victim(voices, 3, SoundConcurrency::RESOLUTION_STOP_OLDEST, 1.0f, 1.0f) == 1);
	}
	SUBCASE("Stop farthest picks the most distant voice when the new one is closer") {
		CHECK(SoundConcurrency::pick_victim(voices, 3, SoundConcurrency::RESOLUTION_STOP_FARTHEST, 2.0f, 1.0f) == 1);
	}
	SUBCASE("Stop farthest rejects a new sound that is farther than every voice") {
		CHECK(SoundConcurrency::pick_victim(voices, 3, SoundConcurrency::RESOLUTION_STOP_FARTHEST, 50.0f, 1.0f) == SoundConcurrency::VICTIM_REJECT_NEW);
	}
	SUBCASE("Stop quietest picks the lowest volume when the new one is louder") {
		CHECK(SoundConcurrency::pick_victim(voices, 3, SoundConcurrency::RESOLUTION_STOP_QUIETEST, 1.0f, 0.9f) == 2);
	}
	SUBCASE("Stop quietest rejects a new sound that is quieter than every voice") {
		CHECK(SoundConcurrency::pick_victim(voices, 3, SoundConcurrency::RESOLUTION_STOP_QUIETEST, 1.0f, 0.05f) == SoundConcurrency::VICTIM_REJECT_NEW);
	}
	SUBCASE("Prevent new always rejects") {
		CHECK(SoundConcurrency::pick_victim(voices, 3, SoundConcurrency::RESOLUTION_PREVENT_NEW, 1.0f, 1.0f) == SoundConcurrency::VICTIM_REJECT_NEW);
	}
	SUBCASE("Empty voice list rejects") {
		CHECK(SoundConcurrency::pick_victim(nullptr, 0, SoundConcurrency::RESOLUTION_STOP_OLDEST, 1.0f, 1.0f) == SoundConcurrency::VICTIM_REJECT_NEW);
	}
	SUBCASE("Array wrapper matches the struct version") {
		PackedInt64Array starts;
		PackedFloat32Array distances;
		PackedFloat32Array volumes;
		for (int i = 0; i < 3; i++) {
			starts.push_back((int64_t)voices[i].start_msec);
			distances.push_back(voices[i].distance);
			volumes.push_back(voices[i].volume);
		}
		CHECK(SoundConcurrency::pick_victim_arrays(starts, distances, volumes, SoundConcurrency::RESOLUTION_STOP_OLDEST, 1.0f, 1.0f) == 1);
	}
}

TEST_CASE("[GameplayFX] SoundConcurrency::volume_scale_for") {
	CHECK(SoundConcurrency::volume_scale_for(0, 0.5f) == doctest::Approx(1.0f));
	CHECK(SoundConcurrency::volume_scale_for(1, 0.5f) == doctest::Approx(0.5f));
	CHECK(SoundConcurrency::volume_scale_for(3, 0.5f) == doctest::Approx(0.125f));
	CHECK(SoundConcurrency::volume_scale_for(5, 1.0f) == doctest::Approx(1.0f));
}

TEST_CASE("[GameplayFX] SoundConcurrency resource properties") {
	Ref<SoundConcurrency> cc;
	cc.instantiate();
	cc->set_max_count(-3);
	CHECK(cc->get_max_count() == 0);
	cc->set_volume_scale(2.0f);
	CHECK(cc->get_volume_scale() == doctest::Approx(1.0f));
	cc->set_retrigger_interval(-1.0f);
	CHECK(cc->get_retrigger_interval() == doctest::Approx(0.0f));
}

TEST_CASE("[GameplayFX] RadialForceField3D::falloff_scale") {
	typedef RadialForceField3D R;
	CHECK(R::falloff_scale(0.0f, 10.0f, R::FALLOFF_LINEAR) == doctest::Approx(1.0f));
	CHECK(R::falloff_scale(5.0f, 10.0f, R::FALLOFF_LINEAR) == doctest::Approx(0.5f));
	CHECK(R::falloff_scale(10.0f, 10.0f, R::FALLOFF_LINEAR) == doctest::Approx(0.0f));
	CHECK(R::falloff_scale(15.0f, 10.0f, R::FALLOFF_LINEAR) == doctest::Approx(0.0f));
	CHECK(R::falloff_scale(5.0f, 10.0f, R::FALLOFF_QUADRATIC) == doctest::Approx(0.25f));
	CHECK(R::falloff_scale(5.0f, 10.0f, R::FALLOFF_NONE) == doctest::Approx(1.0f));
	CHECK(R::falloff_scale(50.0f, 10.0f, R::FALLOFF_NONE) == doctest::Approx(1.0f));
	CHECK(R::falloff_scale(1.0f, 0.0f, R::FALLOFF_LINEAR) == doctest::Approx(0.0f));
	CHECK(R::falloff_scale(-2.0f, 10.0f, R::FALLOFF_LINEAR) == doctest::Approx(1.0f));
}

TEST_CASE("[GameplayFX] RadialForceField3D::impulse_direction") {
	typedef RadialForceField3D R;
	const Vector3 dir = R::impulse_direction(Vector3(), Vector3(4, 0, 0), 0.0f);
	CHECK(dir.is_equal_approx(Vector3(1, 0, 0)));

	const Vector3 up = R::impulse_direction(Vector3(1, 1, 1), Vector3(1, 1, 1), 0.0f);
	CHECK(up.is_equal_approx(Vector3(0, 1, 0)));

	const Vector3 biased = R::impulse_direction(Vector3(), Vector3(2, 0, 0), 1.0f);
	CHECK(biased.is_normalized());
	CHECK(biased.y > 0.0f);
	CHECK(biased.x > 0.0f);
}

TEST_CASE("[GameplayFX] RadialForceField3D shielding and mass-independent velocity change") {
	typedef RadialForceField3D R;
	R *field = memnew(R);
	CHECK(field->get_occlusion_mask() == 0);
	CHECK(field->is_mass_independent() == false);
	CHECK(field->get_max_occlusion_rays() == 24);
	CHECK(field->get_occlusion_attenuation() == doctest::Approx(0.25f));

	field->set_occlusion_mask(0x3u);
	CHECK(field->get_occlusion_mask() == 0x3u);
	field->set_occlusion_attenuation(2.0f);
	CHECK(field->get_occlusion_attenuation() == doctest::Approx(1.0f));
	field->set_occlusion_attenuation(-1.0f);
	CHECK(field->get_occlusion_attenuation() == doctest::Approx(0.0f));
	field->set_occlusion_attenuation(0.25f);
	field->set_max_occlusion_rays(999);
	CHECK(field->get_max_occlusion_rays() == 64);
	field->set_max_occlusion_rays(-4);
	CHECK(field->get_max_occlusion_rays() == 1);
	field->set_max_occlusion_rays(24);
	field->set_mass_independent(true);
	CHECK(field->is_mass_independent());

	CHECK(R::occlusion_scale(false, 0.25f) == doctest::Approx(1.0f));
	CHECK(R::occlusion_scale(true, 0.25f) == doctest::Approx(0.25f));
	CHECK(R::occlusion_scale(true, -1.0f) == doctest::Approx(0.0f));
	CHECK(R::occlusion_scale(true, 2.0f) == doctest::Approx(1.0f));
	CHECK(R::impulse_magnitude(12.0f, 0.5f, 1.0f, false) == doctest::Approx(6.0f));
	CHECK(R::impulse_magnitude(12.0f, 0.5f, 8.0f, false) == doctest::Approx(6.0f));
	CHECK(R::impulse_magnitude(12.0f, 0.5f, 1.0f, true) == doctest::Approx(6.0f));
	CHECK(R::impulse_magnitude(12.0f, 0.5f, 8.0f, true) == doctest::Approx(48.0f));
	// Constant delta-v across masses; both bodies see the same speed change
	// even though their applied physical impulses have different magnitudes.
	CHECK(R::impulse_magnitude(12.0f, 0.5f, 8.0f, true) / 8.0f ==
			doctest::Approx(R::impulse_magnitude(12.0f, 0.5f, 1.0f, true)));
	memdelete(field);
}

TEST_CASE("[GameplayFX] timeline reapply, explicit tick and expiry") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	CHECK(timeline->set_effect("Status.Stagger", 2.0));
	CHECK(timeline->apply_effect("Status.Poison", 5.0, 2, 4));
	CHECK(timeline->apply_effect("Status.Poison", 3.0, 2, 4, GameplayEffectTimeline::REAPPLY_EXTEND));
	CHECK(timeline->get_stacks("Status.Poison") == 4);
	CHECK(timeline->get_remaining("Status.Poison") == doctest::Approx(8.0));
	CHECK(timeline->apply_effect("Status.Poison", 1.0, 3, 4, GameplayEffectTimeline::REAPPLY_KEEP));
	CHECK(timeline->get_remaining("Status.Poison") == doctest::Approx(8.0));
	CHECK(timeline->apply_effect("Status.Poison", 4.0, 1, 4, GameplayEffectTimeline::REAPPLY_REFRESH));
	CHECK(timeline->get_remaining("Status.Poison") == doctest::Approx(4.0));
	CHECK(timeline->tick(1.5).is_empty());
	CHECK(timeline->get_remaining("Status.Stagger") == doctest::Approx(0.5));
	PackedStringArray expired = timeline->tick(1.0);
	REQUIRE(expired.size() == 1);
	CHECK(expired[0] == "Status.Stagger");
	CHECK(timeline->tick(1.5).size() == 1);
	CHECK(timeline->is_empty());
}
TEST_CASE("[GameplayFX] fused periodic tick and drain is equivalent to legacy two calls") {
	Ref<GameplayEffectTimeline> legacy;
	Ref<GameplayEffectTimeline> fused;
	legacy.instantiate();
	fused.instantiate();
	for (int variant = 0; variant < 2; ++variant) {
		Ref<GameplayEffectTimeline> timeline = variant == 0 ? legacy : fused;
		REQUIRE(timeline->set_effect("Runtime.Status.Sundered", 3.0));
		REQUIRE(timeline->set_effect("Runtime.Status.Resolve", 2.1, 3));
		REQUIRE(timeline->set_effect("Local.Visual.Hit", 0.3));
		REQUIRE(timeline->set_periodic("Runtime.Status.Sundered", 0.75, false));
		REQUIRE(timeline->set_periodic("Runtime.Status.Resolve", 1.1, false));
		REQUIRE(timeline->set_periodic("Local.Visual.Hit", 0.1, true));
	}
	const double steps[] = { 0.04, 0.26, 0.1, 0.5, 0.75, 0.71, 2.1, 5.0 };
	for (int i = 0; i < 8; ++i) {
		const PackedStringArray expired = legacy->tick(steps[i]);
		const Dictionary old_pulses = legacy->take_periodic_pulses();
		const Dictionary new_pulses = fused->tick_and_take_periodic_pulses(steps[i]);
		CHECK(new_pulses == old_pulses);
		CHECK(fused->get_snapshot() == legacy->get_snapshot());
		CHECK(fused->get_effect_count() == legacy->get_effect_count());
		CHECK(fused->get_stacks("Runtime.Status.Resolve") == legacy->get_stacks("Runtime.Status.Resolve"));
		if (i == 1) {
			CHECK(expired.size() == 1);
			CHECK(expired[0] == "Local.Visual.Hit");
			CHECK(new_pulses.get(StringName("Local.Visual.Hit"), 0) == 3);
		}
	}
	CHECK(fused->is_empty());
	CHECK(fused->tick_and_take_periodic_pulses(1.0).is_empty());
}

TEST_CASE("[GameplayFX] fused periodic tick preserves pending aggregation and rejects invalid time") {
	Ref<GameplayEffectTimeline> legacy;
	Ref<GameplayEffectTimeline> fused;
	legacy.instantiate();
	fused.instantiate();
	for (int variant = 0; variant < 2; ++variant) {
		Ref<GameplayEffectTimeline> timeline = variant == 0 ? legacy : fused;
		REQUIRE(timeline->set_effect("Runtime.Status.Resolve", 6.0, 3));
		REQUIRE(timeline->set_periodic("Runtime.Status.Resolve", 0.05, false));
	}
	CHECK(legacy->tick(0.1).is_empty());
	CHECK(fused->tick(0.1).is_empty()); // Pending pulses accumulate before drain.
	CHECK(legacy->tick(Math::NaN).is_empty());
	const Dictionary nan_legacy = legacy->take_periodic_pulses();
	const Dictionary nan_fused = fused->tick_and_take_periodic_pulses(Math::NaN);
	CHECK(nan_fused == nan_legacy);
	CHECK(nan_fused.get(StringName("Runtime.Status.Resolve"), 0) == 2);
	CHECK(fused->get_snapshot() == legacy->get_snapshot());
	CHECK(legacy->tick(4.0).is_empty());
	const Dictionary old_pulses = legacy->take_periodic_pulses();
	const Dictionary new_pulses = fused->tick_and_take_periodic_pulses(4.0);
	CHECK(new_pulses == old_pulses);
	CHECK(new_pulses.get(StringName("Runtime.Status.Resolve"), 0) == GameplayEffectTimeline::MAX_PENDING_PULSES);
	CHECK(fused->get_snapshot() == legacy->get_snapshot());
	CHECK(legacy->tick(-5.0).is_empty());
	CHECK(fused->tick_and_take_periodic_pulses(-5.0).is_empty());
	CHECK(fused->get_snapshot() == legacy->get_snapshot());
	CHECK(legacy->tick(50.0).size() == 1);
	CHECK(fused->tick_and_take_periodic_pulses(50.0) == legacy->take_periodic_pulses());
	CHECK(fused->is_empty());
	CHECK(fused->take_periodic_pulses().is_empty()); // Fused step already drained.
}

TEST_CASE("[GameplayFX] timeline target-tag requirements and immunity are atomic") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	const PackedStringArray alive = { "Runtime.Life.Alive", "Status.Fire.Resistant" };
	const PackedStringArray required = { "Runtime.Life" };
	const PackedStringArray blocked = { "Runtime.Life.Dead", "Status.Immune" };
	CHECK(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 2.0, alive, required, blocked, 1, 4));
	CHECK(timeline->get_stacks("Local.Visual.Hit") == 1);
	CHECK(timeline->set_periodic("Local.Visual.Hit", 0.5, false));
	CHECK(timeline->tick(0.2).is_empty());
	const Dictionary baseline = timeline->get_snapshot();

	// Parent requirements match descendants, but partial word prefixes never match.
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 3.0,
			{ "Runtime.Life.Dead" }, { "Runtime.Life.Alive" }, blocked, 1, 4));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 3.0,
			{ "Runtime.Life.Alive", "Status.Immune.Poison" }, required, blocked, 1, 4));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 3.0,
			alive, { "Status.Frozen" }, blocked, 1, 4));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 3.0,
			{ "Runtime.Life.Deadly" }, { "Runtime.Life.Dead" }, {}, 1, 4));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 3.0,
			{ "Runtime..Life.Alive" }, required, blocked, 1, 4));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 3.0,
			alive, { "" }, blocked, 1, 4));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 3.0,
			alive, required, { "Status..Bad" }, 1, 4));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", Math::NaN,
			alive, required, blocked, 1, 4));
	CHECK(timeline->get_snapshot() == baseline);
	CHECK(timeline->get_stacks("Local.Visual.Hit") == 1);
	CHECK(timeline->tick(0.3).is_empty()); // Failed applications leave phase unchanged.
	CHECK(int(timeline->take_periodic_pulses().get(StringName("Local.Visual.Hit"), 0)) == 1);

	// Distinct source prefixes are not mistaken for blocked hierarchy.
	CHECK(timeline->apply_effect_with_tag_requirements("Local.Visual.Hit", 1.0,
			{ "Runtime.Life.Alive", "Status.ImmuneExtra" }, required, blocked, 1, 4));
	CHECK(timeline->get_stacks("Local.Visual.Hit") == 2);
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(1.0));
	PackedStringArray excessive;
	for (int i = 0; i < GameplayEffectTimeline::MAX_ACTIVE_TAG_CONTEXTS + 1; i++) {
		excessive.push_back("Runtime.Life.Alive");
	}
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Extra.Hit", 1.0, excessive, required, blocked));
	excessive.clear();
	for (int i = 0; i < GameplayEffectTimeline::MAX_TAG_REQUIREMENTS + 1; i++) {
		excessive.push_back("Runtime.Life");
	}
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Extra.Hit", 1.0, alive, excessive, blocked));
	CHECK_FALSE(timeline->apply_effect_with_tag_requirements("Extra.Hit", 1.0, alive, required, excessive));
	CHECK_FALSE(timeline->has_effect("Extra.Hit"));
}

TEST_CASE("[GameplayFX] timeline atomic snapshot rollback and validation") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	Dictionary state;
	state["remaining"] = 3.0;
	state["stacks"] = 2;
	Dictionary snapshot;
	snapshot["Status.Resolve"] = state;
	CHECK(timeline->replace_snapshot(snapshot));
	state["stacks"] = 9;
	CHECK(timeline->get_stacks("Status.Resolve") == 2);
	Dictionary copy = timeline->get_snapshot();
	Dictionary copied_state = copy[StringName("Status.Resolve")];
	copied_state["stacks"] = 10;
	CHECK(timeline->get_stacks("Status.Resolve") == 2);
	CHECK_FALSE(timeline->set_effect("Status.Bad", Math::NaN));
	CHECK_FALSE(timeline->apply_effect("Status.Bad", 1.0, -1));
	CHECK(timeline->tick(-5.0).is_empty());
	CHECK(timeline->tick(Math::INF).is_empty());
	Dictionary invalid;
	invalid["Status.Bad"] = copy;
	CHECK_FALSE(timeline->replace_snapshot(invalid));
	Dictionary bad_state;
	bad_state["remaining"] = 2.0;
	bad_state["stacks"] = -1;
	invalid["Status.Bad"] = bad_state;
	CHECK_FALSE(timeline->replace_snapshot(invalid));
	CHECK(timeline->get_stacks("Status.Resolve") == 2);
	Dictionary zero;
	zero["remaining"] = 0.0;
	zero["stacks"] = 1;
	Dictionary cleared;
	cleared["Status.Resolve"] = zero;
	CHECK(timeline->replace_snapshot(cleared));
	CHECK(timeline->is_empty());
}
TEST_CASE("[GameplayFX] timeline periodic pulses preserve phase across snapshots") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	REQUIRE(timeline->set_effect("Status.Sundered", 3.0, 2));
	CHECK(timeline->set_periodic("Status.Sundered", 0.5, false));
	CHECK(timeline->tick(0.3).is_empty());
	CHECK(timeline->take_periodic_pulses().is_empty());
	Dictionary authoritative;
	Dictionary timer;
	timer["remaining"] = 2.7;
	timer["stacks"] = 2;
	authoritative["Status.Sundered"] = timer;
	CHECK(timeline->replace_snapshot(authoritative)); // Must retain the 0.2s phase.
	CHECK(timeline->tick(0.2).is_empty());
	Dictionary pulses = timeline->take_periodic_pulses();
	CHECK(int(pulses.get(StringName("Status.Sundered"), 0)) == 1);
	CHECK(timeline->tick(1.1).is_empty());
	pulses = timeline->take_periodic_pulses();
	CHECK(int(pulses.get(StringName("Status.Sundered"), 0)) == 2);
	const Dictionary saved = timeline->get_snapshot();
	Ref<GameplayEffectTimeline> restored;
	restored.instantiate();
	CHECK(restored->replace_snapshot(saved));
	CHECK(restored->get_periodic("Status.Sundered") == doctest::Approx(0.5));
	CHECK(restored->get_remaining("Status.Sundered") == doctest::Approx(1.4));
	CHECK(restored->tick(2.0).size() == 1);
	pulses = restored->take_periodic_pulses();
	CHECK(int(pulses.get(StringName("Status.Sundered"), 0)) == 3);
	CHECK(restored->is_empty());
}

TEST_CASE("[GameplayFX] periodic policy, validation, coalescing, and rollback") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	REQUIRE(timeline->set_effect("Status.Resolve", 100.0));
	CHECK_FALSE(timeline->set_periodic("Status.Resolve", 0.01));
	CHECK_FALSE(timeline->set_periodic("Status.Resolve", Math::NaN));
	CHECK_FALSE(timeline->set_periodic("Missing", 1.0));
	CHECK(timeline->set_periodic("Status.Resolve", 0.1, true));
	CHECK(timeline->tick(0.08).is_empty());
	CHECK(timeline->apply_effect("Status.Resolve", 1.0));
	CHECK(timeline->tick(0.03).is_empty());
	CHECK(timeline->take_periodic_pulses().is_empty()); // Reapply resets phase.
	CHECK(timeline->tick(0.1).is_empty());
	CHECK(int(timeline->take_periodic_pulses().get(StringName("Status.Resolve"), 0)) == 1);
	CHECK(timeline->set_periodic("Status.Resolve", 0.05, false));
	CHECK(timeline->tick(0.8).is_empty());
	CHECK(int(timeline->take_periodic_pulses().get(StringName("Status.Resolve"), 0)) == 16);
	CHECK(timeline->set_effect("Status.Resolve", 100.0));
	CHECK(timeline->tick(10.0).is_empty());
	CHECK(int(timeline->take_periodic_pulses().get(StringName("Status.Resolve"), 0)) == 32); // Bounded.
	Dictionary saved = timeline->get_snapshot();
	Dictionary effect = saved[StringName("Status.Resolve")];
	effect["next_period"] = 1000.0;
	CHECK_FALSE(timeline->replace_snapshot(saved));
	CHECK(timeline->get_remaining("Status.Resolve") == doctest::Approx(90.0));
	CHECK(timeline->get_periodic("Status.Resolve") == doctest::Approx(0.05));
	CHECK(timeline->remove_effect("Status.Resolve"));
	CHECK(timeline->take_periodic_pulses().is_empty());
}

TEST_CASE("[GameplayFX] scoped effect snapshots keep independent periodic pulses") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	CHECK(timeline->set_effect("Local.Visual.Hit", 2.0));
	CHECK(timeline->set_periodic("Local.Visual.Hit", 0.2, false));
	CHECK(timeline->set_effect("Runtime.Status.Staggered", 3.0));
	CHECK(timeline->set_effect("RuntimeExtra.Keep", 5.0, 2));
	CHECK(timeline->set_effect("Runtime.Status.Resolve", 5.0, 2));
	CHECK(timeline->set_periodic("Runtime.Status.Resolve", 1.0, false));
	CHECK(timeline->tick(0.25).is_empty());
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(1.75));

	Dictionary state;
	state["remaining"] = 4.0;
	state["stacks"] = 3;
	Dictionary snapshot;
	snapshot[StringName("Runtime.Status.Resolve")] = state;
	CHECK(timeline->replace_effect_branch("Runtime", snapshot));
	CHECK(timeline->get_remaining("Runtime.Status.Staggered") == 0.0);
	CHECK(timeline->get_remaining("Runtime.Status.Resolve") == doctest::Approx(4.0));
	CHECK(timeline->get_periodic("Runtime.Status.Resolve") == doctest::Approx(1.0));
	CHECK(timeline->get_stacks("Runtime.Status.Resolve") == 3);
	CHECK(timeline->get_remaining("RuntimeExtra.Keep") == doctest::Approx(4.75));
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(1.75));
	Dictionary pulses = timeline->take_periodic_pulses();
	CHECK(pulses.get(StringName("Local.Visual.Hit"), 0) == 1);
	CHECK(pulses.get(StringName("Runtime.Status.Resolve"), 0) == 0);

	const int old_count = timeline->get_effect_count();
	Dictionary invalid = snapshot.duplicate(true);
	invalid[StringName("Elsewhere.Bad")] = state;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	invalid.erase(StringName("Elsewhere.Bad"));
	Dictionary malformed;
	malformed["remaining"] = Math::NaN;
	malformed["stacks"] = 2;
	invalid[StringName("Runtime.Status.Bad")] = malformed;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	malformed["remaining"] = 2.0;
	malformed["stacks"] = 0;
	invalid[StringName("Runtime.Status.Bad")] = malformed;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	malformed["stacks"] = 1;
	malformed["period"] = 0.01;
	invalid[StringName("Runtime.Status.Bad")] = malformed;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	CHECK_FALSE(timeline->replace_effect_branch("Runtime..Invalid", snapshot));
	CHECK(timeline->get_effect_count() == old_count);
	CHECK(timeline->get_stacks("Runtime.Status.Resolve") == 3);
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(1.75));

	CHECK(timeline->replace_effect_branch("Runtime", snapshot)); // Same values preserve phase.
	CHECK(timeline->tick(0.8).is_empty());
	pulses = timeline->take_periodic_pulses();
	CHECK(pulses.get(StringName("Runtime.Status.Resolve"), 0) == 1);
	CHECK(pulses.get(StringName("Local.Visual.Hit"), 0) == 4);
	CHECK(timeline->replace_effect_branch("Runtime", Dictionary()));
	CHECK(timeline->get_remaining("Runtime.Status.Resolve") == 0.0);
	CHECK(timeline->get_remaining("RuntimeExtra.Keep") == doctest::Approx(3.95));
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(0.95));
}


TEST_CASE("[GameplayFX] replicated effect reconciliation retains earned pulses and independent branches") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	REQUIRE(timeline->set_effect("Runtime.Status.Sundered", 5.0));
	REQUIRE(timeline->set_effect("Runtime.Status.Resolve", 5.0, 3));
	REQUIRE(timeline->set_effect("Local.Visual.Hit", 5.0));
	REQUIRE(timeline->set_periodic("Runtime.Status.Sundered", 0.5, false));
	REQUIRE(timeline->set_periodic("Runtime.Status.Resolve", 0.25, false));
	REQUIRE(timeline->set_periodic("Local.Visual.Hit", 0.25, false));
	CHECK(timeline->tick(0.6).is_empty()); // 1 sunder, 2 resolve, 2 local.
	Dictionary state;
	state["remaining"] = 4.5;
	state["stacks"] = 1;
	Dictionary incoming;
	incoming[StringName("Runtime.Status.Sundered")] = state;
	state = Dictionary();
	state["remaining"] = 4.2;
	state["stacks"] = 4;
	incoming[StringName("Runtime.Status.Resolve")] = state;
	CHECK(timeline->reconcile_effect_branch("Runtime", incoming));
	CHECK(timeline->get_stacks("Runtime.Status.Resolve") == 4);
	CHECK(timeline->get_remaining("Runtime.Status.Sundered") == doctest::Approx(4.5));
	CHECK(timeline->reconcile_effect_branch("Runtime", incoming)); // A duplicate network snapshot.
	Dictionary pulses = timeline->take_periodic_pulses();
	CHECK(int(pulses.get(StringName("Runtime.Status.Sundered"), 0)) == 1);
	CHECK(int(pulses.get(StringName("Runtime.Status.Resolve"), 0)) == 2);
	CHECK(int(pulses.get(StringName("Local.Visual.Hit"), 0)) == 2);
	CHECK(timeline->tick(0.6).is_empty());
	CHECK(timeline->reconcile_effect_branch("Runtime", Dictionary()));
	CHECK(timeline->get_remaining("Runtime.Status.Sundered") == 0.0);
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(3.8));
	pulses = timeline->take_periodic_pulses();
	CHECK(pulses.get(StringName("Runtime.Status.Sundered"), 0) == 0);
	CHECK(pulses.get(StringName("Runtime.Status.Resolve"), 0) == 0);
	CHECK(int(pulses.get(StringName("Local.Visual.Hit"), 0)) == 2);
	// The old API must retain its original drop-all-in-branch contract.
	CHECK(timeline->set_effect("Runtime.Status.Sundered", 2.0));
	CHECK(timeline->set_periodic("Runtime.Status.Sundered", 0.5, false));
	CHECK(timeline->tick(0.5).is_empty());
	CHECK(timeline->replace_effect_branch("Runtime", incoming));
	pulses = timeline->take_periodic_pulses();
	CHECK(pulses.get(StringName("Runtime.Status.Sundered"), 0) == 0);
}

TEST_CASE("[GameplayFX] replicated effect pulse preservation validates phase and rolls back") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	REQUIRE(timeline->set_effect("Runtime.Status.Sundered", 2.0));
	REQUIRE(timeline->set_periodic("Runtime.Status.Sundered", 0.5, false));
	CHECK(timeline->tick(0.6).is_empty()); // 1 queued pulse, next in 0.4.
	Dictionary state;
	state["remaining"] = 1.4;
	state["stacks"] = 1;
	Dictionary snapshot;
	snapshot[StringName("Runtime.Status.Sundered")] = state;
	Dictionary invalid = snapshot.duplicate(true);
	invalid[StringName("RuntimeExtra.Bad")] = state;
	CHECK_FALSE(timeline->reconcile_effect_branch("Runtime", invalid));
	invalid.erase(StringName("RuntimeExtra.Bad"));
	Dictionary bad_state = state.duplicate();
	bad_state["remaining"] = Math::NaN;
	invalid[StringName("Runtime.Status.Sundered")] = bad_state;
	CHECK_FALSE(timeline->reconcile_effect_branch("Runtime", invalid));
	CHECK(timeline->get_remaining("Runtime.Status.Sundered") == doctest::Approx(1.4));
	CHECK(timeline->get_periodic("Runtime.Status.Sundered") == doctest::Approx(0.5));
	// Accepted interval changes explicitly invalidate stale queued pulses.
	state["period"] = 1.0;
	state["next_period"] = 1.0;
	CHECK(timeline->reconcile_effect_branch("Runtime", snapshot));
	CHECK(timeline->take_periodic_pulses().is_empty());
	CHECK(timeline->tick(0.5).is_empty());
	// Same interval but a rephased deadline also cancels the old pulse.
	state["next_period"] = 0.25;
	CHECK(timeline->reconcile_effect_branch("Runtime", snapshot));
	CHECK(timeline->take_periodic_pulses().is_empty());
	CHECK(timeline->tick(0.25).is_empty());
	CHECK(int(timeline->take_periodic_pulses().get(StringName("Runtime.Status.Sundered"), 0)) == 1);
	CHECK(timeline->tick(2.0).size() == 1);
	CHECK(timeline->reconcile_effect_branch("Runtime", snapshot));
	CHECK(timeline->take_periodic_pulses().is_empty()); // New tag never inherits old expired pulses.
}
TEST_CASE("[GameplayFX] GameplayAttributeSet additive and percentage modifiers") {
	Ref<GameplayAttributeSet> a;
	a.instantiate();
	CHECK(a->set_base_value("Vital.Health", 80.0));
	CHECK(a->set_bounds("Vital.Health", 0.0, 100.0));
	CHECK(a->get_value("Vital.Health") == doctest::Approx(80.0));
	CHECK(a->set_modifier("Status.Fortified", "Vital.Health", 10.0, 0.25));
	CHECK(a->get_value("Vital.Health") == doctest::Approx(100.0)); // bounded
	CHECK(a->set_modifier("Status.Weakened", "Vital.Health", -30.0, -0.10));
	CHECK(a->get_value("Vital.Health") == doctest::Approx(69.0)); // (80+10-30)*1.15
	CHECK(a->get_value("Vital.Health") == doctest::Approx(69.0)); // cached
	CHECK(a->get_base_value("Vital.Health") == doctest::Approx(80.0));
	CHECK(a->set_modifier("Status.Weakened", "Vital.Health", -10.0, -0.10));
	CHECK(a->get_value("Vital.Health") == doctest::Approx(92.0));
	CHECK(a->remove_modifier("Status.Fortified", "Vital.Health"));
	CHECK(a->get_value("Vital.Health") == doctest::Approx(63.0));
	CHECK(a->clear_source("Status.Weakened") == 1);
	CHECK(a->get_value("Vital.Health") == doctest::Approx(80.0));
	CHECK(a->get_modifier_count() == 0);
}

TEST_CASE("[GameplayFX] GameplayAttributeSet transaction validation and snapshot isolation") {
	Ref<GameplayAttributeSet> a;
	a.instantiate();
	CHECK(a->set_base_value("Visual.HitResponse", 1.0));
	CHECK(a->set_bounds("Visual.HitResponse", 0.5, 1.75));
	CHECK(a->set_modifier("Rank.Elite", "Visual.HitResponse", 0.2));
	CHECK(a->set_modifier("Status.Sunder", "Visual.HitResponse", 0.25));
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.45));
	Dictionary snapshot = a->get_snapshot();
	Ref<GameplayAttributeSet> b;
	b.instantiate();
	CHECK(b->replace_snapshot(snapshot));
	CHECK(b->get_value("Visual.HitResponse") == doctest::Approx(1.45));
	Dictionary attrs = snapshot["attributes"];
	Dictionary original = attrs[StringName("Visual.HitResponse")];
	original["base"] = 600.0;
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.45));
	CHECK(b->get_value("Visual.HitResponse") == doctest::Approx(1.45));
	CHECK_FALSE(a->set_base_value("Untrusted", Math::NaN));
	CHECK_FALSE(a->set_modifier("Bad", "Visual.HitResponse", 0.0, Math::INF));
	CHECK_FALSE(a->set_bounds("Visual.HitResponse", 2.0, 1.0));
	CHECK_FALSE(a->set_modifier("Bad", "Missing", 1.0));
	Dictionary bad_snapshot = b->get_snapshot();
	Array bad_mods = bad_snapshot["modifiers"];
	Dictionary invalid;
	invalid["source"] = StringName("Status.Invalid");
	invalid["attribute"] = StringName("Missing");
	invalid["additive"] = 1.0;
	invalid["percent"] = 0.0;
	bad_mods.push_back(invalid);
	CHECK_FALSE(b->replace_snapshot(bad_snapshot));
	CHECK(b->get_value("Visual.HitResponse") == doctest::Approx(1.45));
	CHECK(b->get_modifier_count() == 2);
	CHECK(a->clear_source("Rank.Elite") == 1);
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.25));
}

TEST_CASE("[GameplayFX] GameplayAttributeSet scoped snapshots preserve other sources") {
	Ref<GameplayAttributeSet> a;
	a.instantiate();
	CHECK(a->set_base_value("Visual.HitResponse", 1.0));
	CHECK(a->set_bounds("Visual.HitResponse", 0.0, 10.0));
	CHECK(a->set_modifier("Runtime.Status.Sunder", "Visual.HitResponse", 0.25));
	CHECK(a->set_modifier("Local.Visual.Boost", "Visual.HitResponse", 0.15));
	CHECK(a->set_modifier("RuntimeExtra.Keep", "Visual.HitResponse", 0.1));
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.5));

	Dictionary incoming = a->get_snapshot();
	Array mods;
	Dictionary elite;
	elite["source"] = StringName("Runtime.Rank.Elite");
	elite["attribute"] = StringName("Visual.HitResponse");
	elite["additive"] = 0.2;
	elite["percent"] = 0.0;
	mods.push_back(elite);
	incoming["modifiers"] = mods;
	CHECK(a->replace_snapshot_branch("Runtime", incoming));
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.45));
	CHECK(a->get_modifier_count() == 3); // Rank + Local + RuntimeExtra.
	CHECK(a->clear_source("Runtime.Status.Sunder") == 0); // Expired.
	Dictionary saved = a->get_snapshot();
	CHECK(a->replace_snapshot_branch("Runtime", incoming)); // Idempotent.
	CHECK(a->get_modifier_count() == 3);
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.45));

	Dictionary invalid = incoming.duplicate(true);
	Array wrong_mods = invalid["modifiers"];
	Dictionary rogue = elite.duplicate();
	rogue["source"] = StringName("Local.Visual.Escaped");
	wrong_mods.push_back(rogue);
	invalid["modifiers"] = wrong_mods;
	CHECK_FALSE(a->replace_snapshot_branch("Runtime", invalid));
	CHECK_FALSE(a->replace_snapshot_branch("Runtime..Invalid", incoming));
	CHECK_FALSE(a->replace_snapshot_branch("Other", incoming));
	invalid = incoming.duplicate(true);
	Dictionary attrs = invalid["attributes"];
	attrs.erase(StringName("Visual.HitResponse"));
	CHECK_FALSE(a->replace_snapshot_branch("Runtime", invalid));
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.45));
	CHECK(a->get_snapshot() == saved); // Rollback after all rejected updates.

	// An empty incoming modifier list clears only Runtime sources, not Local.
	incoming["modifiers"] = Array();
	CHECK(a->replace_snapshot_branch("Runtime", incoming));
	CHECK(a->get_modifier_count() == 2);
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.25));
	CHECK(a->clear_source("RuntimeExtra.Keep") == 1);
	CHECK(a->get_value("Visual.HitResponse") == doctest::Approx(1.15));
}

TEST_CASE("[GameplayFX] AudioDuckMix overlapping source holds and bounded envelope") {
	Ref<AudioDuckMix> mix;
	mix.instantiate();
	CHECK(mix->trigger("Death", -12.0, 1.2));
	CHECK(mix->tick(0.1) == doctest::Approx(-4.0));
	CHECK(mix->trigger("Skill", -6.0, 3.0));
	CHECK(mix->get_source_count() == 2);
	CHECK(mix->get_target_db() == doctest::Approx(-12.0));
	CHECK(mix->tick(0.2) == doctest::Approx(-12.0));
	CHECK(mix->trigger("Skill", -8.0, 3.0));
	CHECK(mix->get_source_count() == 2);
	CHECK(mix->get_remaining("Skill") == doctest::Approx(3.0));
	CHECK(mix->tick(1.0) == doctest::Approx(-8.0));
	CHECK_FALSE(mix->has_source("Death"));
	CHECK(mix->has_source("Skill"));
	CHECK(mix->get_target_db() == doctest::Approx(-8.0));
	CHECK(mix->release_source("Skill"));
	CHECK(mix->tick(0.5) == doctest::Approx(-6.0));
	CHECK(mix->get_target_db() == 0.0);
	mix->clear();
	CHECK(mix->get_current_db() == 0.0);
	CHECK(mix->get_source_count() == 0);
}

TEST_CASE("[GameplayFX] AudioDuckMix invalid input, source bounds and no partial mutations") {
	Ref<AudioDuckMix> mix;
	mix.instantiate();
	CHECK(mix->trigger("Raid", -9.0));
	CHECK_FALSE(mix->trigger("", -4.0));
	CHECK_FALSE(mix->trigger("Bad", Math::NaN));
	CHECK_FALSE(mix->trigger("Bad", Math::INF));
	CHECK_FALSE(mix->trigger("Bad", -61.0));
	CHECK_FALSE(mix->trigger("Bad", 0.0));
	CHECK_FALSE(mix->trigger("Bad", -3.0, -1.0));
	CHECK_FALSE(mix->trigger("Bad", -3.0, Math::NaN));
	CHECK(mix->get_source_count() == 1);
	CHECK(mix->get_remaining("Raid") == doctest::Approx(1.2));
	CHECK(mix->tick(Math::NaN) == 0.0);
	CHECK(mix->tick(-1.0) == 0.0);
	CHECK(mix->get_remaining("Raid") == doctest::Approx(1.2));
	CHECK_FALSE(mix->set_rates(-1.0, 5.0));
	CHECK_FALSE(mix->set_rates(5.0, Math::INF));
	CHECK(mix->set_rates(40.0, 4.0));
	for (int i = 0; i < 31; ++i) {
		CHECK(mix->trigger(StringName(String("Event") + itos(i)), -3.0, 10.0));
	}
	CHECK(mix->get_source_count() == 32);
	CHECK_FALSE(mix->trigger("Overflow", -2.0));
	CHECK(mix->trigger("Raid", -10.0)); // Re-trigger still succeeds at capacity.
	CHECK(mix->get_source_count() == 32);
	CHECK(mix->get_target_db() == -10.0);
}

TEST_CASE("[GameplayFX] CooldownTracker individual and shared cooldowns") {
	Ref<GameplayCooldownTracker> tracker;
	tracker.instantiate();
	CHECK(tracker->try_start("Ability.Sprint", 5.0, "Ability.Global", 1.0));
	CHECK(tracker->get_remaining("Ability.Sprint") == doctest::Approx(5.0));
	CHECK(tracker->get_effective_remaining("Ability.Heal", "Ability.Global") == doctest::Approx(1.0));
	CHECK_FALSE(tracker->try_start("Ability.Heal", 3.0, "Ability.Global", 1.0));
	CHECK_FALSE(tracker->try_start("Ability.Sprint", 5.0));
	CHECK(tracker->tick(1.0).size() == 1);
	CHECK(tracker->is_ready("Ability.Heal", "Ability.Global"));
	CHECK(tracker->try_start("Ability.Heal", 3.0, "Ability.Global", 0.0));
	CHECK(tracker->get_remaining("Ability.Sprint") == doctest::Approx(4.0));
	CHECK(tracker->get_effective_remaining("Ability.Heal", "Ability.Global") == doctest::Approx(3.0));
	CHECK(tracker->reduce_remaining("Ability.Heal", 1.5));
	CHECK(tracker->get_remaining("Ability.Heal") == doctest::Approx(1.5));
	CHECK(tracker->tick(1.5).size() == 1);
	CHECK(tracker->get_remaining("Ability.Heal") == 0.0);
	CHECK(tracker->get_remaining("Ability.Sprint") == doctest::Approx(2.5));
	CHECK_FALSE(tracker->try_start("Ability.Dodge", 2.0, StringName(), 1.0));
	CHECK_FALSE(tracker->try_start("Ability.Dodge", 2.0, "Ability.Dodge", 1.0));
	CHECK(tracker->get_cooldown_count() == 1);
}

TEST_CASE("[GameplayFX] CooldownTracker bounded batch query respects order and shared group lock") {
	Ref<GameplayCooldownTracker> tracker;
	tracker.instantiate();
	CHECK(tracker->set_remaining("Ability.Global", 0.4));
	CHECK(tracker->set_remaining("Ability.Weapon", 3.5));
	CHECK(tracker->set_remaining("Ability.Head", 1.25));
	CHECK(tracker->set_remaining("Local.UI.Activation.weapon", 0.22));
	const PackedStringArray tags = { "Ability.Weapon", "Ability.Armor", "Ability.Head", "Ability.Feet", "Ability.Weapon" };
	const PackedFloat64Array values = tracker->get_effective_remaining_batch(tags, "Ability.Global");
	REQUIRE(values.size() == 5);
	CHECK(values[0] == doctest::Approx(3.5));
	CHECK(values[1] == doctest::Approx(0.4));
	CHECK(values[2] == doctest::Approx(1.25));
	CHECK(values[3] == doctest::Approx(0.4));
	CHECK(values[4] == doctest::Approx(3.5)); // Repeat keeps input ordering.
	const PackedFloat64Array without_group = tracker->get_effective_remaining_batch(tags);
	REQUIRE(without_group.size() == 5);
	CHECK(without_group[0] == doctest::Approx(3.5));
	CHECK(without_group[1] == 0.0);
	CHECK(tracker->get_cooldown_count() == 4); // Reads never create timers.
	CHECK(tracker->tick(0.5).size() == 2);
	const PackedFloat64Array after = tracker->get_effective_remaining_batch(tags, "Ability.Global");
	REQUIRE(after.size() == 5);
	CHECK(after[0] == doctest::Approx(3.0));
	CHECK(after[1] == 0.0);
	CHECK(after[2] == doctest::Approx(0.75));
	CHECK(after[3] == 0.0);
	CHECK(tracker->get_cooldown_count() == 2);
}

TEST_CASE("[GameplayFX] CooldownTracker batch rejects malformed requests without side effects") {
	Ref<GameplayCooldownTracker> tracker;
	tracker.instantiate();
	CHECK(tracker->set_remaining("Ability.Weapon", 2.0));
	const Dictionary before = tracker->get_snapshot();
	CHECK(tracker->get_effective_remaining_batch({ "Ability.Weapon", ".invalid" }).is_empty());
	CHECK(tracker->get_effective_remaining_batch({ "Ability.Weapon", "" }).is_empty());
	CHECK(tracker->get_effective_remaining_batch({ "Ability.Weapon" }, ".invalid").is_empty());
	PackedStringArray oversized;
	oversized.resize(65);
	CHECK(tracker->get_effective_remaining_batch(oversized).is_empty());
	CHECK(tracker->get_effective_remaining_batch(PackedStringArray()).is_empty());
	CHECK(tracker->get_snapshot() == before);
}

TEST_CASE("[GameplayFX] CooldownTracker snapshot rollback and frame-rate independence") {
	Ref<GameplayCooldownTracker> tracker;
	tracker.instantiate();
	Dictionary snapshot;
	snapshot["Ability.A"] = 5.0;
	snapshot["Ability.B"] = 2.0;
	CHECK(tracker->replace_snapshot(snapshot));
	CHECK(tracker->tick(0.5).is_empty());
	CHECK(tracker->tick(0.5).is_empty());
	CHECK(tracker->get_remaining("Ability.A") == doctest::Approx(4.0));
	CHECK(tracker->get_remaining("Ability.B") == doctest::Approx(1.0));
	Ref<GameplayCooldownTracker> other;
	other.instantiate();
	CHECK(other->replace_snapshot(tracker->get_snapshot()));
	CHECK(other->get_remaining("Ability.A") == doctest::Approx(4.0));
	Dictionary copy = tracker->get_snapshot();
	copy["Ability.A"] = 100.0;
	CHECK(tracker->get_remaining("Ability.A") == doctest::Approx(4.0));
	CHECK(tracker->tick(-1.0).is_empty());
	CHECK(tracker->tick(Math::INF).is_empty());
	CHECK_FALSE(tracker->set_remaining("Ability.C", Math::NaN));
	CHECK_FALSE(tracker->reduce_remaining("Ability.A", -2.0));
	CHECK_FALSE(tracker->try_start("Ability.C", Math::INF));
	Dictionary bad = tracker->get_snapshot();
	bad["Ability.Invalid"] = Math::NaN;
	CHECK_FALSE(tracker->replace_snapshot(bad));
	bad["Ability.Invalid"] = "not a time";
	CHECK_FALSE(tracker->replace_snapshot(bad));
	CHECK(tracker->get_remaining("Ability.A") == doctest::Approx(4.0));
	CHECK(tracker->tick(1.0).size() == 1);
	CHECK(tracker->tick(3.0).size() == 1);
	CHECK(tracker->get_cooldown_count() == 0);
	CHECK(other->get_cooldown_count() == 2);
}


TEST_CASE("[GameplayFX] CueQueue batch validates, coalesces and preserves priority") {
	Ref<GameplayCueQueue> queue;
	queue.instantiate();
	Array batch;
	Dictionary low;
	low["tag"] = "GameplayCue.Status.Sundered";
	low["magnitude"] = 2.0;
	low["priority"] = 4;
	Dictionary high;
	high["tag"] = StringName("GameplayCue.Status.Resolve");
	high["magnitude"] = 4.0;
	high["priority"] = 6;
	Dictionary repeat = low.duplicate();
	repeat["magnitude"] = 3.0;
	batch.push_back(low);
	batch.push_back(high);
	batch.push_back(repeat);
	CHECK(queue->emit_cues_batch(batch));
	CHECK(queue->get_pending_count() == 2);
	Array events = queue->take_events();
	REQUIRE(events.size() == 2);
	CHECK(String(events[0]["tag"]) == "GameplayCue.Status.Resolve");
	CHECK(int(events[0]["priority"]) == 6);
	CHECK(String(events[1]["tag"]) == "GameplayCue.Status.Sundered");
	CHECK(int(events[1]["count"]) == 2);
	CHECK(double(events[1]["magnitude"]) == doctest::Approx(3.0));
	CHECK(queue->get_evicted_transient_count() == 0);
	CHECK(queue->get_rejected_transient_count() == 0);
	CHECK(queue->emit_cues_batch(Array())); // Empty batch is a no-op success.
	CHECK(queue->get_pending_count() == 0);
}

TEST_CASE("[GameplayFX] CueQueue invalid batches roll back without changing lifecycle") {
	Ref<GameplayCueQueue> queue;
	queue.instantiate();
	CHECK(queue->set_active("GameplayCue.Status.Snared", 1, 2));
	CHECK(queue->emit_cue("GameplayCue.Ambient.Rain", 1.0, 0));
	Dictionary valid;
	valid["tag"] = "GameplayCue.Status.Resolve";
	valid["magnitude"] = 3.0;
	valid["priority"] = 6;
	Dictionary invalid = valid.duplicate();
	invalid["tag"] = "Bad.Tag";
	Array batch;
	batch.push_back(valid);
	batch.push_back(invalid);
	CHECK_FALSE(queue->emit_cues_batch(batch));
	CHECK(queue->get_pending_count() == 2);
	CHECK(queue->get_active_stacks("GameplayCue.Status.Snared") == 1);
	batch.remove_at(1);
	invalid["tag"] = "GameplayCue.Status.Resolve";
	invalid["priority"] = 8;
	batch.push_back(invalid);
	CHECK_FALSE(queue->emit_cues_batch(batch));
	CHECK(queue->get_pending_count() == 2);
	batch.remove_at(1);
	invalid["priority"] = 6;
	invalid["magnitude"] = Math::NaN;
	batch.push_back(invalid);
	CHECK_FALSE(queue->emit_cues_batch(batch));
	Array oversized;
	for (int i = 0; i < 33; ++i) {
		oversized.push_back(valid);
	}
	CHECK_FALSE(queue->emit_cues_batch(oversized));
	CHECK(queue->get_pending_count() == 2);
	CHECK(queue->get_rejected_transient_count() == 0);
	CHECK(queue->get_evicted_transient_count() == 0);
	Array events = queue->take_events();
	REQUIRE(events.size() == 2);
	CHECK(String(events[0]["event"]) == "started");
	CHECK(String(events[1]["tag"]) == "GameplayCue.Ambient.Rain");
}

TEST_CASE("[GameplayFX] CueQueue batch significance evictions commit together or not at all") {
	Ref<GameplayCueQueue> queue;
	queue.instantiate();
	for (int i = 0; i < GameplayCueQueue::MAX_PENDING; ++i) {
		CHECK(queue->emit_cue(StringName(String("GameplayCue.Ambient.") + itos(i)), 1.0, 1));
	}
	CHECK(queue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	Dictionary high;
	high["tag"] = "GameplayCue.Status.Resolve";
	high["magnitude"] = 4.0;
	high["priority"] = 6;
	Dictionary low;
	low["tag"] = "GameplayCue.Status.Sundered";
	low["magnitude"] = 2.0;
	low["priority"] = 0;
	Array impossible;
	impossible.push_back(high); // Would evict one ambience if committed.
	impossible.push_back(low); // Cannot evict priority=1 ambience.
	CHECK_FALSE(queue->emit_cues_batch(impossible));
	CHECK(queue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK(queue->get_evicted_transient_count() == 0);
	CHECK(queue->get_rejected_transient_count() == 0);
	low["priority"] = 4;
	Array admitted;
	admitted.push_back(high);
	admitted.push_back(low);
	CHECK(queue->emit_cues_batch(admitted));
	CHECK(queue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK(queue->get_evicted_transient_count() == 2);
	Array first = queue->take_events(2);
	REQUIRE(first.size() == 2);
	CHECK(String(first[0]["tag"]) == "GameplayCue.Status.Resolve");
	CHECK(String(first[1]["tag"]) == "GameplayCue.Status.Sundered");
}

TEST_CASE("[GameplayFX] CueQueue scoped status replication preserves independent active effects") {
	Ref<GameplayCueQueue> cue;
	cue.instantiate();
	CHECK(cue->set_active("GameplayCue.Local.Visual.Glow", 2, 1));
	CHECK(cue->set_active("GameplayCue.StatusExtra.Unrelated", 1, 1));
	Dictionary status;
	status["GameplayCue.Status.Resolve"] = 3;
	status[StringName("GameplayCue.Status.Staggered")] = 1;
	CHECK(cue->replace_active_branch("GameplayCue.Status", status, 2));
	CHECK(cue->get_active_count() == 4);
	CHECK(cue->get_active_stacks("GameplayCue.Local.Visual.Glow") == 2);
	CHECK(cue->get_active_stacks("GameplayCue.StatusExtra.Unrelated") == 1);
	CHECK(cue->get_active_stacks("GameplayCue.Status.Resolve") == 3);
	CHECK(cue->take_events().size() == 4);
	CHECK(cue->get_pending_count() == 0);
	// An identical network snapshot must not allocate or re-emit cues.
	CHECK(cue->replace_active_branch("GameplayCue.Status", status, 2));
	CHECK(cue->get_pending_count() == 0);
	status.erase(StringName("GameplayCue.Status.Staggered"));
	status["GameplayCue.Status.Resolve"] = 4;
	CHECK(cue->replace_active_branch("GameplayCue.Status", status, 2));
	CHECK(cue->get_active_count() == 3);
	CHECK(cue->get_active_stacks("GameplayCue.Local.Visual.Glow") == 2);
	CHECK(cue->get_active_stacks("GameplayCue.StatusExtra.Unrelated") == 1);
	Array events = cue->take_events();
	REQUIRE(events.size() == 2);
	CHECK(String(events[0]["tag"]) == "GameplayCue.Status.Staggered");
	CHECK(String(events[0]["event"]) == "stopped");
	CHECK(String(events[1]["tag"]) == "GameplayCue.Status.Resolve");
	CHECK(String(events[1]["event"]) == "updated");
	CHECK(int(events[1]["stacks"]) == 4);
	CHECK(cue->replace_active_branch("GameplayCue.Status", Dictionary(), 2));
	CHECK(cue->get_active_count() == 2);
	CHECK(cue->get_active_stacks("GameplayCue.Status.Resolve") == 0);
	CHECK(cue->get_active_stacks("GameplayCue.Local.Visual.Glow") == 2);
	CHECK(cue->take_events().size() == 1);
}

TEST_CASE("[GameplayFX] CueQueue scoped snapshots reject polluted or aliased input atomically") {
	Ref<GameplayCueQueue> cue;
	cue.instantiate();
	CHECK(cue->set_active("GameplayCue.Local.Visual.Glow", 2));
	CHECK(cue->set_active("GameplayCue.Status.Resolve", 3));
	const Dictionary baseline = cue->get_active_snapshot();
	const int pending_before = cue->get_pending_count();
	Dictionary invalid;
	invalid["GameplayCue.Status.Resolve"] = 1;
	invalid["GameplayCue.StatusExtra.Mimic"] = 1;
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", invalid));
	invalid.erase("GameplayCue.StatusExtra.Mimic");
	invalid["GameplayCue.Local.Visual.Glow"] = 3;
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", invalid));
	invalid.erase("GameplayCue.Local.Visual.Glow");
	invalid["GameplayCue.Status.Resolve"] = -1;
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", invalid));
	invalid["GameplayCue.Status.Resolve"] = 1.5;
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", invalid));
	invalid["GameplayCue.Status.Resolve"] = 65536;
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", invalid));
	invalid["GameplayCue.Status.Resolve"] = 1;
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.", invalid));
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", invalid, 8));
	invalid[StringName("GameplayCue.Status.Resolve")] = 2;
	// Different Godot Variant key implementations may coalesce String and
	// StringName keys. Assert alias rejection when the dictionary carries both.
	if (invalid.size() > 1) {
		CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", invalid));
	}
	CHECK(cue->get_active_snapshot() == baseline);
	CHECK(cue->get_pending_count() == pending_before);
	CHECK(cue->get_evicted_transient_count() == 0);
}

TEST_CASE("[GameplayFX] CueQueue scoped replication rolls back under lifecycle backlog pressure") {
	Ref<GameplayCueQueue> cue;
	cue.instantiate();
	CHECK(cue->set_active("GameplayCue.Local.Persist", 1));
	CHECK(cue->take_events().size() == 1);
	for (int i = 0; i < GameplayCueQueue::MAX_PENDING; ++i) {
		CHECK(cue->emit_cue(StringName(String("GameplayCue.Ambient.") + itos(i)), 1.0, 1));
	}
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	Dictionary incoming;
	incoming["GameplayCue.Status.Sundered"] = 2;
	const Dictionary before = cue->get_active_snapshot();
	CHECK_FALSE(cue->replace_active_branch("GameplayCue.Status", incoming, 3));
	CHECK(cue->get_active_snapshot() == before);
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK(cue->get_evicted_transient_count() == 0);
	CHECK(cue->get_rejected_transient_count() == 0);
	// A no-op scoped update is still valid even with a saturated visual queue.
	CHECK(cue->replace_active_branch("GameplayCue.Status", Dictionary(), 3));
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK(cue->take_events(32).size() == 32);
	CHECK(cue->replace_active_branch("GameplayCue.Status", incoming, 3));
	CHECK(cue->get_active_stacks("GameplayCue.Status.Sundered") == 2);
	CHECK(cue->get_active_stacks("GameplayCue.Local.Persist") == 1);
}

TEST_CASE("[GameplayFX] CueQueue active lifecycle, priorities and deduplication") {
	Ref<GameplayCueQueue> cue;
	cue.instantiate();
	Dictionary status;
	status["GameplayCue.Status.Sundered"] = 1;
	status[StringName("GameplayCue.Status.Resolve")] = 3;
	CHECK(cue->replace_active(status, 2));
	CHECK(cue->get_active_count() == 2);
	CHECK(cue->replace_active(status, 2)); // Idempotent replication.
	CHECK(cue->get_pending_count() == 2);
	Array events = cue->take_events();
	CHECK(events.size() == 2);
	CHECK(String(events[0]["event"]) == "started");
	CHECK(String(events[1]["event"]) == "started");
	CHECK(cue->get_pending_count() == 0);
	CHECK(cue->get_active_stacks("GameplayCue.Status.Resolve") == 3);

	CHECK(cue->emit_cue("GameplayCue.Status.Sundered", 0.6, 1));
	for (int i = 0; i < 80; ++i) {
		CHECK(cue->emit_cue("GameplayCue.Status.Sundered", 0.9, 1));
	}
	CHECK(cue->emit_cue("GameplayCue.Status.Resolve", 1.0, 7));
	CHECK(cue->get_pending_count() == 2);
	events = cue->take_events(1);
	REQUIRE(events.size() == 1);
	CHECK(String(events[0]["tag"]) == "GameplayCue.Status.Resolve");
	CHECK(String(events[0]["event"]) == "executed");
	events = cue->take_events(8);
	REQUIRE(events.size() == 1);
	CHECK(String(events[0]["tag"]) == "GameplayCue.Status.Sundered");
	CHECK(int(events[0]["count"]) == 32); // Bounded coalescing.
	CHECK(double(events[0]["magnitude"]) == doctest::Approx(0.9));

	status["GameplayCue.Status.Sundered"] = 0;
	status[StringName("GameplayCue.Status.Resolve")] = 4;
	CHECK(cue->replace_active(status));
	CHECK(cue->get_active_count() == 1);
	CHECK(cue->get_active_stacks("GameplayCue.Status.Sundered") == 0);
	events = cue->take_events();
	CHECK(events.size() == 2);
	CHECK(String(events[0]["event"]) == "stopped");
	CHECK(String(events[1]["event"]) == "updated");
	CHECK(int(events[1]["stacks"]) == 4);
}

TEST_CASE("[GameplayFX] CueQueue atomic rollback and bounded event buffering") {
	Ref<GameplayCueQueue> cue;
	cue.instantiate();
	CHECK(cue->set_active("GameplayCue.Status.Resolve", 2));
	CHECK(cue->take_events().size() == 1);
	const Dictionary baseline = cue->get_active_snapshot();
	Dictionary bad;
	bad["GameplayCue.Status.Valid"] = 2;
	bad["GameplayCue.Bad"] = -1;
	CHECK_FALSE(cue->replace_active(bad));
	CHECK(cue->get_active_snapshot() == baseline);
	bad.erase("GameplayCue.Bad");
	bad["NotACue"] = 1;
	CHECK_FALSE(cue->replace_active(bad));
	CHECK_FALSE(cue->set_active("GameplayCue.Invalid", -1));
	CHECK_FALSE(cue->emit_cue("GameplayCue.Status.Resolve", Math::NaN));
	CHECK_FALSE(cue->emit_cue("GameplayCue.Status.Resolve", 1.0, 8));
	CHECK(cue->get_pending_count() == 0);
	Dictionary copy = cue->get_active_snapshot();
	copy[StringName("GameplayCue.Status.Resolve")] = 999;
	CHECK(cue->get_active_stacks("GameplayCue.Status.Resolve") == 2);

	for (int i = 0; i < GameplayCueQueue::MAX_PENDING; ++i) {
		CHECK(cue->emit_cue(StringName(String("GameplayCue.Test.") + itos(i)), 1.0));
	}
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK_FALSE(cue->emit_cue("GameplayCue.Overflow", 1.0));
	CHECK_FALSE(cue->set_active("GameplayCue.Status.Resolve", 3)); // A new lifecycle event cannot fit.
	CHECK(cue->get_active_stacks("GameplayCue.Status.Resolve") == 2);
	CHECK(cue->take_events(0).is_empty());
	CHECK(cue->take_events(500).size() == 32);
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING - 32);
	cue->reset();
	CHECK(cue->get_active_count() == 0);
	CHECK(cue->get_pending_count() == 0);
}


TEST_CASE("[GameplayFX] CooldownTracker scoped server snapshot preserves cosmetic timers") {
	Ref<GameplayCooldownTracker> tracker;
	tracker.instantiate();
	CHECK(tracker->set_remaining("Local.UI.Activation.Weapon", 0.22));
	CHECK(tracker->set_remaining("AbilityExtra.Weapon", 7.0));
	CHECK(tracker->set_remaining("Ability.Old", 9.0));
	CHECK(tracker->set_remaining("Ability.Global", 0.4));
	Dictionary incoming;
	incoming[StringName("Ability.Weapon")] = 3.5;
	incoming[StringName("Ability.Head")] = 1.25;
	incoming[StringName("Ability.Global")] = 0.0;
	CHECK(tracker->replace_cooldown_branch("Ability", incoming));
	CHECK(tracker->get_cooldown_count() == 4);
	CHECK(tracker->get_remaining("Ability.Old") == 0.0);
	CHECK(tracker->get_remaining("Ability.Global") == 0.0);
	CHECK(tracker->get_remaining("Ability.Weapon") == doctest::Approx(3.5));
	CHECK(tracker->get_remaining("Ability.Head") == doctest::Approx(1.25));
	CHECK(tracker->get_remaining("AbilityExtra.Weapon") == doctest::Approx(7.0));
	CHECK(tracker->get_remaining("Local.UI.Activation.Weapon") == doctest::Approx(0.22));
	CHECK(tracker->tick(0.12).is_empty());
	CHECK(tracker->get_remaining("Local.UI.Activation.Weapon") == doctest::Approx(0.10));
	CHECK(tracker->replace_cooldown_branch("Ability", incoming));
	CHECK(tracker->get_remaining("Local.UI.Activation.Weapon") == doctest::Approx(0.10));
	CHECK(tracker->tick(0.11).size() == 1);
	CHECK(tracker->get_remaining("Local.UI.Activation.Weapon") == 0.0);
	CHECK(tracker->get_remaining("Ability.Weapon") > 3.0);
	CHECK(tracker->replace_cooldown_branch("Ability", Dictionary()));
	CHECK(tracker->get_remaining("Ability.Weapon") == 0.0);
	CHECK(tracker->get_remaining("AbilityExtra.Weapon") > 0.0);
}

TEST_CASE("[GameplayFX] CooldownTracker scoped snapshot rolls back on invalid input and capacity") {
	Ref<GameplayCooldownTracker> tracker;
	tracker.instantiate();
	CHECK(tracker->set_remaining("Local.UI.Activation.Weapon", 0.22));
	CHECK(tracker->set_remaining("Ability.Weapon", 4.0));
	const Dictionary before = tracker->get_snapshot();
	Dictionary invalid;
	invalid["Ability.Weapon"] = 2.0;
	invalid["Local.UI.Activation.Weapon"] = 99.0;
	CHECK_FALSE(tracker->replace_cooldown_branch("Ability", invalid));
	CHECK(tracker->get_snapshot() == before);
	invalid.erase("Local.UI.Activation.Weapon");
	invalid["Ability.Wrong"] = Math::INF;
	CHECK_FALSE(tracker->replace_cooldown_branch("Ability", invalid));
	CHECK(tracker->get_snapshot() == before);
	invalid.erase("Ability.Wrong");
	invalid["AbilityExtra.Weapon"] = 1.0;
	CHECK_FALSE(tracker->replace_cooldown_branch("Ability", invalid));
	CHECK(tracker->get_snapshot() == before);
	CHECK_FALSE(tracker->replace_cooldown_branch("Ability..Bad", Dictionary()));
	CHECK(tracker->get_snapshot() == before);

	Ref<GameplayCooldownTracker> full;
	full.instantiate();
	for (int i = 0; i < GameplayCooldownTracker::MAX_COOLDOWNS - 1; i++) {
		CHECK(full->set_remaining(StringName(String("Local.Cooldown.") + itos(i)), 3.0));
	}
	Dictionary too_many;
	too_many[StringName("Ability.Weapon")] = 5.0;
	too_many[StringName("Ability.Head")] = 6.0;
	CHECK_FALSE(full->replace_cooldown_branch("Ability", too_many));
	CHECK(full->get_cooldown_count() == GameplayCooldownTracker::MAX_COOLDOWNS - 1);
	CHECK(full->get_remaining("Ability.Weapon") == 0.0);
	CHECK(full->get_remaining("Local.Cooldown.0") == doctest::Approx(3.0));
}

static PackedStringArray effect_gate_tags(std::initializer_list<const char *> p_items) {
	PackedStringArray tags;
	for (const char *tag : p_items) {
		tags.push_back(tag);
	}
	return tags;
}

TEST_CASE("[GameplayFX] application gate hierarchical rules and immunity") {
	Ref<GameplayEffectApplicationGate> gate;
	gate.instantiate();
	const PackedStringArray alive = effect_gate_tags({"Life.Alive"});
	const PackedStringArray boss = effect_gate_tags({"Rank.RaidBoss", "Immunity.CrowdControl"});
	CHECK(gate->set_rule("Effect.CrowdControl", alive, boss));
	CHECK(gate->set_rule("Effect.CrowdControl.Stagger", PackedStringArray(), effect_gate_tags({"Status.Unstoppable"})));
	CHECK(gate->set_rule("Effect.Debuff.Sunder", alive, effect_gate_tags({"Immunity.Sunder"})));
	CHECK(gate->get_rule_count() == 3);
	CHECK(gate->can_apply("Effect.CrowdControl.Snare", effect_gate_tags({"Life.Alive"})));
	CHECK(gate->can_apply("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive", "Rank.Elite"})));
	CHECK_FALSE(gate->can_apply("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive", "Rank.RaidBoss.Enraged"})));
	CHECK(gate->get_failure_reason("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive", "Immunity.CrowdControl"})) == "blocked");
	CHECK(gate->get_failure_reason("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Dead"})) == "missing_required");
	CHECK(gate->get_failure_reason("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive", "Status.Unstoppable"})) == "blocked");
	CHECK(gate->get_failure_reason("Effect.Unknown", effect_gate_tags({"Life.Alive"})) == "unknown_effect");
	CHECK_FALSE(gate->can_apply("Effect.CrowdControls.Snare", effect_gate_tags({"Life.Alive"}))); // sibling is not a descendant
	CHECK(gate->can_apply("Effect.Debuff.Sunder", effect_gate_tags({"Life.Alive", "Rank.RaidBoss"})));
	CHECK_FALSE(gate->can_apply("Effect.Debuff.Sunder", effect_gate_tags({"Life.Alive", "Immunity.Sunder.Special"})));
}

TEST_CASE("[GameplayFX] application gate atomic snapshot rollback and hostile tags") {
	Ref<GameplayEffectApplicationGate> gate;
	gate.instantiate();
	CHECK(gate->set_rule("Effect.CrowdControl", effect_gate_tags({"Life.Alive"}), effect_gate_tags({"Rank.RaidBoss"})));
	Dictionary snapshot = gate->get_snapshot();
	Ref<GameplayEffectApplicationGate> copy;
	copy.instantiate();
	CHECK(copy->replace_snapshot(snapshot));
	CHECK(copy->can_apply("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive"})));
	Dictionary invalid = snapshot.duplicate(true);
	Dictionary wrong;
	wrong["required"] = effect_gate_tags({"Life.Alive"});
	wrong["blocked"] = effect_gate_tags({"Rank. Bad"});
	invalid[StringName("Effect.Bad")] = wrong;
	CHECK_FALSE(copy->replace_snapshot(invalid));
	CHECK(copy->get_rule_count() == 1);
	CHECK(copy->can_apply("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive"})));
	CHECK_FALSE(copy->set_rule("Effect..Bad", PackedStringArray(), PackedStringArray()));
	CHECK_FALSE(copy->set_rule("Effect.Bad", effect_gate_tags({"Life.Alive", "Life.Alive"}), PackedStringArray()));
	CHECK_FALSE(copy->can_apply("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive", "Bad Tag"})));
	CHECK(gate->get_rule_count() == 1);
	CHECK(gate->remove_rule("Effect.CrowdControl"));
	CHECK_FALSE(gate->can_apply("Effect.CrowdControl.Stagger", effect_gate_tags({"Life.Alive"})));
}


TEST_CASE("[GameplayFX] CueQueue preserves lifecycle while higher-priority pulses displace ambience") {
	Ref<GameplayCueQueue> cue;
	cue.instantiate();
	CHECK(cue->set_active("GameplayCue.Status.Resolve", 3, 7));
	for (int i = 0; i < GameplayCueQueue::MAX_PENDING - 1; ++i) {
		CHECK(cue->emit_cue(StringName(String("GameplayCue.Ambient.") + itos(i)), 1.0, 0));
	}
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK_FALSE(cue->emit_cue("GameplayCue.Ambient.Rejected", 1.0, 0));
	CHECK(cue->get_rejected_transient_count() == 1);
	CHECK(cue->get_evicted_transient_count() == 0);
	// Existing tags still coalesce even on the full queue.
	CHECK(cue->emit_cue("GameplayCue.Ambient.1", 0.8, 0));
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	// Lifecycle updates remain atomic when no slot is available.
	CHECK_FALSE(cue->set_active("GameplayCue.Status.Resolve", 4, 7));
	CHECK(cue->get_active_stacks("GameplayCue.Status.Resolve") == 3);
	CHECK(cue->emit_cue("GameplayCue.Status.CriticalHit", 2.0, 6));
	CHECK(cue->get_evicted_transient_count() == 1);
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK(cue->get_rejected_transient_count() == 1);
	Array events = cue->take_events(2);
	REQUIRE(events.size() == 2);
	CHECK(String(events[0]["event"]) == "started");
	CHECK(String(events[0]["tag"]) == "GameplayCue.Status.Resolve");
	CHECK(String(events[1]["event"]) == "executed");
	CHECK(String(events[1]["tag"]) == "GameplayCue.Status.CriticalHit");
	CHECK(int(events[1]["priority"]) == 6);
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING - 2);
	// Under equal background priorities, the oldest eligible event goes.
	bool saw_oldest = false;
	bool saw_next = false;
	int remaining_count = 0;
	while (cue->get_pending_count() > 0) {
		const Array batch = cue->take_events(32);
		for (int i = 0; i < batch.size(); ++i) {
			const String tag = String(batch[i]["tag"]);
			saw_oldest |= tag == "GameplayCue.Ambient.0";
			if (tag == "GameplayCue.Ambient.1") {
				saw_next = true;
				CHECK(int(batch[i]["count"]) == 2);
			}
			++remaining_count;
		}
	}
	CHECK_FALSE(saw_oldest);
	CHECK(saw_next);
	CHECK(remaining_count == GameplayCueQueue::MAX_PENDING - 2);
	cue->reset();
	CHECK(cue->get_evicted_transient_count() == 0);
	CHECK(cue->get_rejected_transient_count() == 0);
}

TEST_CASE("[GameplayFX] CueQueue never evicts lifecycle-only saturation or equal priorities") {
	Ref<GameplayCueQueue> cue;
	cue.instantiate();
	Dictionary snapshots;
	for (int i = 0; i < GameplayCueQueue::MAX_ACTIVE; ++i) {
		snapshots[StringName(String("GameplayCue.Status.") + itos(i))] = 1;
	}
	CHECK(cue->replace_active(snapshots));
	CHECK(cue->get_active_count() == GameplayCueQueue::MAX_ACTIVE);
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK_FALSE(cue->emit_cue("GameplayCue.Status.ImportantHit", 1.0, 7));
	CHECK(cue->get_rejected_transient_count() == 1);
	CHECK(cue->get_evicted_transient_count() == 0);
	CHECK(cue->get_pending_count() == GameplayCueQueue::MAX_PENDING);
	CHECK(cue->get_active_stacks("GameplayCue.Status.0") == 1);
	CHECK_FALSE(cue->emit_cue("GameplayCue.Status.ImportantHit", Math::NaN, 7));
	CHECK(cue->get_rejected_transient_count() == 1); // Invalid input is not overload.
	cue->reset();
	for (int i = 0; i < GameplayCueQueue::MAX_PENDING; ++i) {
		CHECK(cue->emit_cue(StringName(String("GameplayCue.Important.") + itos(i)), 1.0, 7));
	}
	CHECK_FALSE(cue->emit_cue("GameplayCue.Important.SamePriority", 1.0, 7));
	CHECK(cue->get_evicted_transient_count() == 0);
	CHECK(cue->get_rejected_transient_count() == 1);
}


TEST_CASE("[GameplayFX] stack policy Resolve diminishing returns and strict reapply") {
	Ref<GameplayEffectStackPolicy> policy;
	policy.instantiate();
	PackedFloat32Array factors;
	factors.push_back(1.0f);
	factors.push_back(0.65f);
	factors.push_back(0.4f);
	CHECK(policy->configure(3, factors, GameplayEffectStackPolicy::OVERFLOW_CLAMP, GameplayEffectStackPolicy::REAPPLY_IF_STRONGER));
	CHECK(policy->calculate_magnitude(1.5, 0) == doctest::Approx(1.5));
	CHECK(policy->calculate_magnitude(1.5, 1) == doctest::Approx(0.975).epsilon(0.00001));
	CHECK(policy->calculate_magnitude(1.5, 2) == doctest::Approx(0.6).epsilon(0.00001));
	CHECK(policy->calculate_magnitude(1.5, 99) == doctest::Approx(0.6).epsilon(0.00001));
	CHECK(policy->calculate_magnitude(1.5, 0, 0.5) == doctest::Approx(0.75));
	Dictionary first = policy->preview_application(1.5, 0, 0.0);
	CHECK(bool(first["accepted"]));
	CHECK(int(first["stacks"]) == 1);
	CHECK(double(first["remaining"]) == doctest::Approx(1.5));
	Dictionary reject = policy->preview_application(1.5, 1, 1.5);
	CHECK_FALSE(bool(reject["accepted"]));
	CHECK(int(reject["stacks"]) == 1);
	CHECK(String(reject["reason"]) == "weaker");
	Dictionary next = policy->preview_application(1.5, 1, 0.5);
	CHECK(bool(next["accepted"]));
	CHECK(int(next["stacks"]) == 2);
	CHECK(double(next["remaining"]) == doctest::Approx(0.975).epsilon(0.00001));
	Dictionary saturated = policy->preview_application(1.5, 3, 0.1);
	CHECK(bool(saturated["accepted"]));
	CHECK(bool(saturated["overflow"]));
	CHECK(int(saturated["stacks"]) == 3);
	CHECK(double(saturated["remaining"]) == doctest::Approx(0.6).epsilon(0.00001));
}

TEST_CASE("[GameplayFX] stack policy overflow, reapply modes, rollback and malformed input") {
	Ref<GameplayEffectStackPolicy> policy;
	policy.instantiate();
	PackedFloat32Array factors;
	factors.push_back(1.0f);
	factors.push_back(0.75f);
	CHECK(policy->configure(2, factors, GameplayEffectStackPolicy::OVERFLOW_REJECT, GameplayEffectStackPolicy::REAPPLY_REFRESH));
	CHECK_FALSE(bool(policy->preview_application(3.0, 2, 0.0)["accepted"]));
	CHECK(bool(policy->preview_application(3.0, 1, 2.0)["accepted"]));
	CHECK(policy->configure(2, factors, GameplayEffectStackPolicy::OVERFLOW_RESET, GameplayEffectStackPolicy::REAPPLY_EXTEND));
	Dictionary reset = policy->preview_application(4.0, 2, 1.0);
	CHECK(bool(reset["accepted"]));
	CHECK(bool(reset["overflow"]));
	CHECK(int(reset["stacks"]) == 1);
	CHECK(double(reset["remaining"]) == doctest::Approx(5.0));
	CHECK(policy->configure(2, factors, GameplayEffectStackPolicy::OVERFLOW_CLAMP, GameplayEffectStackPolicy::REAPPLY_KEEP));
	CHECK_FALSE(bool(policy->preview_application(2.0, 1, 0.4)["accepted"]));
	CHECK(bool(policy->preview_application(2.0, 1, 0.0)["accepted"]));

	Dictionary saved = policy->get_config();
	Ref<GameplayEffectStackPolicy> restored;
	restored.instantiate();
	CHECK(restored->replace_config(saved));
	CHECK(restored->get_max_stacks() == 2);
	CHECK(restored->get_reapply_policy() == GameplayEffectStackPolicy::REAPPLY_KEEP);
	Dictionary malformed = saved.duplicate(true);
	PackedFloat32Array bad = factors;
	bad.set(1, Math::NaN);
	malformed["stack_factors"] = bad;
	CHECK_FALSE(restored->replace_config(malformed));
	malformed = saved.duplicate(true);
	malformed["max_stacks"] = int64_t(4294967298LL);
	CHECK_FALSE(restored->replace_config(malformed));
	CHECK(restored->get_max_stacks() == 2);
	CHECK(restored->get_reapply_policy() == GameplayEffectStackPolicy::REAPPLY_KEEP);
	CHECK_FALSE(restored->configure(0, factors));
	CHECK_FALSE(restored->configure(33, factors));
	CHECK_FALSE(restored->configure(1, factors));
	CHECK_FALSE(restored->configure(2, factors, 99));
	CHECK(restored->calculate_magnitude(Math::NaN, 0) == 0.0);
	CHECK(restored->calculate_magnitude(1.0, 0, Math::INF) == 0.0);
	CHECK_FALSE(bool(restored->preview_application(1.0, 0, -1.0)["accepted"]));
	CHECK_FALSE(bool(restored->preview_application(1.0, -1, 0.0)["accepted"]));
	CHECK(restored->get_max_stacks() == 2);
}

} // namespace TestGameplayFX
