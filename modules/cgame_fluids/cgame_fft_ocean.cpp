/**************************************************************************/
/*  cgame_fft_ocean.cpp                                                   */
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

#include "cgame_fft_ocean.h"

#include "core/math/math_funcs.h"
#include "core/math/random_number_generator.h"

// Builds the Phillips spectrum deterministically. n must be a power of two.
void CgameFFTOcean::setup(int p_grid, real_t p_patch, const Vector2 &p_wind, real_t p_amplitude, int64_t p_seed) {
	ERR_FAIL_COND_MSG(p_grid < 4 || (p_grid & (p_grid - 1)) != 0, "CgameFFTOcean: grid must be a power of two >= 4.");
	ERR_FAIL_COND_MSG(p_patch <= 0.0, "CgameFFTOcean: patch size must be positive.");
	n = p_grid;
	patch_size = p_patch;
	last_max_imag = 0.0;
	const int count = n * n;
	h0_re.resize(count);
	h0_im.resize(count);
	omega.resize(count);
	float *hr = h0_re.ptrw();
	float *hi = h0_im.ptrw();
	float *om = omega.ptrw();

	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(p_seed);
	const real_t wind_speed = p_wind.length();
	const Vector2 wind_dir = wind_speed > 0.0001 ? p_wind.normalized() : Vector2(1, 0);
	const real_t largest = MAX(wind_speed * wind_speed / GRAVITY, real_t(0.0001));
	const real_t damp_len = largest * 0.001;
	const int half = n >> 1;
	// Serial on purpose: the random stream must be consumed in a fixed order.
	for (int j = 0; j < n; j++) {
		const int my = j < half ? j : j - n;
		for (int i = 0; i < n; i++) {
			const int mx = i < half ? i : i - n;
			const int idx = j * n + i;
			// Box-Muller pair is always drawn so the stream stays aligned.
			const real_t u1 = MAX(rng->randf(), real_t(1e-7));
			const real_t u2 = rng->randf();
			const real_t rad = Math::sqrt(-2.0 * Math::log(u1));
			const real_t gr = rad * Math::cos(Math::TAU * u2);
			const real_t gi = rad * Math::sin(Math::TAU * u2);
			const Vector2 kv = Vector2(mx, my) * (Math::TAU / patch_size);
			const real_t k2 = kv.length_squared();
			// Skip DC and the unpaired Nyquist row/column so -k always exists.
			if (k2 < 1e-12 || mx == -half || my == -half) {
				hr[idx] = 0.0;
				hi[idx] = 0.0;
				om[idx] = 0.0;
				continue;
			}
			const real_t k = Math::sqrt(k2);
			const real_t align = kv.dot(wind_dir) / k;
			real_t phillips = p_amplitude * Math::exp(-1.0 / (k2 * largest * largest)) / (k2 * k2) * align * align;
			phillips *= Math::exp(-k2 * damp_len * damp_len);
			const real_t s = Math::sqrt(phillips * 0.5);
			hr[idx] = gr * s;
			hi[idx] = gi * s;
			om[idx] = Math::sqrt(GRAVITY * k);
		}
	}
}

// Returns n*n heights (row-major) at the given time.
Vector<float> CgameFFTOcean::evaluate(real_t p_time) {
	ERR_FAIL_COND_V_MSG(n == 0, Vector<float>(), "CgameFFTOcean: call setup() before evaluate().");
	const int count = n * n;
	Vector<float> re;
	Vector<float> im;
	re.resize(count);
	im.resize(count);
	float *pre = re.ptrw();
	float *pim = im.ptrw();
	const float *hr = h0_re.ptr();
	const float *hi = h0_im.ptr();
	const float *om = omega.ptr();
	const int nn = n;
	CgameFluids::parallel_for(nn, 4, [&](int p_from, int p_to) {
		for (int j = p_from; j < p_to; j++) {
			const int nj = (nn - j) % nn;
			for (int i = 0; i < nn; i++) {
				const int ni = (nn - i) % nn;
				const int idx = j * nn + i;
				const int midx = nj * nn + ni;
				const real_t wt = om[idx] * p_time;
				const real_t c = Math::cos(wt);
				const real_t s = Math::sin(wt);
				// h0(k) e^{iwt}
				const real_t ar = hr[idx] * c - hi[idx] * s;
				const real_t ai = hr[idx] * s + hi[idx] * c;
				// conj(h0(-k)) e^{-iwt}: (xr - i xi)(c - i s)
				const real_t br = hr[midx] * c - hi[midx] * s;
				const real_t bi = -(hr[midx] * s + hi[midx] * c);
				pre[idx] = ar + br;
				pim[idx] = ai + bi;
			}
		}
	});
	_fft_2d_inverse(pre, pim);
	const real_t scale = real_t(count);
	Vector<float> out;
	out.resize(count);
	float *po = out.ptrw();
	real_t max_im = 0.0;
	for (int idx = 0; idx < count; idx++) {
		po[idx] = pre[idx] * scale;
		max_im = MAX(max_im, Math::abs(pim[idx] * scale));
	}
	last_max_imag = max_im;
	return out;
}

Ref<Image> CgameFFTOcean::displacement_image(real_t p_time) {
	const Vector<float> heights = evaluate(p_time);
	ERR_FAIL_COND_V(heights.is_empty(), Ref<Image>());
	Vector<uint8_t> raw;
	raw.resize(heights.size() * int(sizeof(float)));
	memcpy(raw.ptrw(), heights.ptr(), raw.size());
	return Image::create_from_data(n, n, false, Image::FORMAT_RF, raw);
}

real_t CgameFFTOcean::sample_height(const Vector<float> &p_heights, const Vector2 &p_position) const {
	ERR_FAIL_COND_V(n == 0 || p_heights.size() != n * n, 0.0);
	const real_t u = p_position.x / patch_size * real_t(n);
	const real_t v = p_position.y / patch_size * real_t(n);
	const real_t fu = Math::floor(u);
	const real_t fv = Math::floor(v);
	const real_t tx = u - fu;
	const real_t ty = v - fv;
	const int x0 = Math::posmod(int(fu), n);
	const int y0 = Math::posmod(int(fv), n);
	const int x1 = (x0 + 1) % n;
	const int y1 = (y0 + 1) % n;
	const float *h = p_heights.ptr();
	const real_t a = Math::lerp(h[y0 * n + x0], h[y0 * n + x1], tx);
	const real_t b = Math::lerp(h[y1 * n + x0], h[y1 * n + x1], tx);
	return Math::lerp(a, b, ty);
}

void CgameFFTOcean::_fft_2d_inverse(float *r_re, float *r_im) const {
	const int nn = n;
	// Rows: each row is transformed independently in place.
	CgameFluids::parallel_for(nn, 4, [&](int p_from, int p_to) {
		for (int j = p_from; j < p_to; j++) {
			fft_1d_inplace(r_re + j * nn, r_im + j * nn, nn, true);
		}
	});
	// Columns: gather into chunk-private scratch, transform, scatter back.
	CgameFluids::parallel_for(nn, 4, [&](int p_from, int p_to) {
		Vector<float> col_re;
		Vector<float> col_im;
		col_re.resize(nn);
		col_im.resize(nn);
		float *cr = col_re.ptrw();
		float *ci = col_im.ptrw();
		for (int i = p_from; i < p_to; i++) {
			for (int j = 0; j < nn; j++) {
				cr[j] = r_re[j * nn + i];
				ci[j] = r_im[j * nn + i];
			}
			fft_1d_inplace(cr, ci, nn, true);
			for (int j = 0; j < nn; j++) {
				r_re[j * nn + i] = cr[j];
				r_im[j * nn + i] = ci[j];
			}
		}
	});
}

// In-place radix-2 Cooley-Tukey FFT. Forward uses e^{-i...}; the inverse uses
// e^{+i...} and scales by 1/N so inverse(forward(x)) == x.
void CgameFFTOcean::fft_1d_inplace(float *r_re, float *r_im, int p_size, bool p_inverse) {
	if (p_size < 2) {
		return;
	}
	ERR_FAIL_COND_MSG((p_size & (p_size - 1)) != 0, "CgameFFTOcean: fft size must be a power of two.");
	// Bit-reversal permutation.
	int j = 0;
	for (int i = 1; i < p_size; i++) {
		int bit = p_size >> 1;
		while (j & bit) {
			j ^= bit;
			bit >>= 1;
		}
		j ^= bit;
		if (i < j) {
			SWAP(r_re[i], r_re[j]);
			SWAP(r_im[i], r_im[j]);
		}
	}
	const real_t sign = p_inverse ? 1.0 : -1.0;
	for (int len = 2; len <= p_size; len <<= 1) {
		const real_t ang = sign * Math::TAU / real_t(len);
		const real_t wr = Math::cos(ang);
		const real_t wi = Math::sin(ang);
		const int half_len = len >> 1;
		for (int start = 0; start < p_size; start += len) {
			real_t cr = 1.0;
			real_t ci = 0.0;
			for (int k = 0; k < half_len; k++) {
				const int a = start + k;
				const int b = a + half_len;
				const real_t xr = r_re[b] * cr - r_im[b] * ci;
				const real_t xi = r_re[b] * ci + r_im[b] * cr;
				r_re[b] = r_re[a] - xr;
				r_im[b] = r_im[a] - xi;
				r_re[a] += xr;
				r_im[a] += xi;
				const real_t ncr = cr * wr - ci * wi;
				ci = cr * wi + ci * wr;
				cr = ncr;
			}
		}
	}
	if (p_inverse) {
		const real_t inv = 1.0 / real_t(p_size);
		for (int i = 0; i < p_size; i++) {
			r_re[i] *= inv;
			r_im[i] *= inv;
		}
	}
}

Array CgameFFTOcean::_fft_1d_bind(const Vector<float> &p_re, const Vector<float> &p_im, bool p_inverse) {
	Array result;
	ERR_FAIL_COND_V_MSG(p_re.size() != p_im.size(), result, "CgameFFTOcean.fft_1d: re and im must have the same size.");
	ERR_FAIL_COND_V_MSG(p_re.size() >= 2 && (p_re.size() & (p_re.size() - 1)) != 0, result, "CgameFFTOcean.fft_1d: size must be a power of two.");
	Vector<float> re = p_re;
	Vector<float> im = p_im;
	fft_1d_inplace(re.ptrw(), im.ptrw(), re.size(), p_inverse);
	result.push_back(re);
	result.push_back(im);
	return result;
}

void CgameFFTOcean::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "grid", "patch", "wind", "amplitude", "seed"), &CgameFFTOcean::setup);
	ClassDB::bind_method(D_METHOD("evaluate", "time"), &CgameFFTOcean::evaluate);
	ClassDB::bind_method(D_METHOD("displacement_image", "time"), &CgameFFTOcean::displacement_image);
	ClassDB::bind_method(D_METHOD("sample_height", "heights", "position"), &CgameFFTOcean::sample_height);
	ClassDB::bind_static_method("CgameFFTOcean", D_METHOD("fft_1d", "re", "im", "inverse"), &CgameFFTOcean::_fft_1d_bind);

	CGF_BIND_READONLY_PROPERTY(CgameFFTOcean, Variant::INT, n)
	CGF_BIND_READONLY_PROPERTY(CgameFFTOcean, Variant::FLOAT, patch_size)
	CGF_BIND_READONLY_PROPERTY(CgameFFTOcean, Variant::FLOAT, last_max_imag)
}
