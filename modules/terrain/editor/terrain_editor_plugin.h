/**************************************************************************/
/*  terrain_editor_plugin.h                                               */
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

#include "../terrain_mesh.h"

#include "editor/plugins/editor_plugin.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/gui/box_container.h"

class Button;
class Camera3D;
class OptionButton;
class SpinBox;

class TerrainEditorPlugin : public EditorPlugin {
	GDCLASS(TerrainEditorPlugin, EditorPlugin);

	MeshInstance3D *edited_instance = nullptr;
	Ref<TerrainMesh> terrain;
	HBoxContainer *toolbar = nullptr;
	Button *paint_enabled = nullptr;
	OptionButton *brush_mode = nullptr;
	SpinBox *brush_radius = nullptr;
	SpinBox *brush_strength = nullptr;

	Ref<TerrainMesh> stroke_terrain;
	PackedFloat32Array stroke_before;
	bool stroke_active = false;
	bool plugin_visible = false;
	bool stroke_has_position = false;
	Vector2 last_stroke_position;

	bool _pick_position(Camera3D *p_camera, const Vector2 &p_screen_position, Vector2 &r_grid_position) const;
	bool _apply_brush(Camera3D *p_camera, const Vector2 &p_screen_position);
	void _finish_stroke();
	void _paint_toggled(bool p_enabled);
#ifndef PHYSICS_3D_DISABLED
	void _create_collision();
#endif

protected:
	void _notification(int p_what);

public:
	String get_plugin_name() const override { return "Terrain"; }
	bool handles(Object *p_object) const override;
	void edit(Object *p_object) override;
	void make_visible(bool p_visible) override;
	void clear() override;
	AfterGUIInput forward_3d_gui_input(Camera3D *p_camera, const Ref<InputEvent> &p_event) override;
};
