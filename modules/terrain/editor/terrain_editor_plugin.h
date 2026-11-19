/**************************************************************************/
/*  terrain_editor_plugin.h                                               */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

	bool _pick_position(Camera3D *p_camera, const Vector2 &p_screen_position, Vector2 &r_grid_position) const;
	bool _apply_brush(Camera3D *p_camera, const Vector2 &p_screen_position);
	void _finish_stroke();

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
