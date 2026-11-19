/**************************************************************************/
/*  terrain_editor_plugin.cpp                                             */
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

#include "terrain_editor_plugin.h"

#include "core/input/input_event.h"
#include "core/object/callable_mp.h"
#include "editor/editor_undo_redo_manager.h"
#include "scene/3d/camera_3d.h"
#include "scene/gui/button.h"
#include "scene/gui/label.h"
#include "scene/gui/option_button.h"
#include "scene/gui/spin_box.h"
#include "scene/main/scene_tree.h"

#ifndef PHYSICS_3D_DISABLED
#include "../terrain_collision_3d.h"
#include "scene/3d/physics/static_body_3d.h"
#endif

void TerrainEditorPlugin::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		toolbar = memnew(HBoxContainer);

		paint_enabled = memnew(Button);
		paint_enabled->set_text("Paint Terrain");
		paint_enabled->set_tooltip_text("Enable terrain painting in the 3D viewport. Drag the left mouse button to sculpt.");
		paint_enabled->set_toggle_mode(true);
		paint_enabled->connect(SNAME("toggled"), callable_mp(this, &TerrainEditorPlugin::_paint_toggled));
		toolbar->add_child(paint_enabled);

		brush_mode = memnew(OptionButton);
		brush_mode->add_item("Raise", 0);
		brush_mode->add_item("Lower", 1);
		brush_mode->add_item("Smooth", 2);
		brush_mode->set_tooltip_text("Terrain brush mode");
		toolbar->add_child(brush_mode);

		Label *radius_label = memnew(Label);
		radius_label->set_text("Radius");
		toolbar->add_child(radius_label);

		brush_radius = memnew(SpinBox);
		brush_radius->set_min(0.5);
		brush_radius->set_max(100.0);
		brush_radius->set_step(0.5);
		brush_radius->set_value(4.0);
		brush_radius->set_tooltip_text("Brush radius in heightmap cells");
		toolbar->add_child(brush_radius);

		Label *strength_label = memnew(Label);
		strength_label->set_text("Strength");
		toolbar->add_child(strength_label);

		brush_strength = memnew(SpinBox);
		brush_strength->set_min(0.01);
		brush_strength->set_max(10.0);
		brush_strength->set_step(0.1);
		brush_strength->set_value(1.0);
		brush_strength->set_tooltip_text("Height change per brush sample; smoothing is limited to 1.0");
		toolbar->add_child(brush_strength);

#ifndef PHYSICS_3D_DISABLED
		Button *make_collider = memnew(Button);
		make_collider->set_text("Add Collider");
		make_collider->set_tooltip_text("Create a StaticBody3D child with an auto-updating TerrainCollision3D.");
		make_collider->connect(SNAME("pressed"), callable_mp(this, &TerrainEditorPlugin::_create_collision));
		toolbar->add_child(make_collider);
#endif

		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar);
		toolbar->hide();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		_finish_stroke();
		if (toolbar != nullptr) {
			remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar);
			memdelete(toolbar);
			toolbar = nullptr;
		}
		edited_instance = nullptr;
		terrain.unref();
	}
}

bool TerrainEditorPlugin::handles(Object *p_object) const {
	const MeshInstance3D *instance = Object::cast_to<MeshInstance3D>(p_object);
	if (instance == nullptr) {
		return false;
	}
	const Ref<Mesh> mesh = instance->get_mesh();
	return mesh.is_valid() && Object::cast_to<TerrainMesh>(mesh.ptr()) != nullptr;
}

void TerrainEditorPlugin::edit(Object *p_object) {
	_finish_stroke();
	edited_instance = Object::cast_to<MeshInstance3D>(p_object);
	terrain.unref();
	if (edited_instance != nullptr && edited_instance->get_mesh().is_valid()) {
		TerrainMesh *resource = Object::cast_to<TerrainMesh>(edited_instance->get_mesh().ptr());
		if (resource != nullptr) {
			terrain = Ref<TerrainMesh>(resource);
		}
	}
	if (toolbar != nullptr) {
		toolbar->set_visible(plugin_visible && terrain.is_valid());
	}
}

void TerrainEditorPlugin::make_visible(bool p_visible) {
	plugin_visible = p_visible;
	if (!p_visible) {
		_finish_stroke();
		if (paint_enabled != nullptr) {
			paint_enabled->set_pressed(false);
		}
	}
	if (toolbar != nullptr) {
		toolbar->set_visible(p_visible && terrain.is_valid());
	}
}

void TerrainEditorPlugin::_paint_toggled(bool p_enabled) {
	if (!p_enabled) {
		_finish_stroke();
	}
}

#ifndef PHYSICS_3D_DISABLED

void TerrainEditorPlugin::_create_collision() {
	if (edited_instance == nullptr || terrain.is_null() || get_tree() == nullptr) {
		return;
	}
	Node *scene_root = get_tree()->get_edited_scene_root();
	if (scene_root == nullptr) {
		return;
	}

	// Creating the body as a child of MeshInstance3D means its transform always
	// follows the visual mesh, even if the parent is later moved or rotated.
	StaticBody3D *body = memnew(StaticBody3D);
	body->set_name("TerrainStaticBody3D");
	TerrainCollision3D *collider = memnew(TerrainCollision3D);
	collider->set_name("TerrainCollision3D");
	collider->set_terrain(terrain);
	body->add_child(collider);

	EditorUndoRedoManager *undo_redo = get_undo_redo();
	undo_redo->create_action("Add Terrain Collider");
	undo_redo->add_do_method(edited_instance, "add_child", body);
	undo_redo->add_do_method(body, "set_owner", scene_root);
	undo_redo->add_do_method(collider, "set_owner", scene_root);
	undo_redo->add_undo_method(edited_instance, "remove_child", body);
	undo_redo->add_do_reference(body);
	undo_redo->commit_action();
}

#endif // PHYSICS_3D_DISABLED

void TerrainEditorPlugin::clear() {
	_finish_stroke();
	edited_instance = nullptr;
	terrain.unref();
	if (paint_enabled != nullptr) {
		paint_enabled->set_pressed(false);
	}
	if (toolbar != nullptr) {
		toolbar->hide();
	}
}

bool TerrainEditorPlugin::_pick_position(Camera3D *p_camera, const Vector2 &p_screen_position, Vector2 &r_grid_position) const {
	if (p_camera == nullptr || edited_instance == nullptr || terrain.is_null()) {
		return false;
	}
	const Vector3 world_origin = p_camera->project_ray_origin(p_screen_position);
	const Vector3 world_end = world_origin + p_camera->project_ray_normal(p_screen_position) * p_camera->get_far();
	const Transform3D local_from_world = edited_instance->get_global_transform().affine_inverse();
	const Vector3 local_origin = local_from_world.xform(world_origin);
	const Vector3 local_end = local_from_world.xform(world_end);
	Vector3 hit;
	if (!terrain->intersect_segment(local_origin, local_end, hit)) {
		return false;
	}
	r_grid_position = Vector2(hit.x / terrain->get_cell_size(), hit.z / terrain->get_cell_size());
	return true;
}

bool TerrainEditorPlugin::_apply_brush(Camera3D *p_camera, const Vector2 &p_screen_position) {
	if (terrain.is_null() || terrain != stroke_terrain) {
		return false;
	}
	Vector2 grid_position;
	if (!_pick_position(p_camera, p_screen_position, grid_position)) {
		return false;
	}
	if (stroke_has_position && last_stroke_position.distance_to(grid_position) < 0.25f) {
		return true;
	}
	last_stroke_position = grid_position;
	stroke_has_position = true;
	const float radius = float(brush_radius->get_value());
	const float strength = float(brush_strength->get_value());
	switch (brush_mode->get_selected_id()) {
		case 0:
			terrain->sculpt(grid_position, radius, strength);
			break;
		case 1:
			terrain->sculpt(grid_position, radius, -strength);
			break;
		case 2:
			terrain->smooth(grid_position, radius, MIN(strength, 1.0f));
			break;
	}
	return true;
}

void TerrainEditorPlugin::_finish_stroke() {
	if (!stroke_active) {
		return;
	}
	stroke_active = false;
	stroke_has_position = false;
	if (stroke_terrain.is_valid()) {
		const PackedFloat32Array after = stroke_terrain->get_heights();
		if (after != stroke_before) {
			EditorUndoRedoManager *undo_redo = get_undo_redo();
			undo_redo->create_action("Terrain Brush Stroke");
			undo_redo->add_do_method(stroke_terrain.ptr(), "set_heights", after);
			undo_redo->add_undo_method(stroke_terrain.ptr(), "set_heights", stroke_before);
			// The brush already applied the new heights during the drag.
			undo_redo->commit_action(false);
		}
	}
	stroke_before.clear();
	stroke_terrain.unref();
}

EditorPlugin::AfterGUIInput TerrainEditorPlugin::forward_3d_gui_input(Camera3D *p_camera, const Ref<InputEvent> &p_event) {
	if (terrain.is_null() || edited_instance == nullptr || paint_enabled == nullptr || !paint_enabled->is_pressed()) {
		return AFTER_GUI_INPUT_PASS;
	}

	Ref<InputEventMouseButton> click = p_event;
	if (click.is_valid() && click->get_button_index() == MouseButton::LEFT) {
		if (click->is_pressed()) {
			if (click->is_alt_pressed() || click->is_command_or_control_pressed()) {
				return AFTER_GUI_INPUT_PASS; // Preserve viewport navigation shortcuts.
			}
			if (stroke_active) {
				return AFTER_GUI_INPUT_STOP;
			}
			stroke_terrain = terrain;
			stroke_has_position = false;
			stroke_before = terrain->get_heights();
			if (_apply_brush(p_camera, click->get_position())) {
				stroke_active = true;
				return AFTER_GUI_INPUT_STOP;
			}
			stroke_before.clear();
			stroke_terrain.unref();
			return AFTER_GUI_INPUT_PASS;
		}
		if (stroke_active) {
			_finish_stroke();
			return AFTER_GUI_INPUT_STOP;
		}
	}
	Ref<InputEventMouseMotion> motion = p_event;
	if (motion.is_valid() && stroke_active) {
		if (!motion->get_button_mask().has_flag(MouseButtonMask::LEFT)) {
			_finish_stroke();
			return AFTER_GUI_INPUT_PASS;
		}
		_apply_brush(p_camera, motion->get_position());
		return AFTER_GUI_INPUT_STOP;
	}
	return AFTER_GUI_INPUT_PASS;
}
