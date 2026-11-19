/**************************************************************************/
/*  terrain_editor_plugin.cpp                                             */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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
#include "core/math/triangle_mesh.h"
#include "editor/editor_undo_redo_manager.h"
#include "scene/3d/camera_3d.h"
#include "scene/gui/box_container.h"
#include "scene/gui/color_picker.h"
#include "scene/gui/label.h"
#include "scene/gui/option_button.h"
#include "scene/gui/spin_box.h"
#include "scene/main/viewport.h"

void HeightmapTerrainEditorPlugin::_notification(int p_what) {
    if (p_what == NOTIFICATION_ENTER_TREE) {
        toolbar = memnew(HBoxContainer);

        brush_mode = memnew(OptionButton);
        brush_mode->add_item("Raise", 0);
        brush_mode->add_item("Lower", 1);
        brush_mode->add_item("Paint Color", 2);
        toolbar->add_child(brush_mode);

        Label *radius_label = memnew(Label);
        radius_label->set_text("Radius");
        toolbar->add_child(radius_label);

        radius = memnew(SpinBox);
        radius->set_min(0.1);
        radius->set_max(128);
        radius->set_step(0.1);
        radius->set_value(3);
        toolbar->add_child(radius);

        Label *strength_label = memnew(Label);
        strength_label->set_text("Strength");
        toolbar->add_child(strength_label);

        strength = memnew(SpinBox);
        strength->set_min(0.01);
        strength->set_max(10);
        strength->set_step(0.05);
        strength->set_value(1);
        toolbar->add_child(strength);

        paint_color = memnew(ColorPickerButton);
        paint_color->set_pick_color(Color(0.24, 0.55, 0.17));
        toolbar->add_child(paint_color);

        add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar);
        toolbar->hide();
    } else if (p_what == NOTIFICATION_EXIT_TREE) {
        if (toolbar) {
            remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar);
            memdelete(toolbar);
            toolbar = nullptr;
        }
        brush_mode = nullptr;
        radius = nullptr;
        strength = nullptr;
        paint_color = nullptr;
        terrain = nullptr;
    }
}

bool HeightmapTerrainEditorPlugin::handles(Object *p_object) const {
    return Object::cast_to<HeightmapTerrain3D>(p_object) != nullptr;
}

void HeightmapTerrainEditorPlugin::edit(Object *p_object) {
    terrain = Object::cast_to<HeightmapTerrain3D>(p_object);
}

void HeightmapTerrainEditorPlugin::make_visible(bool p_visible) {
    if (toolbar) {
        toolbar->set_visible(p_visible && terrain);
    }
    if (!p_visible) {
        terrain = nullptr;
    }
}

EditorPlugin::AfterGUIInput HeightmapTerrainEditorPlugin::forward_3d_gui_input(Camera3D *p_camera, const Ref<InputEvent> &p_event) {
    if (!terrain || !toolbar || !toolbar->is_visible() || !p_camera) {
        return AFTER_GUI_INPUT_PASS;
    }
    Ref<InputEventMouseButton> mouse = p_event;
    if (mouse.is_null() || mouse->get_button_index() != MouseButton::LEFT || !mouse->is_pressed()) {
        return AFTER_GUI_INPUT_PASS;
    }
    // Preserve viewport orbit/pan modifiers, and allow normal object selection.
    if (mouse->is_alt_pressed() || mouse->is_shift_pressed() || mouse->is_command_or_control_pressed()) {
        return AFTER_GUI_INPUT_PASS;
    }
    Ref<TerrainHeightmap> data = terrain->get_heightmap();
    if (data.is_null()) {
        return AFTER_GUI_INPUT_PASS;
    }

    Ref<TriangleMesh> triangle_mesh = terrain->generate_triangle_mesh();
    if (triangle_mesh.is_null()) {
        return AFTER_GUI_INPUT_PASS;
    }

    const Transform3D inverse = terrain->get_global_transform().affine_inverse();
    const Vector3 ray_origin = inverse.xform(p_camera->project_ray_origin(mouse->get_position()));
    const Vector3 ray_direction = inverse.basis.xform(p_camera->project_ray_normal(mouse->get_position())).normalized();
    Vector3 hit;
    Vector3 normal;
    if (!triangle_mesh->intersect_ray(ray_origin, ray_direction, hit, normal)) {
        return AFTER_GUI_INPUT_PASS;
    }

    const real_t size = terrain->get_cell_size();
    const Vector2 grid_center(hit.x / size, hit.z / size);
    const real_t grid_radius = radius->get_value() / size;
    const int mode = brush_mode->get_selected_id();
    const real_t power = strength->get_value();

    EditorUndoRedoManager *undo = get_undo_redo();
    if (!undo) {
        return AFTER_GUI_INPUT_PASS;
    }

    if (mode == 2) {
        const PackedColorArray before = data->get_colors();
        data->apply_color_brush(grid_center, grid_radius, paint_color->get_pick_color(), CLAMP(power, 0.0, 1.0));
        const PackedColorArray after = data->get_colors();
        if (before == after) {
            return AFTER_GUI_INPUT_PASS;
        }
        data->set_colors(before);
        undo->create_action("Paint Terrain Color", UndoRedo::MERGE_DISABLE, terrain);
        undo->add_do_method(data.ptr(), SNAME("set_colors"), after);
        undo->add_undo_method(data.ptr(), SNAME("set_colors"), before);
        undo->commit_action();
    } else {
        const PackedFloat32Array before = data->get_heights();
        data->apply_height_brush(grid_center, grid_radius, mode == 1 ? -power : power);
        const PackedFloat32Array after = data->get_heights();
        if (before == after) {
            return AFTER_GUI_INPUT_PASS;
        }
        data->set_heights(before);
        undo->create_action("Sculpt Terrain", UndoRedo::MERGE_DISABLE, terrain);
        undo->add_do_method(data.ptr(), SNAME("set_heights"), after);
        undo->add_undo_method(data.ptr(), SNAME("set_heights"), before);
        undo->commit_action();
    }
    return AFTER_GUI_INPUT_STOP;
}
