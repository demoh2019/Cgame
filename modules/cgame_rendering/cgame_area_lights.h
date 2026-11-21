/**************************************************************************/
/*  cgame_area_lights.h                                                   */
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

#include "core/object/ref_counted.h"

class Light3D;
class SceneTree;

// Area-light softness for local lights (UE5 Source Radius, HDRP area/PCSS). Torches, lanterns and
// campfires get a physical emitter size so their shadows soften with distance; the PCSS filter
// quality follows the tier.
class CgameAreaLights : public RefCounted {
	GDCLASS(CgameAreaLights, RefCounted);

	static int level;

protected:
	static void _bind_methods();

public:
	static const StringName &get_group();
	static const StringName &get_meta_radius();

	// Returns a RenderingServer.ShadowQuality value.
	static int filter_quality(int p_level);
	// Emitter radius actually used: PCSS is skipped below High (it costs blocker search taps).
	static float size_for(int p_level, float p_emitter_radius);

	static void register_light(Light3D *p_light, float p_emitter_radius);
	static void configure(int p_level, SceneTree *p_tree);
	static int get_level() { return level; }

private:
	static void _apply_one(Light3D *p_light);
};
