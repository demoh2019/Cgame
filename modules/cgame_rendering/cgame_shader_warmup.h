/**************************************************************************/
/*  cgame_shader_warmup.h                                                 */
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

#include "core/variant/typed_array.h"
#include "scene/3d/node_3d.h"
#include "scene/resources/shader.h"

class Camera3D;

// Shader / pipeline precompilation (UE5 PSO precaching, Unity ShaderVariantCollection.WarmUp):
// during loading every spatial shader of the game is drawn once on a sub-pixel quad in front of the
// camera, so the driver compiles its pipelines before combat instead of mid-fight.
class CgameShaderWarmup : public Node3D {
	GDCLASS(CgameShaderWarmup, Node3D);

public:
	static constexpr int FRAMES_VISIBLE = 3;
	static constexpr int GRID_COLUMNS = 8;

private:
	int frames_left = FRAMES_VISIBLE;

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	// Pure helper: position of the i-th probe quad relative to the camera.
	static Vector3 slot_position(int p_index, float p_camera_near);

	static PackedStringArray default_shader_dirs();
	static PackedStringArray shader_paths(const PackedStringArray &p_dirs = PackedStringArray());
	static TypedArray<Shader> spatial_shaders(const PackedStringArray &p_dirs = PackedStringArray());

	// Attaches a warm-up rig to the camera; it frees itself after a few frames.
	static CgameShaderWarmup *start(Camera3D *p_camera, const PackedStringArray &p_dirs = PackedStringArray());
	// Same as start() for an explicit shader list (non-spatial shaders are skipped).
	static CgameShaderWarmup *start_with_shaders(Camera3D *p_camera, const TypedArray<Shader> &p_shaders);

	// Pipeline compile counters from RenderingServer rendering info, as
	// {canvas, mesh, surface, draw, specialization, total}.
	static Dictionary get_pipeline_compile_counters();
	static int get_pipeline_compile_total();

	int get_frames_left() const { return frames_left; }
};
