/**************************************************************************/
/*  cgame_mocap_cleanup.h                                                 */
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
#include "core/variant/typed_array.h"

// Offline motion-capture cleanup: One Euro and zero-phase Butterworth filtering, rotation
// smoothing in log space, spike removal, gap filling, contact detection, foot-skate fixing, root
// motion extraction, key reduction and retiming. Mirrors scripts/client/mocap_cleanup.gd.
class CgameMocapCleanup : public RefCounted {
	GDCLASS(CgameMocapCleanup, RefCounted);

	static Vector<double> _biquad(const Vector<double> &p_x, double p_fps, double p_cutoff);
	static Vector<double> _filtfilt(const Vector<double> &p_x, double p_fps, double p_cutoff);
	static double _median(const Vector<double> &p_values);
	static Vector3 _hermite(const Vector3 &p_p0, const Vector3 &p_p1, const Vector3 &p_m0, const Vector3 &p_m1, double p_t, double p_span);
	static Vector3 _quat_log(const Quaternion &p_q);
	static Quaternion _quat_exp(const Vector3 &p_v);

protected:
	static void _bind_methods();

public:
	static PackedVector3Array one_euro_positions(const PackedVector3Array &p_track, float p_fps, float p_min_cutoff = 1.0f, float p_beta = 0.0f, float p_d_cutoff = 1.0f);
	static PackedVector3Array butterworth(const PackedVector3Array &p_track, float p_fps, float p_cutoff_hz);
	static TypedArray<Quaternion> make_continuous(const TypedArray<Quaternion> &p_rotations);
	static TypedArray<Quaternion> smooth_rotations(const TypedArray<Quaternion> &p_rotations, float p_fps, float p_cutoff);
	static PackedVector3Array remove_spikes(const PackedVector3Array &p_track, float p_threshold_sigma = 4.0f);
	static PackedVector3Array fill_gaps(const PackedVector3Array &p_track, const PackedByteArray &p_valid);
	static TypedArray<Quaternion> fill_gaps_rotations(const TypedArray<Quaternion> &p_rotations, const PackedByteArray &p_valid);
	static PackedByteArray detect_contacts(const PackedVector3Array &p_foot_track, float p_fps, float p_height_threshold, float p_speed_threshold);
	static PackedVector3Array fix_foot_skate(const PackedVector3Array &p_foot_track, const PackedByteArray &p_contacts, int p_blend_frames = 4);
	static Dictionary extract_root_motion(const PackedVector3Array &p_hips_track);
	static PackedInt32Array reduce_keys(const PackedVector3Array &p_track, float p_tolerance);
	static PackedVector3Array retime(const PackedVector3Array &p_track, float p_src_fps, float p_dst_fps);
	static TypedArray<Quaternion> retime_rotations(const TypedArray<Quaternion> &p_rotations, float p_src_fps, float p_dst_fps);
};
