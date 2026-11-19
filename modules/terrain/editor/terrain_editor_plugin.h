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

#include "../terrain_3d.h"
#include "editor/plugins/editor_plugin.h"

class HBoxContainer;
class OptionButton;
class SpinBox;
class ColorPickerButton;
class Camera3D;

class Terrain3DEditorPlugin : public EditorPlugin {
	GDCLASS(Terrain3DEditorPlugin, EditorPlugin);

	enum BrushMode {
		BRUSH_NAVIGATE,
		BRUSH_RAISE,
		BRUSH_LOWER,
		BRUSH_SMOOTH,
		BRUSH_COLOR,
	};

	HeightmapTerrain3D *terrain = nullptr;
	HBoxContainer *toolbar = nullptr;
	OptionButton *mode = nullptr;
	SpinBox *radius = nullptr;
	SpinBox *strength = nullptr;
	ColorPickerButton *color = nullptr;
	bool dragging = false;
	BrushMode drag_mode = BRUSH_NAVIGATE;
	PackedFloat32Array undo_heights;
	PackedColorArray undo_colors;

	bool _pick_terrain(Camera3D *p_camera, const Vector2 &p_screen_position, Vector2 &r_grid_position) const;
	void _apply_at(const Vector2 &p_grid_position);
	void _commit_stroke();

public:
	virtual String get_plugin_name() const override { return "Heightmap Terrain"; }
	virtual bool handles(Object *p_object) const override;
	virtual void edit(Object *p_object) override;
	virtual void make_visible(bool p_visible) override;
	virtual EditorPlugin::AfterGUIInput forward_3d_gui_input(Camera3D *p_camera, const Ref<InputEvent> &p_event) override;

	Terrain3DEditorPlugin();
	~Terrain3DEditorPlugin();
};
