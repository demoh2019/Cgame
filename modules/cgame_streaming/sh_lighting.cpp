/**************************************************************************/
/*  sh_lighting.cpp                                                       */
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

#include "sh_lighting.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void SHLighting::basis_native(const Vector3 &p_d, float r_b[COEFFS]) {
	r_b[0] = C0;
	r_b[1] = C1 * p_d.y;
	r_b[2] = C1 * p_d.z;
	r_b[3] = C1 * p_d.x;
	r_b[4] = C2 * p_d.x * p_d.y;
	r_b[5] = C2 * p_d.y * p_d.z;
	r_b[6] = C3 * (3.0f * p_d.z * p_d.z - 1.0f);
	r_b[7] = C2 * p_d.x * p_d.z;
	r_b[8] = C4 * (p_d.x * p_d.x - p_d.y * p_d.y);
}

Vector3 SHLighting::fibonacci_dir_native(int p_i, int p_n) {
	float y = 1.0f - 2.0f * ((float)p_i + 0.5f) / (float)p_n;
	float r = Math::sqrt(MAX(0.0f, 1.0f - y * y));
	float phi = (float)p_i * GOLDEN_ANGLE;
	return Vector3(Math::cos(phi) * r, y, Math::sin(phi) * r);
}

void SHLighting::accumulate_native(Coeffs &r_sh, const Vector3 &p_dir, float p_r, float p_g, float p_b) {
	float b[COEFFS];
	basis_native(p_dir, b);
	for (int i = 0; i < COEFFS; i++) {
		r_sh.c[i][0] += p_r * b[i];
		r_sh.c[i][1] += p_g * b[i];
		r_sh.c[i][2] += p_b * b[i];
	}
}

void SHLighting::add_native(Coeffs &r_a, const Coeffs &p_b) {
	for (int i = 0; i < COEFFS; i++) {
		for (int k = 0; k < 3; k++) {
			r_a.c[i][k] += p_b.c[i][k];
		}
	}
}

SHLighting::Coeffs SHLighting::scale_native(const Coeffs &p_a, float p_f) {
	Coeffs out;
	for (int i = 0; i < COEFFS; i++) {
		for (int k = 0; k < 3; k++) {
			out.c[i][k] = p_a.c[i][k] * p_f;
		}
	}
	return out;
}

SHLighting::Coeffs SHLighting::lerp_native(const Coeffs &p_a, const Coeffs &p_b, float p_t) {
	Coeffs out;
	for (int i = 0; i < COEFFS; i++) {
		for (int k = 0; k < 3; k++) {
			out.c[i][k] = Math::lerp(p_a.c[i][k], p_b.c[i][k], p_t);
		}
	}
	return out;
}

Color SHLighting::radiance_native(const Coeffs &p_sh, const Vector3 &p_dir) {
	float b[COEFFS];
	basis_native(p_dir.normalized(), b);
	float rgb[3] = { 0, 0, 0 };
	for (int i = 0; i < COEFFS; i++) {
		for (int k = 0; k < 3; k++) {
			rgb[k] += p_sh.c[i][k] * b[i];
		}
	}
	return Color(rgb[0], rgb[1], rgb[2], 1.0f);
}

Color SHLighting::irradiance_native(const Coeffs &p_sh, const Vector3 &p_normal) {
	float b[COEFFS];
	basis_native(p_normal.normalized(), b);
	float rgb[3] = { 0, 0, 0 };
	for (int i = 0; i < COEFFS; i++) {
		// Cosine convolution A_l / pi for bands 0, 1, 2.
		float f = i == 0 ? 1.0f : (i < 4 ? 2.0f / 3.0f : 0.25f);
		for (int k = 0; k < 3; k++) {
			rgb[k] += p_sh.c[i][k] * b[i] * f;
		}
	}
	return Color(MAX(rgb[0], 0.0f), MAX(rgb[1], 0.0f), MAX(rgb[2], 0.0f), 1.0f);
}

SHLighting::Coeffs SHLighting::from_sky_native(const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky, const Color &p_ground, int p_samples) {
	Coeffs sh;
	int n = MAX(p_samples, 16);
	float w = 4.0f * (float)Math::PI / (float)n;
	for (int i = 0; i < n; i++) {
		Vector3 d = fibonacci_dir_native(i, n);
		Color rad = p_ground.lerp(p_sky, CLAMP(d.y * 0.5f + 0.5f, 0.0f, 1.0f));
		accumulate_native(sh, d, rad.r * w, rad.g * w, rad.b * w);
	}
	if (p_sun_dir.length_squared() > 0.0f) {
		float pi = (float)Math::PI;
		accumulate_native(sh, p_sun_dir.normalized(), p_sun_color.r * pi, p_sun_color.g * pi, p_sun_color.b * pi);
	}
	return sh;
}

SHLighting::Coeffs SHLighting::from_array(const PackedColorArray &p_sh) {
	Coeffs out;
	for (int i = 0; i < COEFFS && i < p_sh.size(); i++) {
		out.c[i][0] = p_sh[i].r;
		out.c[i][1] = p_sh[i].g;
		out.c[i][2] = p_sh[i].b;
	}
	return out;
}

PackedColorArray SHLighting::to_array(const Coeffs &p_sh) {
	PackedColorArray out;
	out.resize(COEFFS);
	for (int i = 0; i < COEFFS; i++) {
		out.write[i] = Color(p_sh.c[i][0], p_sh.c[i][1], p_sh.c[i][2], 0.0f);
	}
	return out;
}

PackedColorArray SHLighting::create() {
	return to_array(Coeffs());
}

PackedFloat32Array SHLighting::basis(const Vector3 &p_dir) {
	float b[COEFFS];
	basis_native(p_dir, b);
	PackedFloat32Array out;
	out.resize(COEFFS);
	for (int i = 0; i < COEFFS; i++) {
		out.write[i] = b[i];
	}
	return out;
}

Vector3 SHLighting::fibonacci_dir(int p_i, int p_n) {
	ERR_FAIL_COND_V(p_n <= 0, Vector3());
	return fibonacci_dir_native(p_i, p_n);
}

PackedColorArray SHLighting::accumulate(const PackedColorArray &p_sh, const Vector3 &p_dir, const Color &p_color) {
	Coeffs sh = from_array(p_sh);
	accumulate_native(sh, p_dir.normalized(), p_color.r, p_color.g, p_color.b);
	return to_array(sh);
}

PackedColorArray SHLighting::project_direction(const Vector3 &p_dir, const Color &p_color) {
	return accumulate(create(), p_dir, p_color);
}

PackedColorArray SHLighting::add(const PackedColorArray &p_a, const PackedColorArray &p_b) {
	Coeffs a = from_array(p_a);
	add_native(a, from_array(p_b));
	return to_array(a);
}

PackedColorArray SHLighting::scale(const PackedColorArray &p_a, float p_factor) {
	return to_array(scale_native(from_array(p_a), p_factor));
}

PackedColorArray SHLighting::lerp_sh(const PackedColorArray &p_a, const PackedColorArray &p_b, float p_t) {
	return to_array(lerp_native(from_array(p_a), from_array(p_b), p_t));
}

Color SHLighting::evaluate_radiance(const PackedColorArray &p_sh, const Vector3 &p_dir) {
	return radiance_native(from_array(p_sh), p_dir);
}

Color SHLighting::evaluate_irradiance(const PackedColorArray &p_sh, const Vector3 &p_normal) {
	return irradiance_native(from_array(p_sh), p_normal);
}

PackedColorArray SHLighting::from_sky(const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky_color, const Color &p_ground_color, int p_samples) {
	return to_array(from_sky_native(p_sun_dir, p_sun_color, p_sky_color, p_ground_color, p_samples));
}

PackedColorArray SHLighting::rotate(const PackedColorArray &p_sh, const Basis &p_rotation) {
	Coeffs src = from_array(p_sh);
	Coeffs out;
	Basis inv = p_rotation.inverse();
	const int n = 256;
	float w = 4.0f * (float)Math::PI / (float)n;
	for (int i = 0; i < n; i++) {
		Vector3 d = fibonacci_dir_native(i, n);
		Color rad = radiance_native(src, inv.xform(d));
		accumulate_native(out, d, rad.r * w, rad.g * w, rad.b * w);
	}
	return to_array(out);
}

void SHLighting::_bind_methods() {
	ClassDB::bind_static_method("SHLighting", D_METHOD("create"), &SHLighting::create);
	ClassDB::bind_static_method("SHLighting", D_METHOD("basis", "dir"), &SHLighting::basis);
	ClassDB::bind_static_method("SHLighting", D_METHOD("fibonacci_dir", "i", "n"), &SHLighting::fibonacci_dir);
	ClassDB::bind_static_method("SHLighting", D_METHOD("accumulate", "sh", "dir", "color"), &SHLighting::accumulate);
	ClassDB::bind_static_method("SHLighting", D_METHOD("project_direction", "dir", "color"), &SHLighting::project_direction);
	ClassDB::bind_static_method("SHLighting", D_METHOD("add", "a", "b"), &SHLighting::add);
	ClassDB::bind_static_method("SHLighting", D_METHOD("scale", "a", "factor"), &SHLighting::scale);
	ClassDB::bind_static_method("SHLighting", D_METHOD("lerp_sh", "a", "b", "t"), &SHLighting::lerp_sh);
	ClassDB::bind_static_method("SHLighting", D_METHOD("evaluate_radiance", "sh", "dir"), &SHLighting::evaluate_radiance);
	ClassDB::bind_static_method("SHLighting", D_METHOD("evaluate_irradiance", "sh", "normal"), &SHLighting::evaluate_irradiance);
	ClassDB::bind_static_method("SHLighting", D_METHOD("from_sky", "sun_dir", "sun_color", "sky_color", "ground_color", "samples"), &SHLighting::from_sky);
	ClassDB::bind_static_method("SHLighting", D_METHOD("rotate", "sh", "rotation"), &SHLighting::rotate);

	BIND_CONSTANT(COEFFS);
}
