/**************************************************************************/
/*  animation_node_motion_matching.h                                      */
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

#include "cgame_motion_matching_database.h"

#include "scene/animation/animation_tree.h"

// AnimationTree node that picks a clip and a playback time every search interval by running a
// pose search over a CgameMotionMatchingDatabase, then plays it back with a short crossfade.
class AnimationNodeMotionMatching : public AnimationRootNode {
	GDCLASS(AnimationNodeMotionMatching, AnimationRootNode);

	Ref<CgameMotionMatchingDatabase> database;
	Dictionary clip_animations;
	PackedStringArray required_tags;
	float search_interval = 0.1f;
	float blend_time = 0.15f;
	bool use_brute_force = false;

	// Parameter names.
	StringName p_velocity = "velocity";
	StringName p_facing = "facing";
	StringName p_desired_velocity = "desired_velocity";
	StringName p_desired_facing = "desired_facing";
	StringName p_left_foot = "left_foot";
	StringName p_right_foot = "right_foot";
	StringName p_left_foot_velocity = "left_foot_velocity";
	StringName p_right_foot_velocity = "right_foot_velocity";
	StringName p_features = "features";
	StringName p_current_clip = "current_clip";
	StringName p_current_time = "current_time";
	StringName p_previous_clip = "previous_clip";
	StringName p_previous_time = "previous_time";
	StringName p_blend_elapsed = "blend_elapsed";
	StringName p_search_timer = "search_timer";
	StringName p_last_cost = "last_cost";

	StringName _animation_for_clip(int p_clip) const;

protected:
	static void _bind_methods();

public:
	virtual void get_parameter_list(LocalVector<PropertyInfo> *r_list) const override;
	virtual Variant get_parameter_default_value(const StringName &p_parameter) const override;
	virtual bool is_parameter_read_only(const StringName &p_parameter) const override;
	virtual NodeTimeInfo _process(ProcessState &p_process_state, AnimationNodeInstance &p_instance, const AnimationMixer::PlaybackInfo &p_playback_info, bool p_test_only = false) override;
	virtual String get_caption() const override;

	void set_database(const Ref<CgameMotionMatchingDatabase> &p_database);
	Ref<CgameMotionMatchingDatabase> get_database() const;
	void set_clip_animations(const Dictionary &p_map);
	Dictionary get_clip_animations() const;
	void set_required_tags(const PackedStringArray &p_tags);
	PackedStringArray get_required_tags() const;
	void set_search_interval(float p_interval);
	float get_search_interval() const;
	void set_blend_time(float p_time);
	float get_blend_time() const;
	void set_use_brute_force(bool p_enabled);
	bool is_using_brute_force() const;

	AnimationNodeMotionMatching();
};
