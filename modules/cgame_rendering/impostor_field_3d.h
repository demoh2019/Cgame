/**************************************************************************/
/*  impostor_field_3d.h                                                   */
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
#include "scene/3d/multimesh_instance_3d.h"
#include "scene/resources/mesh.h"

// Billboard/impostor LOD ring: past the real mesh's draw distance, the same placements continue as
// one MultiMesh of baked impostor quads, so distant hills keep their bushes and trees instead of
// popping to bare ground. One draw call per field.
class ImpostorField3D : public MultiMeshInstance3D {
	GDCLASS(ImpostorField3D, MultiMeshInstance3D);

	static float range_factor; // Impostor end distance relative to the mesh range.

	Ref<Mesh> source_mesh;
	Vector<Transform3D> placements;
	float mesh_range = 50.0f;
	float fade_margin = 8.0f;
	bool baked = false;
	bool bake_requested = false;

	void _on_baked(const Ref<Texture2D> &p_atlas);
	void _request_bake();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	// Pure helpers: used by tests.
	static float range_factor_for_level(int p_level);
	static float end_distance_for(float p_mesh_range, float p_range_factor);

	static void configure(int p_level);
	static float get_range_factor() { return range_factor; }
	static float end_distance(float p_mesh_range);

	void set_source_mesh(const Ref<Mesh> &p_mesh);
	Ref<Mesh> get_source_mesh() const { return source_mesh; }
	void set_placements(const TypedArray<Transform3D> &p_placements);
	TypedArray<Transform3D> get_placements() const;
	void set_mesh_range(float p_range);
	float get_mesh_range() const { return mesh_range; }
	void set_fade_margin(float p_margin);
	float get_fade_margin() const { return fade_margin; }

	// Builds the MultiMesh and visibility ranges from the current properties. Returns false (and
	// leaves the node empty) when nothing would be drawn: no mesh/placements or range factor <= 1.
	bool rebuild();
	bool is_baked() const { return baked; }

	// Convenience factory mirroring the GDScript API: creates, configures and parents a field.
	static ImpostorField3D *add(Node3D *p_parent, const Ref<Mesh> &p_mesh, const TypedArray<Transform3D> &p_transforms, float p_mesh_range, float p_fade_margin = 8.0f);
};
