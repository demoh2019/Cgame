/**************************************************************************/
/*  cgame_gpu_resource_report.h                                           */
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

#include "core/io/image.h"
#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class GeometryInstance3D;
class Material;
class Mesh;
class Node;
class Shader;
class Texture2D;
class Resource;

// GPU resource diagnostics: walks a node tree and estimates VRAM use of meshes, materials, textures
// and shaders, adds RenderingServer totals and per-viewport render-pass info, and keeps a
// ring-buffer timeline of totals. Byte figures are ESTIMATES (driver padding, tiling and
// compression-on-upload are not visible from here).
class CgameGPUResourceReport : public RefCounted {
	GDCLASS(CgameGPUResourceReport, RefCounted);

public:
	static constexpr int TIMELINE_CAPACITY = 256;

private:
	bool probe_compressed = false;
	int timeline_capacity = TIMELINE_CAPACITY;

	Dictionary meshes; // instance id -> entry
	Dictionary materials;
	Dictionary textures;
	Dictionary shaders;
	Dictionary node_counts;
	int64_t instance_bytes = 0;
	TypedArray<Dictionary> passes;
	TypedArray<Dictionary> timeline_data;
	int timeline_head = 0;
	int timeline_seq = 0;

	void _walk(Node *p_node);
	void _count_node(const String &p_kind);
	void _add_geometry_materials(GeometryInstance3D *p_gi, const Ref<Mesh> &p_mesh);
	void _add_mesh(const Ref<Mesh> &p_mesh);
	void _add_material(const Ref<Material> &p_material);
	String _add_shader(const Ref<Shader> &p_shader);
	void _add_texture(const Ref<Texture2D> &p_texture, const String &p_source);
	void _collect_passes(Node *p_root);
	static String _res_name(const Ref<Resource> &p_resource);
	static int64_t _sum_bytes(const Dictionary &p_entries);
	Dictionary _source(const String &p_kind) const;
	String _detail(const String &p_kind, const Dictionary &p_entry) const;

protected:
	static void _bind_methods();

public:
	// Pure helpers (no engine singletons): used by tests.
	// Bits per pixel for an Image::Format, or -1 when unknown.
	static int format_bpp(int p_format);
	static bool is_block_compressed(int p_format);
	// Estimated bytes for a 2D texture, optionally including the full mip chain.
	static int64_t texture_bytes(int p_width, int p_height, int p_format, bool p_mipmaps, int p_layers = 1);
	static String format_bytes(int64_t p_bytes);

	static Dictionary rendering_totals();

	Dictionary collect(Node *p_root);
	Dictionary snapshot() const;
	// Top n entries of kind (meshes | materials | textures | shaders) by estimated bytes, descending;
	// ties break by name so the order is deterministic.
	TypedArray<Dictionary> top(int p_n, const String &p_kind) const;

	// Records one sample: RenderingServer memory totals plus the estimate from the last collect().
	Dictionary timeline_push();
	// Samples oldest first.
	TypedArray<Dictionary> timeline() const;
	int64_t timeline_peak(const String &p_key) const;

	String to_markdown(int p_top_n = 5) const;

	void set_probe_compressed(bool p_enabled) { probe_compressed = p_enabled; }
	bool get_probe_compressed() const { return probe_compressed; }
	void set_timeline_capacity(int p_capacity) { timeline_capacity = MAX(p_capacity, 1); }
	int get_timeline_capacity() const { return timeline_capacity; }
};
