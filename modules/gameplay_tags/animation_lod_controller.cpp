/**************************************************************************/
/*  animation_lod_controller.cpp                                          */
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


#include "animation_lod_controller.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "scene/3d/camera_3d.h"
#include "scene/3d/node_3d.h"
#include "scene/3d/skeleton_modifier_3d.h"
#include "scene/main/viewport.h"

int AnimationLODController::update_interval(real_t p_distance, bool p_visible, real_t p_near, real_t p_mid, real_t p_far) {
	if (!p_visible) {
		return 0;
	}
	if (p_distance < p_near) {
		return 1;
	}
	if (p_distance < p_mid) {
		return 2;
	}
	if (p_distance < p_far) {
		return 4;
	}
	return 0;
}

void AnimationLODController::_restore_entry(Entry &r_entry) {
	AnimationMixer *mixer = ObjectDB::get_instance<AnimationMixer>(r_entry.mixer_id);
	if (mixer) {
		mixer->set_callback_mode_process(r_entry.original_mode);
		_set_modifiers_culled(r_entry, mixer, false);
	}
	r_entry.accumulated = 0.0;
}

void AnimationLODController::_set_modifiers_culled(Entry &r_entry, AnimationMixer *p_mixer, bool p_culled) {
	if (p_culled == r_entry.modifiers_culled) {
		return;
	}
	if (p_culled) {
		r_entry.disabled_modifiers.clear();
		Node *root = p_mixer->get_node_or_null(p_mixer->get_root_node());
		if (root) {
			TypedArray<Node> found = root->find_children("*", "SkeletonModifier3D", true, false);
			for (int i = 0; i < found.size(); i++) {
				SkeletonModifier3D *modifier = Object::cast_to<SkeletonModifier3D>(found[i]);
				if (modifier && modifier->is_active()) {
					modifier->set_active(false);
					r_entry.disabled_modifiers.push_back(modifier->get_instance_id());
				}
			}
		}
	} else {
		for (int i = 0; i < r_entry.disabled_modifiers.size(); i++) {
			SkeletonModifier3D *modifier = ObjectDB::get_instance<SkeletonModifier3D>(r_entry.disabled_modifiers[i]);
			if (modifier) {
				modifier->set_active(true);
			}
		}
		r_entry.disabled_modifiers.clear();
	}
	r_entry.modifiers_culled = p_culled;
}

void AnimationLODController::_update(double p_delta) {
	frame_counter++;

	Camera3D *camera = nullptr;
	Vector3 camera_pos;
	Viewport *viewport = get_viewport();
	if (viewport) {
		camera = viewport->get_camera_3d();
		if (camera) {
			camera_pos = camera->get_global_transform().origin;
		}
	}

	for (int i = 0; i < entries.size();) {
		Entry &entry = entries.write[i];
		AnimationMixer *mixer = ObjectDB::get_instance<AnimationMixer>(entry.mixer_id);
		if (!mixer) {
			entries.remove_at(i);
			continue;
		}
		i++;
		if (!mixer->is_inside_tree()) {
			continue;
		}

		// Nearest Node3D ancestor provides the world position.
		Node3D *spatial = nullptr;
		for (Node *n = mixer->get_parent(); n && !spatial; n = n->get_parent()) {
			spatial = Object::cast_to<Node3D>(n);
		}

		real_t distance = 0.0;
		bool visible = true;
		if (spatial) {
			const Vector3 pos = spatial->get_global_transform().origin;
			visible = spatial->is_visible_in_tree();
			if (camera) {
				distance = camera_pos.distance_to(pos);
				// Characters within a few meters are always considered visible (point test would flicker at screen edges).
				if (visible && cull_offscreen && distance > 3.0 && !camera->is_position_in_frustum(pos + Vector3(0, 1, 0))) {
					visible = false;
				}
			}
		}

		const bool want_modifier_cull = modifier_cull_distance > 0.0 && (!visible || distance > modifier_cull_distance);
		_set_modifiers_culled(entry, mixer, want_modifier_cull);

		const int interval = update_interval(distance, visible, near_distance, mid_distance, far_distance);
		if (interval == 0) {
			continue; // Paused; keep animation state untouched.
		}

		entry.accumulated = MIN(entry.accumulated + p_delta, max_accumulated_delta);
		if ((frame_counter + entry.phase) % (uint32_t)interval == 0) {
			if (mixer->is_active()) {
				mixer->advance(entry.accumulated);
			}
			entry.accumulated = 0.0;
		}
	}
}

void AnimationLODController::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			if (!Engine::get_singleton()->is_editor_hint()) {
				set_process_internal(true);
				if (enabled) {
					for (int i = 0; i < entries.size(); i++) {
						AnimationMixer *mixer = ObjectDB::get_instance<AnimationMixer>(entries[i].mixer_id);
						if (mixer) {
							mixer->set_callback_mode_process(AnimationMixer::ANIMATION_CALLBACK_MODE_PROCESS_MANUAL);
						}
					}
				}
			}
		} break;
		case NOTIFICATION_EXIT_TREE: {
			set_process_internal(false);
			for (int i = 0; i < entries.size(); i++) {
				_restore_entry(entries.write[i]);
			}
		} break;
		case NOTIFICATION_INTERNAL_PROCESS: {
			if (enabled) {
				_update(get_process_delta_time());
			}
		} break;
	}
}

void AnimationLODController::register_mixer(AnimationMixer *p_mixer) {
	ERR_FAIL_NULL(p_mixer);
	const ObjectID id = p_mixer->get_instance_id();
	for (int i = 0; i < entries.size(); i++) {
		if (entries[i].mixer_id == id) {
			return;
		}
	}
	Entry entry;
	entry.mixer_id = id;
	entry.original_mode = p_mixer->get_callback_mode_process();
	entry.phase = next_phase++;
	entries.push_back(entry);
	if (enabled && is_inside_tree()) {
		p_mixer->set_callback_mode_process(AnimationMixer::ANIMATION_CALLBACK_MODE_PROCESS_MANUAL);
	}
}

void AnimationLODController::unregister_mixer(AnimationMixer *p_mixer) {
	ERR_FAIL_NULL(p_mixer);
	const ObjectID id = p_mixer->get_instance_id();
	for (int i = 0; i < entries.size(); i++) {
		if (entries[i].mixer_id == id) {
			_restore_entry(entries.write[i]);
			entries.remove_at(i);
			return;
		}
	}
}

void AnimationLODController::clear_mixers() {
	for (int i = 0; i < entries.size(); i++) {
		_restore_entry(entries.write[i]);
	}
	entries.clear();
}

void AnimationLODController::set_enabled(bool p_enabled) {
	if (enabled == p_enabled) {
		return;
	}
	enabled = p_enabled;
	for (int i = 0; i < entries.size(); i++) {
		if (enabled) {
			AnimationMixer *mixer = ObjectDB::get_instance<AnimationMixer>(entries[i].mixer_id);
			if (mixer && is_inside_tree()) {
				mixer->set_callback_mode_process(AnimationMixer::ANIMATION_CALLBACK_MODE_PROCESS_MANUAL);
			}
		} else {
			_restore_entry(entries.write[i]);
		}
	}
}

void AnimationLODController::_bind_methods() {
	ClassDB::bind_static_method("AnimationLODController", D_METHOD("update_interval", "distance", "visible", "near", "mid", "far"), &AnimationLODController::update_interval);

	ClassDB::bind_method(D_METHOD("register_mixer", "mixer"), &AnimationLODController::register_mixer);
	ClassDB::bind_method(D_METHOD("unregister_mixer", "mixer"), &AnimationLODController::unregister_mixer);
	ClassDB::bind_method(D_METHOD("clear_mixers"), &AnimationLODController::clear_mixers);
	ClassDB::bind_method(D_METHOD("get_mixer_count"), &AnimationLODController::get_mixer_count);

	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &AnimationLODController::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &AnimationLODController::is_enabled);
	ClassDB::bind_method(D_METHOD("set_near_distance", "distance"), &AnimationLODController::set_near_distance);
	ClassDB::bind_method(D_METHOD("get_near_distance"), &AnimationLODController::get_near_distance);
	ClassDB::bind_method(D_METHOD("set_mid_distance", "distance"), &AnimationLODController::set_mid_distance);
	ClassDB::bind_method(D_METHOD("get_mid_distance"), &AnimationLODController::get_mid_distance);
	ClassDB::bind_method(D_METHOD("set_far_distance", "distance"), &AnimationLODController::set_far_distance);
	ClassDB::bind_method(D_METHOD("get_far_distance"), &AnimationLODController::get_far_distance);
	ClassDB::bind_method(D_METHOD("set_modifier_cull_distance", "distance"), &AnimationLODController::set_modifier_cull_distance);
	ClassDB::bind_method(D_METHOD("get_modifier_cull_distance"), &AnimationLODController::get_modifier_cull_distance);
	ClassDB::bind_method(D_METHOD("set_cull_offscreen", "cull"), &AnimationLODController::set_cull_offscreen);
	ClassDB::bind_method(D_METHOD("is_cull_offscreen"), &AnimationLODController::is_cull_offscreen);
	ClassDB::bind_method(D_METHOD("set_max_accumulated_delta", "seconds"), &AnimationLODController::set_max_accumulated_delta);
	ClassDB::bind_method(D_METHOD("get_max_accumulated_delta"), &AnimationLODController::get_max_accumulated_delta);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "near_distance", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:m"), "set_near_distance", "get_near_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mid_distance", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:m"), "set_mid_distance", "get_mid_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "far_distance", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:m"), "set_far_distance", "get_far_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "modifier_cull_distance", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:m"), "set_modifier_cull_distance", "get_modifier_cull_distance");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cull_offscreen"), "set_cull_offscreen", "is_cull_offscreen");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_accumulated_delta", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater,suffix:s"), "set_max_accumulated_delta", "get_max_accumulated_delta");
}
