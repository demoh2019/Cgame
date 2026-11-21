/**************************************************************************/
/*  cgame_terrain_edit_layers.h                                           */
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

#include "core/math/rect2i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_set.h"
#include "core/variant/typed_array.h"
#include "scene/resources/curve.h"
#include "scene/resources/mesh.h"

class CgameTerrainEditLayers : public RefCounted {
	GDCLASS(CgameTerrainEditLayers, RefCounted);

public:
	enum Blend {
		BLEND_ADD,
		BLEND_MAX,
		BLEND_REPLACE,
	};

	enum Brush {
		BRUSH_RAISE,
		BRUSH_LOWER,
		BRUSH_SMOOTH,
		BRUSH_FLATTEN,
		BRUSH_NOISE,
		BRUSH_ERODE,
	};

	enum Falloff {
		FALLOFF_LINEAR,
		FALLOFF_SMOOTH,
		FALLOFF_SPHERE,
		FALLOFF_CONSTANT,
	};

	enum UndoKind {
		UNDO_HEIGHT,
		UNDO_SPLAT,
	};

private:
	struct EditLayer {
		int id = 0;
		String name;
		bool visible = true;
		double opacity = 1.0;
		int blend = BLEND_ADD;
		PackedFloat32Array delta;
		PackedFloat32Array alpha;
		// Texel bounds ever touched (for cheap dirty marking on property changes).
		Rect2i bounds;
		bool has_bounds = false;
	};

	struct UndoEntry {
		int kind = UNDO_HEIGHT;
		int layer_id = -1;
		Rect2i rect;
		PackedFloat32Array data;
		PackedFloat32Array data2;

		int64_t bytes() const { return ((int64_t)data.size() + data2.size()) * 4; }
	};

	struct Vector2iLess {
		bool operator()(const Vector2i &p_a, const Vector2i &p_b) const {
			return p_a.y < p_b.y || (p_a.y == p_b.y && p_a.x < p_b.x);
		}
	};

	int width = 0;
	int height = 0;
	int chunk_size = 16;
	int chunks_x = 0;
	int chunks_z = 0;
	// Upper bound on undo+redo history memory. Oldest entries are dropped first.
	int64_t max_undo_bytes = 8 * 1024 * 1024;

	PackedFloat32Array base;
	Vector<EditLayer> layers;
	int next_layer_id = 1;

	int splat_count_value = 0;
	PackedFloat32Array splat;

	Vector<UndoEntry> undo_stack;
	Vector<UndoEntry> redo_stack;

	HashSet<Vector2i> dirty;
	HashSet<Vector2i> collision_pending;
	Vector<Vector2i> collision_queue;

	int _layer_index(int p_id) const;
	void _mark_layer_dirty(const EditLayer &p_layer);
	void _mark_all_layers_dirty();
	void _mark_rect_dirty(const Rect2i &p_rect);
	static void _grow_bounds(EditLayer &r_layer, const Rect2i &p_rect);
	Rect2i _map_rect() const { return Rect2i(0, 0, width, height); }

	double _blend_texel(double p_h, double p_b, const EditLayer &p_layer, int p_i) const;
	static double _falloff(double p_t, int p_kind, const Ref<Curve> &p_curve);
	Rect2i _brush_rect(const Vector2 &p_center, double p_radius) const;
	static double _hash_noise(int p_x, int p_y, int64_t p_seed);

	PackedFloat32Array _read_rect(const PackedFloat32Array &p_arr, const Rect2i &p_rect, int p_stride) const;
	void _write_rect(PackedFloat32Array &r_arr, const Rect2i &p_rect, int p_stride, const PackedFloat32Array &p_data) const;
	UndoEntry _snapshot_height(const EditLayer &p_layer, const Rect2i &p_rect) const;
	void _push_undo(const UndoEntry &p_entry);
	void _trim_history();
	bool _swap_entry(UndoEntry &r_entry);
	bool _valid_chunk(const Vector2i &p_chunk) const;

protected:
	static void _bind_methods();

public:
	void setup(int p_width, int p_height, int p_chunk_size, const PackedFloat32Array &p_base_heights);
	int get_width() const { return width; }
	int get_height() const { return height; }
	int get_chunk_size() const { return chunk_size; }
	int get_chunks_x() const { return chunks_x; }
	int get_chunks_z() const { return chunks_z; }
	int chunk_count() const { return chunks_x * chunks_z; }
	void set_max_undo_bytes(int64_t p_bytes);
	int64_t get_max_undo_bytes() const { return max_undo_bytes; }

	// Layers.
	int add_layer(const String &p_name, Blend p_blend = BLEND_ADD, double p_opacity = 1.0);
	int add_layer_from_region(const String &p_name, const Rect2i &p_rect, const PackedFloat32Array &p_delta, const PackedFloat32Array &p_alpha, Blend p_blend = BLEND_ADD, double p_opacity = 1.0);
	bool remove_layer(int p_id);
	bool move_layer(int p_id, int p_to_index);
	void set_layer_visible(int p_id, bool p_visible);
	bool is_layer_visible(int p_id) const;
	void set_layer_opacity(int p_id, double p_opacity);
	double get_layer_opacity(int p_id) const;
	void set_layer_blend(int p_id, Blend p_blend);
	Blend get_layer_blend(int p_id) const;
	void set_layer_name(int p_id, const String &p_name);
	String get_layer_name(int p_id) const;
	int layer_count() const { return layers.size(); }
	PackedInt32Array layer_ids() const;
	bool has_layer(int p_id) const { return _layer_index(p_id) >= 0; }
	Rect2i get_layer_bounds(int p_id) const;

	// Per-texel / per-region delta access (no need to touch internal storage).
	double layer_delta_at(int p_id, int p_x, int p_y) const;
	double layer_alpha_at(int p_id, int p_x, int p_y) const;
	bool set_layer_texel(int p_id, int p_x, int p_y, double p_delta, double p_alpha = 1.0);
	PackedFloat32Array get_layer_region_deltas(int p_id, const Rect2i &p_rect) const;
	PackedFloat32Array get_layer_region_alphas(int p_id, const Rect2i &p_rect) const;
	bool write_layer_region(int p_id, const Rect2i &p_rect, const PackedFloat32Array &p_delta, const PackedFloat32Array &p_alpha);
	void fill_layer_rect(int p_id, const Rect2i &p_rect, double p_delta, double p_alpha = 1.0);

	// Compositing.
	double composite_height(int p_x, int p_y) const;
	PackedFloat32Array composite_region(const Rect2i &p_rect) const;

	// Brushes.
	Rect2i apply_brush(int p_layer_id, Brush p_brush, const Vector2 &p_center, double p_radius, double p_strength, Falloff p_falloff = FALLOFF_SMOOTH, double p_target_height = 0.0, int64_t p_seed_value = 0, const Ref<Curve> &p_curve = Ref<Curve>());

	// Splat (material weights).
	void setup_splat(int p_count);
	int splat_count() const { return splat_count_value; }
	PackedFloat32Array splat_weights(int p_x, int p_y) const;
	Rect2i paint_splat(int p_material, const Vector2 &p_center, double p_radius, double p_strength, Falloff p_falloff = FALLOFF_SMOOTH, const Ref<Curve> &p_curve = Ref<Curve>());

	// Undo / redo.
	int64_t undo_bytes() const;
	int undo_depth() const { return undo_stack.size(); }
	bool can_undo() const { return !undo_stack.is_empty(); }
	bool can_redo() const { return !redo_stack.is_empty(); }
	bool undo();
	bool redo();

	// Dirty tracking / collision queue.
	TypedArray<Vector2i> take_dirty_chunks();
	TypedArray<Vector2i> collision_jobs(int p_max_per_frame);
	int pending_collision_count() const { return collision_queue.size(); }

	// Chunk export / mesh.
	PackedFloat32Array export_chunk_heights(const Vector2i &p_chunk) const;
	Ref<ArrayMesh> build_chunk_mesh(const Vector2i &p_chunk, double p_cell_size) const;
};

VARIANT_ENUM_CAST(CgameTerrainEditLayers::Blend);
VARIANT_ENUM_CAST(CgameTerrainEditLayers::Brush);
VARIANT_ENUM_CAST(CgameTerrainEditLayers::Falloff);
VARIANT_ENUM_CAST(CgameTerrainEditLayers::UndoKind);
