/**************************************************************************/
/*  vfx_graph_asset.h                                                     */
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

#include "core/io/resource.h"

// A data-driven VFX graph: a Dictionary of emitters, each with spawn/update module lists,
// attributes and event routing. The format is identical to the GDScript vfx_graph.gd asset:
//
//   {"emitters": {name: {"max_particles": int, "duration": float,
//                        "attributes": {custom_float_name: default},
//                        "spawn": [module, ...], "update": [module, ...],
//                        "events": {"death": spec, "collision": spec},
//                        "blend": "alpha" | "add", "texture": Texture2D, "bounds": float}}}
//
// A bare emitter dictionary (without "emitters") is accepted and wrapped as emitter "main".
class VFXGraphAsset : public Resource {
	GDCLASS(VFXGraphAsset, Resource);

	Dictionary graph;

protected:
	static void _bind_methods();

public:
	void set_graph(const Dictionary &p_graph);
	Dictionary get_graph() const { return graph; }

	// Returns the normalized system dictionary ({"emitters": {...}}).
	Dictionary get_system() const;
	PackedStringArray get_emitter_names() const;
	bool has_emitter(const String &p_name) const;
	Dictionary get_emitter(const String &p_name) const;
	int get_emitter_count() const;
	// Sum of "max_particles" over every emitter (the cost reported to the budget server).
	int get_total_max_particles() const;
	// True when at least one emitter can hold particles.
	bool has_particles() const;

	// Returns human-readable errors; an empty array means the graph is valid.
	PackedStringArray validate() const;
	bool is_valid() const { return validate().is_empty(); }
	static PackedStringArray validate_graph(const Dictionary &p_graph);

	static Ref<VFXGraphAsset> create_from_dictionary(const Dictionary &p_graph);
	// Names of every supported spawn and update module.
	static PackedStringArray get_module_names();
};
