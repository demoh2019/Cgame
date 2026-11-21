/**************************************************************************/
/*  animation_node_motion_matching.cpp                                    */
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

#include "animation_node_motion_matching.h"

#include "core/object/class_db.h"

StringName AnimationNodeMotionMatching::_animation_for_clip(int p_clip) const {
	const String clip_name = database->get_clip_name(p_clip);
	if (clip_animations.has(clip_name)) {
		return StringName(String(clip_animations[clip_name]));
	}
	return StringName(clip_name);
}

void AnimationNodeMotionMatching::get_parameter_list(LocalVector<PropertyInfo> *r_list) const {
	AnimationRootNode::get_parameter_list(r_list);
	r_list->push_back(PropertyInfo(Variant::VECTOR2, p_velocity));
	r_list->push_back(PropertyInfo(Variant::FLOAT, p_facing));
	r_list->push_back(PropertyInfo(Variant::VECTOR2, p_desired_velocity));
	r_list->push_back(PropertyInfo(Variant::FLOAT, p_desired_facing));
	r_list->push_back(PropertyInfo(Variant::VECTOR3, p_left_foot));
	r_list->push_back(PropertyInfo(Variant::VECTOR3, p_right_foot));
	r_list->push_back(PropertyInfo(Variant::VECTOR3, p_left_foot_velocity));
	r_list->push_back(PropertyInfo(Variant::VECTOR3, p_right_foot_velocity));
	r_list->push_back(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, p_features));
	r_list->push_back(PropertyInfo(Variant::STRING, p_current_clip, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR));
	r_list->push_back(PropertyInfo(Variant::FLOAT, p_last_cost, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR));
	r_list->push_back(PropertyInfo(Variant::FLOAT, p_current_time, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE));
	r_list->push_back(PropertyInfo(Variant::STRING, p_previous_clip, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE));
	r_list->push_back(PropertyInfo(Variant::FLOAT, p_previous_time, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE));
	r_list->push_back(PropertyInfo(Variant::FLOAT, p_blend_elapsed, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE));
	r_list->push_back(PropertyInfo(Variant::FLOAT, p_search_timer, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE));
}

Variant AnimationNodeMotionMatching::get_parameter_default_value(const StringName &p_parameter) const {
	Variant ret = AnimationRootNode::get_parameter_default_value(p_parameter);
	if (ret != Variant()) {
		return ret;
	}
	if (p_parameter == p_velocity || p_parameter == p_desired_velocity) {
		return Vector2();
	}
	if (p_parameter == p_facing || p_parameter == p_desired_facing || p_parameter == p_current_time || p_parameter == p_previous_time || p_parameter == p_blend_elapsed || p_parameter == p_search_timer || p_parameter == p_last_cost) {
		return 0.0;
	}
	if (p_parameter == p_left_foot || p_parameter == p_right_foot || p_parameter == p_left_foot_velocity || p_parameter == p_right_foot_velocity) {
		return Vector3();
	}
	if (p_parameter == p_features) {
		return PackedFloat32Array();
	}
	return String();
}

bool AnimationNodeMotionMatching::is_parameter_read_only(const StringName &p_parameter) const {
	if (AnimationRootNode::is_parameter_read_only(p_parameter)) {
		return true;
	}
	return p_parameter == p_current_clip || p_parameter == p_last_cost;
}

AnimationNode::NodeTimeInfo AnimationNodeMotionMatching::_process(ProcessState &p_process_state, AnimationNodeInstance &p_instance, const AnimationMixer::PlaybackInfo &p_playback_info, bool p_test_only) {
	if (database.is_null() || !database->is_built() || database->get_frame_count() == 0) {
		if (!p_test_only && p_instance.is_blended()) {
			make_invalid(p_process_state, p_instance, RTR("Motion matching database is missing, empty or not built."));
		}
		return NodeTimeInfo();
	}

	const double delta = p_playback_info.delta;
	String cur_clip_name = p_instance.get_parameter(p_current_clip);
	int cur_idx = database->find_clip(cur_clip_name);
	double cur_t = p_instance.get_parameter(p_current_time);
	String prev_clip_name = p_instance.get_parameter(p_previous_clip);
	int prev_idx = database->find_clip(prev_clip_name);
	double prev_t = p_instance.get_parameter(p_previous_time);
	double blend_elapsed = p_instance.get_parameter(p_blend_elapsed);
	double timer = double(p_instance.get_parameter(p_search_timer)) + delta;
	float last_cost = p_instance.get_parameter(p_last_cost);

	bool jumped = false;
	const bool first = cur_idx < 0;
	if (first || timer >= search_interval) {
		timer = 0.0;
		Vector<float> query;
		const PackedFloat32Array custom = p_instance.get_parameter(p_features);
		if (custom.size() == CgameMotionMatchingDatabase::DIMS) {
			query.resize(custom.size());
			for (int i = 0; i < custom.size(); i++) {
				query.write[i] = custom[i];
			}
		} else {
			query = database->query_features_from(p_instance.get_parameter(p_velocity), p_instance.get_parameter(p_facing), p_instance.get_parameter(p_desired_velocity), p_instance.get_parameter(p_desired_facing), p_instance.get_parameter(p_left_foot), p_instance.get_parameter(p_right_foot), p_instance.get_parameter(p_left_foot_velocity), p_instance.get_parameter(p_right_foot_velocity));
		}
		const int cur_frame = first ? -1 : int(Math::floor(cur_t * database->get_clip_fps(cur_idx)));
		const CgameMotionMatchingDatabase::SearchResult res = database->search_native(query, cur_idx, cur_frame, required_tags, !use_brute_force);
		if (res.clip >= 0) {
			last_cost = res.cost;
			const double target_t = double(res.frame) / MAX(database->get_clip_fps(res.clip), 0.001f);
			if (first) {
				cur_idx = res.clip;
				cur_t = target_t;
				prev_idx = -1;
				jumped = true;
			} else if (!res.continuing) {
				prev_idx = cur_idx;
				prev_t = cur_t;
				cur_idx = res.clip;
				cur_t = target_t;
				blend_elapsed = 0.0;
				jumped = true;
			}
		}
	}
	if (cur_idx < 0) {
		return NodeTimeInfo();
	}

	// Advance both playheads.
	cur_t += delta;
	prev_t += delta;
	blend_elapsed += delta;
	auto clip_length = [&](int p_clip) -> double {
		const StringName anim_name = _animation_for_clip(p_clip);
		if (p_process_state.tree && p_process_state.tree->has_animation(anim_name)) {
			const double l = p_process_state.tree->get_animation(anim_name)->get_length();
			if (l > CMP_EPSILON) {
				return l;
			}
		}
		return double(database->get_clip_frame_count(p_clip)) / MAX(database->get_clip_fps(p_clip), 0.001f);
	};
	const double cur_len = clip_length(cur_idx);
	Animation::LoopedFlag looped = Animation::LOOPED_FLAG_NONE;
	if (database->is_clip_looping(cur_idx)) {
		if (cur_len > CMP_EPSILON && cur_t >= cur_len) {
			looped = Animation::LOOPED_FLAG_END;
		}
		cur_t = cur_len > CMP_EPSILON ? Math::fposmod(cur_t, cur_len) : 0.0;
	} else {
		cur_t = MIN(cur_t, cur_len);
	}
	double prev_len = 0.0;
	if (prev_idx >= 0) {
		prev_len = clip_length(prev_idx);
		prev_t = database->is_clip_looping(prev_idx) && prev_len > CMP_EPSILON ? Math::fposmod(prev_t, prev_len) : MIN(prev_t, prev_len);
	}

	if (!p_test_only) {
		double w = 1.0;
		if (prev_idx >= 0) {
			if (blend_time > CMP_EPSILON && blend_elapsed < blend_time) {
				w = Math::smoothstep(0.0, 1.0, blend_elapsed / blend_time);
			} else {
				prev_idx = -1; // Blend finished.
			}
		}
		const StringName cur_anim = _animation_for_clip(cur_idx);
		if (p_process_state.tree && p_process_state.tree->has_animation(cur_anim)) {
			AnimationMixer::PlaybackInfo pi = p_playback_info;
			pi.start = 0.0;
			pi.end = cur_len;
			pi.time = cur_t;
			pi.delta = jumped ? 0.0 : delta;
			pi.seeked = jumped;
			pi.weight = w * p_playback_info.weight;
			pi.looped_flag = looped;
			blend_animation(p_process_state, p_instance, cur_anim, pi);
		} else if (p_instance.is_blended()) {
			make_invalid(p_process_state, p_instance, vformat(RTR("Animation '%s' not found."), cur_anim));
		}
		if (prev_idx >= 0) {
			const StringName prev_anim = _animation_for_clip(prev_idx);
			if (p_process_state.tree && p_process_state.tree->has_animation(prev_anim)) {
				AnimationMixer::PlaybackInfo pi = p_playback_info;
				pi.start = 0.0;
				pi.end = prev_len;
				pi.time = prev_t;
				pi.delta = delta;
				pi.seeked = false;
				pi.weight = (1.0 - w) * p_playback_info.weight;
				blend_animation(p_process_state, p_instance, prev_anim, pi);
			}
		}

		p_instance.set_parameter(p_current_clip, database->get_clip_name(cur_idx), p_process_state.is_testing);
		p_instance.set_parameter(p_current_time, cur_t, p_process_state.is_testing);
		p_instance.set_parameter(p_previous_clip, prev_idx >= 0 ? database->get_clip_name(prev_idx) : String(), p_process_state.is_testing);
		p_instance.set_parameter(p_previous_time, prev_t, p_process_state.is_testing);
		p_instance.set_parameter(p_blend_elapsed, blend_elapsed, p_process_state.is_testing);
		p_instance.set_parameter(p_search_timer, timer, p_process_state.is_testing);
		p_instance.set_parameter(p_last_cost, last_cost, p_process_state.is_testing);
	}

	NodeTimeInfo nti;
	nti.length = cur_len;
	nti.position = cur_t;
	nti.delta = delta;
	nti.loop_mode = database->is_clip_looping(cur_idx) ? Animation::LOOP_LINEAR : Animation::LOOP_NONE;
	nti.will_end = looped != Animation::LOOPED_FLAG_NONE;
	return nti;
}

String AnimationNodeMotionMatching::get_caption() const {
	return "Motion Matching";
}

void AnimationNodeMotionMatching::set_database(const Ref<CgameMotionMatchingDatabase> &p_database) {
	database = p_database;
	emit_changed();
}

Ref<CgameMotionMatchingDatabase> AnimationNodeMotionMatching::get_database() const {
	return database;
}

void AnimationNodeMotionMatching::set_clip_animations(const Dictionary &p_map) {
	clip_animations = p_map;
}

Dictionary AnimationNodeMotionMatching::get_clip_animations() const {
	return clip_animations;
}

void AnimationNodeMotionMatching::set_required_tags(const PackedStringArray &p_tags) {
	required_tags = p_tags;
}

PackedStringArray AnimationNodeMotionMatching::get_required_tags() const {
	return required_tags;
}

void AnimationNodeMotionMatching::set_search_interval(float p_interval) {
	search_interval = MAX(p_interval, 0.0f);
}

float AnimationNodeMotionMatching::get_search_interval() const {
	return search_interval;
}

void AnimationNodeMotionMatching::set_blend_time(float p_time) {
	blend_time = MAX(p_time, 0.0f);
}

float AnimationNodeMotionMatching::get_blend_time() const {
	return blend_time;
}

void AnimationNodeMotionMatching::set_use_brute_force(bool p_enabled) {
	use_brute_force = p_enabled;
}

bool AnimationNodeMotionMatching::is_using_brute_force() const {
	return use_brute_force;
}

void AnimationNodeMotionMatching::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_database", "database"), &AnimationNodeMotionMatching::set_database);
	ClassDB::bind_method(D_METHOD("get_database"), &AnimationNodeMotionMatching::get_database);
	ClassDB::bind_method(D_METHOD("set_clip_animations", "clip_animations"), &AnimationNodeMotionMatching::set_clip_animations);
	ClassDB::bind_method(D_METHOD("get_clip_animations"), &AnimationNodeMotionMatching::get_clip_animations);
	ClassDB::bind_method(D_METHOD("set_required_tags", "tags"), &AnimationNodeMotionMatching::set_required_tags);
	ClassDB::bind_method(D_METHOD("get_required_tags"), &AnimationNodeMotionMatching::get_required_tags);
	ClassDB::bind_method(D_METHOD("set_search_interval", "interval"), &AnimationNodeMotionMatching::set_search_interval);
	ClassDB::bind_method(D_METHOD("get_search_interval"), &AnimationNodeMotionMatching::get_search_interval);
	ClassDB::bind_method(D_METHOD("set_blend_time", "time"), &AnimationNodeMotionMatching::set_blend_time);
	ClassDB::bind_method(D_METHOD("get_blend_time"), &AnimationNodeMotionMatching::get_blend_time);
	ClassDB::bind_method(D_METHOD("set_use_brute_force", "enabled"), &AnimationNodeMotionMatching::set_use_brute_force);
	ClassDB::bind_method(D_METHOD("is_using_brute_force"), &AnimationNodeMotionMatching::is_using_brute_force);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "database", PROPERTY_HINT_RESOURCE_TYPE, "CgameMotionMatchingDatabase"), "set_database", "get_database");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "clip_animations"), "set_clip_animations", "get_clip_animations");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "required_tags"), "set_required_tags", "get_required_tags");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "search_interval", PROPERTY_HINT_RANGE, "0.0,1.0,0.001,or_greater,suffix:s"), "set_search_interval", "get_search_interval");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "blend_time", PROPERTY_HINT_RANGE, "0.0,1.0,0.001,or_greater,suffix:s"), "set_blend_time", "get_blend_time");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_brute_force"), "set_use_brute_force", "is_using_brute_force");
}

AnimationNodeMotionMatching::AnimationNodeMotionMatching() {
}
