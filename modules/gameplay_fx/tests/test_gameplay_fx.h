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
TEST_CASE("[GameplayFX] timeline scoped snapshot preserves local timers and rolls back") {
	Ref<GameplayEffectTimeline> timeline;
	timeline.instantiate();
	CHECK(timeline->set_effect("Local.Visual.Hit", 0.25, 1));
	CHECK(timeline->set_effect("Runtime.Status.Staggered", 3.0, 1));
	CHECK(timeline->set_effect("RuntimeExtra.Keep", 5.0, 2));

	Dictionary resolve;
	resolve["remaining"] = 4.0;
	resolve["stacks"] = 3;
	Dictionary snapshot;
	snapshot[StringName("Runtime.Status.Resolve")] = resolve;
	CHECK(timeline->replace_effect_branch("Runtime", snapshot));
	CHECK(timeline->get_effect_count() == 3);
	CHECK(timeline->get_remaining("Runtime.Status.Staggered") == 0.0);
	CHECK(timeline->get_remaining("Runtime.Status.Resolve") == doctest::Approx(4.0));
	CHECK(timeline->get_stacks("Runtime.Status.Resolve") == 3);
	CHECK(timeline->get_remaining("RuntimeExtra.Keep") == doctest::Approx(5.0));
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(0.25));

	Dictionary before = timeline->get_snapshot();
	Dictionary invalid = snapshot.duplicate(true);
	invalid["Outside.Escaped"] = resolve;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	invalid.erase("Outside.Escaped");
	Dictionary bad;
	bad["remaining"] = Math::NaN;
	bad["stacks"] = 1;
	invalid["Runtime.Status.Frozen"] = bad;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	bad["remaining"] = 2.0;
	bad["stacks"] = 0;
	invalid["Runtime.Status.Frozen"] = bad;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	bad["stacks"] = 65536;
	invalid["Runtime.Status.Frozen"] = bad;
	CHECK_FALSE(timeline->replace_effect_branch("Runtime", invalid));
	CHECK_FALSE(timeline->replace_effect_branch("Runtime..Bad", snapshot));
	CHECK_FALSE(timeline->replace_effect_branch("", snapshot));
	CHECK(timeline->get_effect_count() == before.size());
	CHECK(timeline->get_stacks("Runtime.Status.Resolve") == 3);
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(0.25));

	Dictionary duplicate;
	duplicate[String("Runtime.Status.Resolve")] = resolve;
	duplicate[StringName("Runtime.Status.Resolve")] = resolve;
	// Some Godot builds normalize String and StringName dictionary keys at insertion.
	// If they remain distinct, the native API must reject that ambiguous alias.
	if (duplicate.size() == 2) {
		CHECK_FALSE(timeline->replace_effect_branch("Runtime", duplicate));
	} else {
		CHECK(timeline->replace_effect_branch("Runtime", duplicate));
	}
	CHECK(timeline->get_stacks("Runtime.Status.Resolve") == 3);
	CHECK(timeline->replace_effect_branch("Runtime", snapshot));
	CHECK(timeline->tick(0.1).is_empty());
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(0.15));
	CHECK(timeline->replace_effect_branch("Runtime", Dictionary()));
	CHECK(timeline->get_remaining("Runtime.Status.Resolve") == 0.0);
	CHECK(timeline->get_remaining("RuntimeExtra.Keep") == doctest::Approx(4.9));
	CHECK(timeline->get_remaining("Local.Visual.Hit") == doctest::Approx(0.15));
}

} // namespace TestGameplayFX
