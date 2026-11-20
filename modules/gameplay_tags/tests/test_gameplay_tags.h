/**************************************************************************/
/*  test_gameplay_tags.h                                                  */
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

#include "../animation_lod_controller.h"
#include "../gameplay_tag_container.h"
#include "scene/animation/animation_player.h"

#include "tests/test_macros.h"

namespace TestGameplayTags {

TEST_CASE("[GameplayTags] tag_matches hierarchy") {
	CHECK(GameplayTagContainer::tag_matches("Enemy.Infected.Elite", "Enemy.Infected.Elite", true));
	CHECK(GameplayTagContainer::tag_matches("Enemy.Infected.Elite", "Enemy"));
	CHECK(GameplayTagContainer::tag_matches("Enemy.Infected.Elite", "Enemy.Infected"));
	CHECK_FALSE(GameplayTagContainer::tag_matches("Enemy.Infected.Elite", "Enemy", true));
	CHECK_FALSE(GameplayTagContainer::tag_matches("Enemy.Infected", "Enemy.Infected.Elite"));
	// Must match on a '.' boundary, not a raw prefix.
	CHECK_FALSE(GameplayTagContainer::tag_matches("Enemies.Boss", "Enemy"));
	CHECK_FALSE(GameplayTagContainer::tag_matches("EnemyBoss", "Enemy"));
	CHECK_FALSE(GameplayTagContainer::tag_matches("Enemy", ""));
	CHECK_FALSE(GameplayTagContainer::tag_matches("", "Enemy"));
}

TEST_CASE("[GameplayTags] container add/remove/has") {
	Ref<GameplayTagContainer> c;
	c.instantiate();
	CHECK(c->is_empty());
	c->add_tag("Enemy.Infected.Elite");
	c->add_tag("Enemy.Infected.Elite"); // Duplicate ignored.
	c->add_tag("Status.Burning");
	CHECK(c->get_tag_count() == 2);
	CHECK(c->has_tag("Enemy"));
	CHECK_FALSE(c->has_tag("Enemy", true));
	CHECK(c->has_tag("Status.Burning", true));
	CHECK_FALSE(c->has_tag("Status.Frozen"));

	PackedStringArray any;
	any.push_back("Status.Frozen");
	any.push_back("Status");
	CHECK(c->has_any(any));
	CHECK_FALSE(c->has_any(any, true));

	PackedStringArray all;
	all.push_back("Enemy");
	all.push_back("Status.Burning");
	CHECK(c->has_all(all));
	all.push_back("Player");
	CHECK_FALSE(c->has_all(all));

	c->remove_tag("Status.Burning");
	CHECK_FALSE(c->has_tag("Status"));
	CHECK(c->get_tag_count() == 1);
}

TEST_CASE("[GameplayTags] query all/any/none") {
	Ref<GameplayTagContainer> c;
	c.instantiate();
	c->add_tag("Enemy.Infected.Elite");
	c->add_tag("Status.Burning");

	Ref<GameplayTagQuery> q;
	q.instantiate();
	PackedStringArray all;
	all.push_back("Enemy");
	q->set_all_tags(all);
	CHECK(q->matches(c));

	PackedStringArray none;
	none.push_back("Status.Burning");
	q->set_none_tags(none);
	CHECK_FALSE(q->matches(c));

	q->set_none_tags(PackedStringArray());
	PackedStringArray any;
	any.push_back("Player");
	q->set_any_tags(any);
	CHECK_FALSE(q->matches(c));
	any.push_back("Status");
	q->set_any_tags(any);
	CHECK(q->matches(c));
	CHECK_FALSE(q->matches(Ref<GameplayTagContainer>())); // Null behaves as empty.
}

TEST_CASE("[AnimationLODController] update_interval") {
	CHECK(AnimationLODController::update_interval(5, true, 15, 35, 70) == 1);
	CHECK(AnimationLODController::update_interval(15, true, 15, 35, 70) == 2);
	CHECK(AnimationLODController::update_interval(34.9, true, 15, 35, 70) == 2);
	CHECK(AnimationLODController::update_interval(50, true, 15, 35, 70) == 4);
	CHECK(AnimationLODController::update_interval(70, true, 15, 35, 70) == 0);
	CHECK(AnimationLODController::update_interval(200, true, 15, 35, 70) == 0);
	CHECK(AnimationLODController::update_interval(1, false, 15, 35, 70) == 0);
}

TEST_CASE("[AnimationLODController] priority budget and reversible urgent mixers") {
	AnimationLODController *lod = memnew(AnimationLODController);
	AnimationPlayer *mixer = memnew(AnimationPlayer);

	CHECK(lod->get_max_priority_mixers() == 8);
	lod->set_max_priority_mixers(-50);
	CHECK(lod->get_max_priority_mixers() == 0);
	lod->set_max_priority_mixers(500);
	CHECK(lod->get_max_priority_mixers() == 32);
	lod->set_max_priority_mixers(4);
	CHECK(lod->get_max_priority_mixers() == 4);

	CHECK_FALSE(lod->is_mixer_high_priority(mixer));
	lod->register_mixer(mixer);
	CHECK(lod->get_mixer_count() == 1);
	CHECK_FALSE(lod->is_mixer_high_priority(mixer));
	lod->set_mixer_high_priority(mixer, true);
	CHECK(lod->is_mixer_high_priority(mixer));
	lod->set_mixer_high_priority(mixer, true); // A repeated network snapshot is a no-op.
	CHECK(lod->get_mixer_count() == 1);
	lod->set_mixer_high_priority(mixer, false);
	CHECK_FALSE(lod->is_mixer_high_priority(mixer));
	lod->set_mixer_high_priority(mixer, true);
	lod->unregister_mixer(mixer);
	CHECK(lod->get_mixer_count() == 0);
	CHECK_FALSE(lod->is_mixer_high_priority(mixer));

	memdelete(mixer);
	memdelete(lod);
}

} // namespace TestGameplayTags
