/**************************************************************************/
/*  test_animation_player.cpp                                             */
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

TEST_FORCE_LINK(test_animation_player)

#include "scene/animation/animation_player.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/animation.h"

namespace TestAnimationPlayer {

TEST_CASE("[AnimationPlayer] get & set default_blend_time") {
	AnimationPlayer *animation_player = memnew(AnimationPlayer);
	animation_player->set_default_blend_time(4.0);

	CHECK(animation_player->get_default_blend_time() == doctest::Approx(4.0f));
	memdelete(animation_player);
}

TEST_CASE("[AnimationPlayer] get & set blend_time") {
	String anim1 = "animation1";
	String anim2 = "animation2";
	const Ref<Animation> animation1 = memnew(Animation);
	const Ref<Animation> animation2 = memnew(Animation);
	const Ref<AnimationLibrary> animation_library = memnew(AnimationLibrary);
	animation_library->add_animation(anim1, animation1);
	animation_library->add_animation(anim2, animation2);

	AnimationPlayer *animation_player = memnew(AnimationPlayer);
	animation_player->add_animation_library("", animation_library);

	animation_player->set_blend_time(anim1, anim2, 4.0);
	CHECK(animation_player->get_blend_time(anim1, anim2) == doctest::Approx(4.0f));
	memdelete(animation_player);
}

static AnimationPlayer *create_player_with_animations() {
	AnimationPlayer *player = memnew(AnimationPlayer);
	Ref<AnimationLibrary> library;
	library.instantiate();
	Ref<Animation> first;
	first.instantiate();
	first->set_length(0.5);
	Ref<Animation> second;
	second.instantiate();
	second->set_length(0.5);
	library->add_animation("first", first);
	library->add_animation("second", second);
	player->add_animation_library("", library);
	SceneTree::get_singleton()->get_root()->add_child(player);
	return player;
}

TEST_CASE("[SceneTree][AnimationPlayer] Finishing an animation clears its active state") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	CHECK(player->is_playing());
	CHECK(player->is_valid());
	CHECK(player->get_current_animation() == StringName("first"));

	player->advance(0.25);
	CHECK(player->is_playing());
	CHECK(player->is_valid());
	player->advance(0.5);

	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());
	CHECK(player->get_current_animation().is_empty());
	// Keep the last assigned name so the user can restart the animation.
	CHECK(player->get_assigned_animation() == StringName("first"));
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] Finishing backwards also clears the active state") {
	AnimationPlayer *player = create_player_with_animations();
	player->play_backwards("first");
	CHECK(player->is_valid());
	player->advance(0.75);
	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());
	CHECK(player->get_assigned_animation() == StringName("first"));
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] Pausing preserves the active animation until stopped") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	player->advance(0.1);
	player->pause();

	CHECK_FALSE(player->is_playing());
	CHECK(player->is_valid());
	CHECK(player->get_assigned_animation() == StringName("first"));

	player->stop();
	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] Stop with keep state also clears animation validity") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	player->advance(0.1);
	player->stop(true);

	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());
	CHECK(player->get_assigned_animation() == StringName("first"));
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] A completed animation can be played again") {
	AnimationPlayer *player = create_player_with_animations();
	for (int i = 0; i < 3; i++) {
		player->play("first");
		CHECK(player->is_valid());
		CHECK(player->is_playing());
		player->advance(0.6);
		CHECK_FALSE(player->is_valid());
		CHECK_FALSE(player->is_playing());
	}
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] Queued animation stays active until it finishes") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	player->queue("second");
	CHECK(player->get_queue().size() == 1);

	player->advance(0.6);
	CHECK(player->is_playing());
	CHECK(player->is_valid());
	CHECK(player->get_current_animation() == StringName("second"));
	player->advance(0.6);

	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());
	CHECK(player->get_assigned_animation() == StringName("second"));
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] Assigning a new animation after completion leaves it ready but paused") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	player->advance(0.6);
	CHECK_FALSE(player->is_valid());

	player->set_assigned_animation("second");
	CHECK(player->is_valid());
	CHECK_FALSE(player->is_playing());
	CHECK(player->get_assigned_animation() == StringName("second"));
	player->play();
	CHECK(player->is_playing());
	CHECK(player->is_valid());
	memdelete(player);
}


TEST_CASE("[SceneTree][AnimationPlayer] Completion remains inactive across further advances") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	player->advance(0.6);
	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());

	for (int i = 0; i < 3; i++) {
		player->advance(0.1);
		CHECK_FALSE(player->is_playing());
		CHECK_FALSE(player->is_valid());
		CHECK(player->get_current_animation().is_empty());
		CHECK(player->get_assigned_animation() == StringName("first"));
	}
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] A finished animation can transition to reverse playback") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	player->advance(0.6);
	CHECK_FALSE(player->is_valid());

	player->play_backwards("second");
	CHECK(player->is_playing());
	CHECK(player->is_valid());
	CHECK(player->get_current_animation() == StringName("second"));
	player->advance(0.6);
	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());
	CHECK(player->get_assigned_animation() == StringName("second"));
	memdelete(player);
}

TEST_CASE("[SceneTree][AnimationPlayer] Pausing and resuming does not prematurely reset animation") {
	AnimationPlayer *player = create_player_with_animations();
	player->play("first");
	player->advance(0.1);
	player->pause();
	CHECK_FALSE(player->is_playing());
	CHECK(player->is_valid());
	CHECK(player->get_current_animation() == StringName("first"));

	player->play();
	CHECK(player->is_playing());
	CHECK(player->is_valid());
	player->advance(0.5);
	CHECK_FALSE(player->is_playing());
	CHECK_FALSE(player->is_valid());
	CHECK(player->get_assigned_animation() == StringName("first"));
	memdelete(player);
}

} // namespace TestAnimationPlayer
