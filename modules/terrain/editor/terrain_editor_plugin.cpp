/**************************************************************************/
/*  terrain_editor_plugin.cpp                                             */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/**************************************************************************/

#include "terrain_editor_plugin.h"

#include "core/input/input_event.h"
#include "core/math/math_funcs.h"
#include "editor/editor_undo_redo_manager.h"
#include "scene/3d/camera_3d.h"
#include "scene/gui/box_container.h"
#include "scene/gui/color_picker.h"
#include "scene/gui/option_button.h"
#include "scene/gui/spin_box.h"

bool Terrain3DEditorPlugin::handles(Object *p_object) const {
	return Object::cast_to<HeightmapTerrain3D>(p_object) != nullptr;
}

void Terrain3DEditorPlugin::edit(Object *p_object) {
	_commit_stroke();
	terrain = Object::cast_to<HeightmapTerrain3D>(p_object);
	toolbar->set_visible(terrain != nullptr);
}

void Terrain3DEditorPlugin::make_visible(bool p_visible) {
	if (!p_visible) {
		_commit_stroke();
	}
	toolbar->set_visible(p_visible && terrain != nullptr);
}

// Intersects the editor ray against a sampled heightfield rather than the
// y=0 plane, so sculpting works on hills without a physics body.
bool Terrain3DEditorPlugin::_pick_terrain(Camera3D *p_camera, const Vector2 &p_screen_position, Vector2 &r_grid_position) const {
	if (!terrain || !p_camera) {
		return false;
	}
	const Transform3D inverse = terrain->get_global_transform().affine_inverse();
	const Vector3 origin = inverse.xform(p_camera->project_ray_origin(p_screen_position));
	const Vector3 direction = inverse.basis.xform(p_camera->project_ray_normal(p_screen_position)).normalized();
	const Vector2i size = terrain->get_grid_size();
	const real_t cell_size = terrain->get_cell_size();

	const PackedFloat32Array heights = terrain->get_height_data();
	if (heights.is_empty()) {
		return false;
	}
	float min_height = heights[0];
	float max_height = heights[0];
	for (int i = 1; i < heights.size(); i++) {
		min_height = MIN(min_height, heights[i]);
		max_height = MAX(max_height, heights[i]);
	}

	real_t entry = 0.0;
	real_t exit = 100000.0;
	auto slab = [&entry, &exit](real_t p_origin, real_t p_direction, real_t p_min, real_t p_max) {
		if (Math::is_zero_approx(p_direction)) {
			return p_origin >= p_min && p_origin <= p_max;
		}
		real_t a = (p_min - p_origin) / p_direction;
		real_t b = (p_max - p_origin) / p_direction;
		if (a > b) {
			SWAP(a, b);
		}
		entry = MAX(entry, a);
		exit = MIN(exit, b);
		return entry <= exit;
	};
	if (!slab(origin.x, direction.x, 0, (size.x - 1) * cell_size) ||
			!slab(origin.y, direction.y, min_height - 0.01, max_height + 0.01) ||
			!slab(origin.z, direction.z, 0, (size.y - 1) * cell_size) ||
			exit < entry) {
		return false;
	}
	const int steps = MIN(4096, MAX(32, (int)Math::ceil((exit - entry) / cell_size * 4.0)));
	const auto height_difference = [this, &origin, &direction, cell_size](real_t p_time) {
		const Vector3 point = origin + direction * p_time;
		const Vector2i size = terrain->get_grid_size();
		return point.y - terrain->sample_height(Vector2(CLAMP(point.x / cell_size, 0.0, (real_t)(size.x - 1)), CLAMP(point.z / cell_size, 0.0, (real_t)(size.y - 1))));
	};
	real_t previous_time = entry;
	real_t previous_difference = height_difference(previous_time);
	for (int i = 1; i <= steps; i++) {
		real_t time = Math::lerp(entry, exit, (real_t)i / steps);
		real_t difference = height_difference(time);
		if (previous_difference >= 0.0 && difference <= 0.0) {
			real_t low = previous_time;
			real_t high = time;
			for (int refine = 0; refine < 12; refine++) {
				const real_t middle = (low + high) * 0.5;
				if (height_difference(middle) > 0.0) {
					low = middle;
				} else {
					high = middle;
				}
			}
			const Vector3 hit = origin + direction * ((low + high) * 0.5);
			r_grid_position = Vector2(hit.x / cell_size, hit.z / cell_size);
			return true;
		}
		previous_time = time;
		previous_difference = difference;
	}
	return false;
}

void Terrain3DEditorPlugin::_apply_at(const Vector2 &p_grid_position) {
	const real_t r = radius->get_value();
	const real_t value = strength->get_value();
	switch (drag_mode) {
		case BRUSH_RAISE:
			terrain->sculpt(p_grid_position, r, value * 0.05);
			break;
		case BRUSH_LOWER:
			terrain->sculpt(p_grid_position, r, -value * 0.05);
			break;
		case BRUSH_SMOOTH:
			terrain->smooth(p_grid_position, r, value * 0.05);
			break;
		case BRUSH_COLOR:
			terrain->paint_color(p_grid_position, r, color->get_pick_color(), value * 0.05);
			break;
		case BRUSH_NAVIGATE:
			break;
	}
}

void Terrain3DEditorPlugin::_commit_stroke() {
	if (!dragging) {
		return;
	}
	dragging = false;
	if (!terrain) {
		return;
	}
	EditorUndoRedoManager *undo_redo = EditorUndoRedoManager::get_singleton();
	if (drag_mode == BRUSH_COLOR) {
		const PackedColorArray after = terrain->get_color_data();
		if (after == undo_colors) {
			return;
		}
		undo_redo->create_action("Paint Terrain", UndoRedo::MERGE_DISABLE, terrain);
		undo_redo->add_do_method(terrain, "set_color_data", after);
		undo_redo->add_undo_method(terrain, "set_color_data", undo_colors);
	} else {
		const PackedFloat32Array after = terrain->get_height_data();
		if (after == undo_heights) {
			return;
		}
		undo_redo->create_action("Sculpt Terrain", UndoRedo::MERGE_DISABLE, terrain);
		undo_redo->add_do_method(terrain, "set_height_data", after);
		undo_redo->add_undo_method(terrain, "set_height_data", undo_heights);
	}
	undo_redo->commit_action();
}

EditorPlugin::AfterGUIInput Terrain3DEditorPlugin::forward_3d_gui_input(Camera3D *p_camera, const Ref<InputEvent> &p_event) {
	if (!terrain || !toolbar->is_visible() || mode->get_selected_id() == BRUSH_NAVIGATE) {
		return AFTER_GUI_INPUT_PASS;
	}
	const Ref<InputEventMouseButton> button = p_event;
	if (button.is_valid() && button->get_button_index() == MouseButton::LEFT) {
		if (!button->is_pressed()) {
			if (dragging) {
				_commit_stroke();
				return AFTER_GUI_INPUT_STOP;
			}
			return AFTER_GUI_INPUT_PASS;
		}
		Vector2 grid_point;
		if (!_pick_terrain(p_camera, button->get_position(), grid_point)) {
			return AFTER_GUI_INPUT_PASS;
		}
		dragging = true;
		drag_mode = (BrushMode)mode->get_selected_id();
		undo_heights = terrain->get_height_data();
		undo_colors = terrain->get_color_data();
		_apply_at(grid_point);
		return AFTER_GUI_INPUT_STOP;
	}
	const Ref<InputEventMouseMotion> motion = p_event;
	if (motion.is_valid() && dragging) {
		Vector2 grid_point;
		if (_pick_terrain(p_camera, motion->get_position(), grid_point)) {
			_apply_at(grid_point);
		}
		return AFTER_GUI_INPUT_STOP;
	}
	return AFTER_GUI_INPUT_PASS;
}

Terrain3DEditorPlugin::Terrain3DEditorPlugin() {
	toolbar = memnew(HBoxContainer);
	mode = memnew(OptionButton);
	mode->add_item("Navigate", BRUSH_NAVIGATE);
	mode->add_item("Raise", BRUSH_RAISE);
	mode->add_item("Lower", BRUSH_LOWER);
	mode->add_item("Smooth", BRUSH_SMOOTH);
	mode->add_item("Paint Color", BRUSH_COLOR);
	mode->select(0);
	toolbar->add_child(mode);

	radius = memnew(SpinBox);
	radius->set_min(0.5);
	radius->set_max(128.0);
	radius->set_step(0.5);
	radius->set_value(4.0);
	radius->set_accessibility_name("Terrain brush radius (grid cells)");
	toolbar->add_child(radius);

	strength = memnew(SpinBox);
	strength->set_min(0.01);
	strength->set_max(10.0);
	strength->set_step(0.1);
	strength->set_value(1.0);
	strength->set_accessibility_name("Terrain brush strength");
	toolbar->add_child(strength);

	color = memnew(ColorPickerButton);
	color->set_pick_color(Color(0.3, 0.6, 0.2));
	color->set_edit_alpha(false);
	color->set_custom_minimum_size(Size2(36, 0));
	toolbar->add_child(color);

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar);
	toolbar->hide();
}

Terrain3DEditorPlugin::~Terrain3DEditorPlugin() {
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar);
	memdelete(toolbar);
}
