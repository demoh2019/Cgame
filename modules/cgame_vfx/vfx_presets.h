/**************************************************************************/
/*  vfx_presets.h                                                         */
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

#include "vfx_graph_instance_3d.h"

#include "core/object/ref_counted.h"

// Gameplay effects authored as VFX graph dictionaries. Each preset is pure data: spawn/update
// modules plus event routing between emitters.
class VFXPresets : public RefCounted {
	GDCLASS(VFXPresets, RefCounted);

protected:
	static void _bind_methods();

public:
	// Particle counts per graphics level; level 0 (Performance) yields an empty effect.
	static int get_spark_count(int p_level);

	// Lightning ground strike: white-hot sparks that bounce off the ground and spawn short-lived
	// embers on impact (collision event routing).
	static Dictionary lightning_sparks(int p_level);

	// Spawns a self-freeing effect node at a world position; null when disabled or invalid.
	// p_asset is a graph Dictionary or a VFXGraphAsset.
	static VFXGraphInstance3D *spawn(Node3D *p_parent, const Variant &p_asset, const Vector3 &p_at, int64_t p_seed);
};
