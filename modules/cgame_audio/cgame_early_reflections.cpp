/**************************************************************************/
/*  cgame_early_reflections.cpp                                           */
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

#include "cgame_early_reflections.h"

#include "core/math/math_funcs.h"
#include "core/math/random_pcg.h"
#include "core/object/class_db.h"
#include "core/templates/local_vector.h"
#include "core/variant/dictionary.h"

namespace {

struct ImageSource {
	double delay_s;
	double gain;
	Vector3 direction;
	int order;
	double distance;
	int index; // Generation order, used as a deterministic tie-break.
};

struct ImageSourceLess {
	bool operator()(const ImageSource &p_a, const ImageSource &p_b) const {
		if (p_a.delay_s != p_b.delay_s) {
			return p_a.delay_s < p_b.delay_s;
		}
		return p_a.index < p_b.index;
	}
};

double image_axis(int p_n, double p_length, double p_s) {
	if (p_n % 2 == 0) {
		return double(p_n) * p_length + p_s;
	}
	return double(p_n) * p_length + (p_length - p_s);
}

} // namespace

int CgameEarlyReflections::image_source_count(int p_order) {
	const int64_t n = MAX(p_order, 0);
	// Number of integer points with |x| + |y| + |z| <= n (centred octahedral number).
	return int((2 * n + 1) * (2 * n * n + 2 * n + 3) / 3);
}

TypedArray<Dictionary> CgameEarlyReflections::image_sources_box(const Vector3 &p_room_size, const Vector3 &p_source, const Vector3 &p_listener, int p_order, float p_absorption, float p_speed) {
	TypedArray<Dictionary> result;
	const double speed = p_speed > 0.0f ? double(p_speed) : 343.0;
	const double refl = Math::sqrt(CLAMP(1.0 - double(p_absorption), 0.0, 1.0));
	const int max_order = CLAMP(p_order, 0, 32);

	LocalVector<ImageSource> images;
	images.reserve(image_source_count(max_order));
	int counter = 0;
	for (int nx = -max_order; nx <= max_order; nx++) {
		const int rx = Math::abs(nx);
		const double ix = image_axis(nx, p_room_size.x, p_source.x);
		for (int ny = -(max_order - rx); ny <= max_order - rx; ny++) {
			const int rxy = rx + Math::abs(ny);
			const double iy = image_axis(ny, p_room_size.y, p_source.y);
			const int rem = max_order - rxy;
			for (int nz = -rem; nz <= rem; nz++) {
				const int bounces = rxy + Math::abs(nz);
				const double iz = image_axis(nz, p_room_size.z, p_source.z);
				const Vector3 delta = Vector3(real_t(ix), real_t(iy), real_t(iz)) - p_listener;
				const double dist = delta.length();
				ImageSource img;
				img.distance = dist;
				img.delay_s = dist / speed;
				img.gain = Math::pow(refl, double(bounces)) / MAX(dist, MIN_DISTANCE);
				img.direction = dist > 0.000001 ? delta / real_t(dist) : Vector3();
				img.order = bounces;
				img.index = counter++;
				images.push_back(img);
			}
		}
	}
	images.sort_custom<ImageSourceLess>();

	result.resize(images.size());
	for (uint32_t i = 0; i < images.size(); i++) {
		const ImageSource &img = images[i];
		Dictionary d;
		d["delay_s"] = img.delay_s;
		d["gain"] = img.gain;
		d["direction"] = img.direction;
		d["order"] = img.order;
		d["distance"] = img.distance;
		result[i] = d;
	}
	return result;
}

TypedArray<Dictionary> CgameEarlyReflections::echogram_to_reflections(const PackedFloat32Array &p_echogram, float p_bin_s) {
	TypedArray<Dictionary> result;
	for (int i = 0; i < p_echogram.size(); i++) {
		if (p_echogram[i] > 0.0f) {
			Dictionary d;
			d["delay_s"] = (double(i) + 0.5) * double(p_bin_s);
			d["gain"] = Math::sqrt(double(p_echogram[i]));
			d["direction"] = Vector3();
			d["order"] = 1;
			result.push_back(d);
		}
	}
	return result;
}

PackedFloat32Array CgameEarlyReflections::impulse_response(const Vector3 &p_rt60, int p_sample_rate, float p_seconds, int64_t p_seed) {
	const int count = MAX(int(double(p_seconds) * double(p_sample_rate)), 1);
	PackedFloat32Array out;
	out.resize(count);
	float *w = out.ptrw();

	RandomPCG rng;
	rng.seed(uint64_t(p_seed));
	const double rate = double(MAX(p_sample_rate, 1));
	const double coef_lo = 1.0 - Math::exp(-Math::TAU * 300.0 / rate);
	const double coef_hi = 1.0 - Math::exp(-Math::TAU * 3000.0 / rate);
	double lp_lo = 0.0;
	double lp_hi = 0.0;
	const double t60_lo = MAX(double(p_rt60.x), 0.02);
	const double t60_mid = MAX(double(p_rt60.y), 0.02);
	const double t60_hi = MAX(double(p_rt60.z), 0.02);
	double peak = 0.0;
	for (int i = 0; i < count; i++) {
		const double n = rng.random(-1.0, 1.0);
		lp_lo += coef_lo * (n - lp_lo);
		lp_hi += coef_hi * (n - lp_hi);
		const double time = double(i) / rate;
		const double low = lp_lo * Math::pow(10.0, -3.0 * time / t60_lo);
		const double mid = (lp_hi - lp_lo) * Math::pow(10.0, -3.0 * time / t60_mid);
		const double high = (n - lp_hi) * Math::pow(10.0, -3.0 * time / t60_hi);
		const double s = low + mid + high;
		w[i] = float(s);
		peak = MAX(peak, Math::abs(s));
	}
	if (peak > 0.0) {
		const float inv = float(1.0 / peak);
		for (int i = 0; i < count; i++) {
			w[i] *= inv;
		}
	}
	return out;
}

PackedFloat32Array CgameEarlyReflections::to_ir(const TypedArray<Dictionary> &p_reflections, int p_sample_rate, float p_length_s, const Vector3 &p_rt60, float p_late_start_s, float p_late_gain, int64_t p_seed) {
	const int count = MAX(int(double(p_length_s) * double(p_sample_rate)), 1);
	PackedFloat32Array ir;
	ir.resize(count);
	float *w = ir.ptrw();
	for (int i = 0; i < count; i++) {
		w[i] = 0.0f;
	}

	for (int r = 0; r < p_reflections.size(); r++) {
		const Dictionary d = p_reflections[r];
		const double pos = double(d.get("delay_s", 0.0)) * double(p_sample_rate);
		const int i0 = int(Math::floor(pos));
		const float frac = float(pos - double(i0));
		const float g = float(double(d.get("gain", 0.0)));
		if (i0 >= 0 && i0 < count) {
			w[i0] += g * (1.0f - frac);
		}
		if (i0 + 1 >= 0 && i0 + 1 < count) {
			w[i0 + 1] += g * frac;
		}
	}
	float early_peak = 0.0f;
	for (int i = 0; i < count; i++) {
		early_peak = MAX(early_peak, Math::abs(w[i]));
	}
	if (early_peak > 0.0f) {
		for (int i = 0; i < count; i++) {
			w[i] /= early_peak;
		}
	}

	const PackedFloat32Array tail = impulse_response(p_rt60, p_sample_rate, p_length_s, p_seed);
	const float fade = MAX(p_late_start_s * float(p_sample_rate), 1.0f);
	for (int i = 0; i < count; i++) {
		const float wgt = CLAMP(float(i) / fade, 0.0f, 1.0f);
		w[i] += tail[i] * p_late_gain * wgt * wgt;
	}

	float peak = 0.0f;
	for (int i = 0; i < count; i++) {
		peak = MAX(peak, Math::abs(w[i]));
	}
	if (peak > 0.0f) {
		for (int i = 0; i < count; i++) {
			w[i] /= peak;
		}
	}
	return ir;
}

void CgameEarlyReflections::_bind_methods() {
	ClassDB::bind_static_method("CgameEarlyReflections", D_METHOD("image_sources_box", "room_size", "source", "listener", "order", "absorption", "speed"), &CgameEarlyReflections::image_sources_box, DEFVAL(343.0f));
	ClassDB::bind_static_method("CgameEarlyReflections", D_METHOD("echogram_to_reflections", "echogram", "bin_s"), &CgameEarlyReflections::echogram_to_reflections);
	ClassDB::bind_static_method("CgameEarlyReflections", D_METHOD("impulse_response", "rt60", "sample_rate", "seconds", "seed"), &CgameEarlyReflections::impulse_response);
	ClassDB::bind_static_method("CgameEarlyReflections", D_METHOD("to_ir", "reflections", "sample_rate", "length_s", "rt60", "late_start_s", "late_gain", "seed"), &CgameEarlyReflections::to_ir, DEFVAL(Vector3(0.7, 0.6, 0.4)), DEFVAL(0.04f), DEFVAL(0.25f), DEFVAL(1));
	ClassDB::bind_static_method("CgameEarlyReflections", D_METHOD("image_source_count", "order"), &CgameEarlyReflections::image_source_count);
}
