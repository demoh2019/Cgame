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

#include "../gameplay_attribute_set.h"
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
} // namespace TestGameplayFX
