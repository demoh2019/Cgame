/**************************************************************************/
/*  cgame_motion_matching_database.h                                      */
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
#include "core/variant/typed_array.h"

// Pose-search database for motion matching.
//
// Concepts after Clavet, "Motion Matching and The Road to Next-Gen Animation" (GDC 2016) and
// Holden's critically damped spring write-up. The implementation is original. Acceleration is a
// k-means bucket index with triangle-inequality pruning, so indexed search is exact.
//
// Feature layout (DIMS = 24):
//   0..1   root velocity (local space, x right / y forward)
//   2      root facing
//   3..11  3 trajectory samples at 0.2/0.4/0.6 s: pos.x, pos.y, facing (relative to root)
//   12..14 left foot pos, 15..17 right foot pos
//   18..20 left foot vel, 21..23 right foot vel
class CgameMotionMatchingDatabase : public Resource {
	GDCLASS(CgameMotionMatchingDatabase, Resource);

public:
	static constexpr int DIMS = 24;
	static constexpr int TRAJ_SAMPLES = 3;
	static constexpr float MIN_STD = 0.0001f;

	struct SearchResult {
		int clip = -1;
		int frame = -1;
		float cost = Math::INF;
		bool continuing = false;
	};

private:
	struct Clip {
		String name;
		Vector<float> raw; // frame_count * DIMS un-normalized features.
		float fps = 30.0f;
		bool loop = true;
		PackedStringArray tags;
		int frame_count = 0;
	};

	Vector<Clip> clips;

	// Weights (applied after mean/std normalization).
	float weight_velocity = 1.0f;
	float weight_facing = 0.5f;
	float weight_traj_pos = 1.0f;
	float weight_traj_facing = 0.5f;
	float weight_foot_pos = 0.6f;
	float weight_foot_vel = 0.4f;
	float continue_bias = 0.85f;
	float spring_halflife = 0.27f;

	// Built data.
	Vector<float> features; // Normalized and weight-scaled, DIMS floats per frame.
	Vector<float> mean;
	Vector<float> stdev;
	Vector<float> dim_scale;
	Vector<int> clip_of;
	Vector<int> frame_src;
	Vector<int> clip_start;
	Vector<int> clip_count;
	Vector<float> centroids;
	Vector<float> radius;
	Vector<Vector<int>> members;
	HashMap<String, int> clip_index;
	bool built = false;

	void _dim_weights(float *r_w) const;
	static float _dsq(const float *p_a, const float *p_b);
	float _partial_dsq(const float *p_q, int p_i, float p_limit) const;
	void _build_index();
	void _assign_all(Vector<int> &r_assign, int p_k) const;
	int _next_index(int p_clip, int p_frame) const;
	void _normalize_query(const Vector<float> &p_raw, float *r_q) const;
	SearchResult _search_impl(const Vector<float> &p_raw_query, int p_current_clip, int p_current_frame, const PackedStringArray &p_required_tags, bool p_indexed) const;
	Dictionary _result_to_dict(const SearchResult &p_result) const;
	void _set_weight_dict(const Dictionary &p_weights);
	Dictionary _get_weight_dict() const;

protected:
	static void _bind_methods();

public:
	// Authoring.
	void add_clip(const String &p_name, const Array &p_frames, float p_fps, bool p_loop, const PackedStringArray &p_tags = PackedStringArray());
	void add_clip_features(const String &p_name, const PackedFloat32Array &p_features, float p_fps, bool p_loop, const PackedStringArray &p_tags = PackedStringArray());
	void clear();
	void build();
	bool is_built() const { return built; }
	int retain_frames(const PackedByteArray &p_keep);
	int prune_redundant(float p_threshold);

	// Properties.
	void set_clips(const Array &p_clips);
	Array get_clips() const;
	void set_weights(const Dictionary &p_weights);
	Dictionary get_weights() const;
	void set_continue_bias(float p_bias) { continue_bias = p_bias; }
	float get_continue_bias() const { return continue_bias; }
	void set_spring_halflife(float p_halflife) { spring_halflife = p_halflife; }
	float get_spring_halflife() const { return spring_halflife; }

	// Introspection.
	int get_clip_count() const { return clips.size(); }
	int find_clip(const String &p_name) const;
	String get_clip_name(int p_clip) const;
	float get_clip_fps(int p_clip) const;
	bool is_clip_looping(int p_clip) const;
	int get_clip_frame_count(int p_clip) const;
	int get_frame_count() const { return clip_of.size(); }
	Dictionary get_stats() const;

	// Search.
	SearchResult search_native(const Vector<float> &p_raw_query, int p_current_clip, int p_current_frame, const PackedStringArray &p_required_tags, bool p_indexed = true) const;
	Dictionary search(const Dictionary &p_query, const String &p_current_clip = "", int p_current_frame = -1, const PackedStringArray &p_required_tags = PackedStringArray()) const;
	Dictionary brute_force_search(const Dictionary &p_query, const String &p_current_clip = "", int p_current_frame = -1, const PackedStringArray &p_required_tags = PackedStringArray()) const;
	Dictionary query_from(const Vector2 &p_velocity, float p_facing, const Vector2 &p_desired_velocity, float p_desired_facing, const Vector3 &p_left_foot, const Vector3 &p_right_foot, const Vector3 &p_left_vel, const Vector3 &p_right_vel) const;
	Vector<float> query_features_from(const Vector2 &p_velocity, float p_facing, const Vector2 &p_desired_velocity, float p_desired_facing, const Vector3 &p_left_foot, const Vector3 &p_right_foot, const Vector3 &p_left_vel, const Vector3 &p_right_vel) const;

	// Static helpers.
	static PackedFloat32Array frame_features(const Dictionary &p_frame);
	static Vector2 predict_velocity(const Vector2 &p_v0, const Vector2 &p_goal, float p_halflife, float p_t);
	static float predict_facing(float p_facing, float p_goal, float p_halflife, float p_t);
	static Array synthesize_locomotion_clips();
	static Ref<CgameMotionMatchingDatabase> build_default_database();
};
