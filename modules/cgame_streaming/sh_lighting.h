/**************************************************************************/
/*  sh_lighting.h                                                         */
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

#include "core/math/basis.h"
#include "core/math/color.h"
#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Static L2 spherical-harmonics lighting helpers (9 coefficients, one Color per coefficient;
// only r/g/b are used, alpha stays 0). evaluate_irradiance() returns irradiance divided by pi,
// so a uniform radiance L yields exactly L.
// Order: Y00, Y1-1(y), Y10(z), Y11(x), Y2-2(xy), Y2-1(yz), Y20, Y21(xz), Y22.
class SHLighting : public RefCounted {
	GDCLASS(SHLighting, RefCounted);

public:
	static constexpr int COEFFS = 9;
	static constexpr float C0 = 0.282094792f;
	static constexpr float C1 = 0.488602512f;
	static constexpr float C2 = 1.092548431f;
	static constexpr float C3 = 0.315391565f;
	static constexpr float C4 = 0.546274215f;
	static constexpr float GOLDEN_ANGLE = 2.399963229728653f;

	// Native, allocation free representation used by ProbeVolume.
	struct Coeffs {
		float c[COEFFS][3] = {};
	};

	static void basis_native(const Vector3 &p_dir, float r_basis[COEFFS]);
	static Vector3 fibonacci_dir_native(int p_i, int p_n);
	static void accumulate_native(Coeffs &r_sh, const Vector3 &p_dir, float p_r, float p_g, float p_b);
	static void add_native(Coeffs &r_a, const Coeffs &p_b);
	static Coeffs scale_native(const Coeffs &p_a, float p_f);
	static Coeffs lerp_native(const Coeffs &p_a, const Coeffs &p_b, float p_t);
	static Color radiance_native(const Coeffs &p_sh, const Vector3 &p_dir);
	static Color irradiance_native(const Coeffs &p_sh, const Vector3 &p_normal);
	static Coeffs from_sky_native(const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky, const Color &p_ground, int p_samples);
	static Coeffs from_array(const PackedColorArray &p_sh);
	static PackedColorArray to_array(const Coeffs &p_sh);

protected:
	static void _bind_methods();

public:
	static PackedColorArray create();
	static PackedFloat32Array basis(const Vector3 &p_dir);
	static Vector3 fibonacci_dir(int p_i, int p_n);
	static PackedColorArray accumulate(const PackedColorArray &p_sh, const Vector3 &p_dir, const Color &p_color);
	static PackedColorArray project_direction(const Vector3 &p_dir, const Color &p_color);
	static PackedColorArray add(const PackedColorArray &p_a, const PackedColorArray &p_b);
	static PackedColorArray scale(const PackedColorArray &p_a, float p_factor);
	static PackedColorArray lerp_sh(const PackedColorArray &p_a, const PackedColorArray &p_b, float p_t);
	static Color evaluate_radiance(const PackedColorArray &p_sh, const Vector3 &p_dir);
	static Color evaluate_irradiance(const PackedColorArray &p_sh, const Vector3 &p_normal);
	static PackedColorArray from_sky(const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky_color, const Color &p_ground_color, int p_samples);
	static PackedColorArray rotate(const PackedColorArray &p_sh, const Basis &p_rotation);
};
