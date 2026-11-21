/**************************************************************************/
/*  cgame_convolution.cpp                                                 */
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

#include "cgame_convolution.h"

#include "core/math/math_funcs.h"

void CgameFFT::init(int p_size) {
	n = p_size;
	cos_table.resize(n / 2);
	sin_table.resize(n / 2);
	for (int i = 0; i < n / 2; i++) {
		const double a = Math::TAU * double(i) / double(n);
		cos_table[i] = Math::cos(a);
		sin_table[i] = Math::sin(a);
	}
	int bits = 0;
	while ((1 << bits) < n) {
		bits++;
	}
	rev.resize(n);
	for (int i = 0; i < n; i++) {
		int r = 0;
		for (int j = 0; j < bits; j++) {
			if (i & (1 << j)) {
				r |= 1 << (bits - 1 - j);
			}
		}
		rev[i] = r;
	}
}

void CgameFFT::transform(double *r_re, double *r_im, bool p_inverse) const {
	for (int i = 0; i < n; i++) {
		const int j = rev[i];
		if (j > i) {
			SWAP(r_re[i], r_re[j]);
			SWAP(r_im[i], r_im[j]);
		}
	}
	const double sign = p_inverse ? 1.0 : -1.0;
	for (int size = 2; size <= n; size *= 2) {
		const int half_size = size / 2;
		const int step = n / size;
		for (int start = 0; start < n; start += size) {
			for (int k = 0; k < half_size; k++) {
				const double wr = cos_table[k * step];
				const double wi = sign * sin_table[k * step];
				const int a = start + k;
				const int c = a + half_size;
				const double xr = r_re[c] * wr - r_im[c] * wi;
				const double xi = r_re[c] * wi + r_im[c] * wr;
				r_re[c] = r_re[a] - xr;
				r_im[c] = r_im[a] - xi;
				r_re[a] += xr;
				r_im[a] += xi;
			}
		}
	}
	if (p_inverse) {
		const double inv = 1.0 / double(n);
		for (int i = 0; i < n; i++) {
			r_re[i] *= inv;
			r_im[i] *= inv;
		}
	}
}

int CgameConvolutionKernel::round_block(int p_block) {
	int b = MIN_BLOCK;
	while (b < p_block && b < MAX_BLOCK) {
		b *= 2;
	}
	return b;
}

bool CgameConvolutionKernel::build(const float *p_left, int p_left_len, const float *p_right, int p_right_len, int p_block) {
	ERR_FAIL_NULL_V(p_left, false);
	ERR_FAIL_COND_V(p_left_len <= 0, false);
	block = round_block(p_block);
	fft_size = 2 * block;
	bins = block + 1;
	channels = (p_right != nullptr && p_right_len > 0) ? 2 : 1;
	length_frames = MAX(p_left_len, channels == 2 ? p_right_len : 0);
	parts = (length_frames + block - 1) / block;
	fft.init(fft_size);

	LocalVector<double> re;
	LocalVector<double> im;
	re.resize(fft_size);
	im.resize(fft_size);

	for (int c = 0; c < channels; c++) {
		const float *ir = c == 0 ? p_left : p_right;
		const int ir_len = c == 0 ? p_left_len : p_right_len;
		h_re[c].resize(size_t(parts) * bins);
		h_im[c].resize(size_t(parts) * bins);
		for (int p = 0; p < parts; p++) {
			for (int i = 0; i < fft_size; i++) {
				re[i] = 0.0;
				im[i] = 0.0;
			}
			const int base = p * block;
			for (int i = 0; i < block; i++) {
				const int idx = base + i;
				if (idx < ir_len) {
					re[i] = ir[idx];
				}
			}
			fft.transform(re.ptr(), im.ptr(), false);
			const size_t off = size_t(p) * bins;
			for (int k = 0; k < bins; k++) {
				h_re[c][off + k] = re[k];
				h_im[c][off + k] = im[k];
			}
		}
	}
	return true;
}

void CgameConvolutionKernel::direct_convolve(const float *p_x, int p_n, const float *p_h, int p_m, float *r_out) {
	if (p_n <= 0 || p_m <= 0) {
		return;
	}
	for (int i = 0; i < p_n + p_m - 1; i++) {
		r_out[i] = 0.0f;
	}
	for (int i = 0; i < p_n; i++) {
		const float xi = p_x[i];
		if (xi == 0.0f) {
			continue;
		}
		for (int j = 0; j < p_m; j++) {
			r_out[i + j] += xi * p_h[j];
		}
	}
}

void CgameConvolutionState::setup(const CgameConvolutionKernel &p_kernel) {
	const size_t total = size_t(p_kernel.parts) * p_kernel.bins;
	fdl_re.resize(total);
	fdl_im.resize(total);
	prev.resize(p_kernel.block);
	re.resize(p_kernel.fft_size);
	im.resize(p_kernel.fft_size);
	acc_re.resize(p_kernel.bins);
	acc_im.resize(p_kernel.bins);
	reset();
}

void CgameConvolutionState::reset() {
	for (uint32_t i = 0; i < fdl_re.size(); i++) {
		fdl_re[i] = 0.0;
		fdl_im[i] = 0.0;
	}
	for (uint32_t i = 0; i < prev.size(); i++) {
		prev[i] = 0.0f;
	}
	head = 0;
}

void CgameConvolutionState::process_block(const CgameConvolutionKernel &p_kernel, int p_channel, const float *p_in, float *r_out) {
	const int b = p_kernel.block;
	const int n = p_kernel.fft_size;
	const int bins = p_kernel.bins;
	const int parts = p_kernel.parts;
	const int kc = MIN(p_channel, p_kernel.channels - 1);

	double *rp = re.ptr();
	double *ip = im.ptr();
	for (int i = 0; i < b; i++) {
		rp[i] = prev[i];
		const float s = p_in[i];
		rp[b + i] = s;
		prev[i] = s;
	}
	for (int i = 0; i < n; i++) {
		ip[i] = 0.0;
	}
	p_kernel.fft.transform(rp, ip, false);

	head = (head - 1 + parts) % parts;
	double *fr = fdl_re.ptr();
	double *fi = fdl_im.ptr();
	const size_t head_off = size_t(head) * bins;
	for (int k = 0; k < bins; k++) {
		fr[head_off + k] = rp[k];
		fi[head_off + k] = ip[k];
	}

	double *ar = acc_re.ptr();
	double *ai = acc_im.ptr();
	for (int k = 0; k < bins; k++) {
		ar[k] = 0.0;
		ai[k] = 0.0;
	}
	const double *hr_base = p_kernel.h_re[kc].ptr();
	const double *hi_base = p_kernel.h_im[kc].ptr();
	int slot = head;
	for (int p = 0; p < parts; p++) {
		const double *xr = fr + size_t(slot) * bins;
		const double *xi = fi + size_t(slot) * bins;
		const double *hr = hr_base + size_t(p) * bins;
		const double *hi = hi_base + size_t(p) * bins;
		for (int k = 0; k < bins; k++) {
			ar[k] += xr[k] * hr[k] - xi[k] * hi[k];
			ai[k] += xr[k] * hi[k] + xi[k] * hr[k];
		}
		slot++;
		if (slot == parts) {
			slot = 0;
		}
	}

	// Rebuild the Hermitian-symmetric spectrum and transform back.
	for (int k = 0; k < bins; k++) {
		rp[k] = ar[k];
		ip[k] = ai[k];
	}
	for (int k = 1; k < b; k++) {
		rp[n - k] = ar[k];
		ip[n - k] = -ai[k];
	}
	p_kernel.fft.transform(rp, ip, true);
	for (int i = 0; i < b; i++) {
		r_out[i] = float(rp[b + i]);
	}
}

void CgameConvolutionEngine::setup(const Ref<CgameConvolutionKernel> &p_kernel) {
	kernel = p_kernel;
	if (kernel.is_null()) {
		return;
	}
	for (int c = 0; c < 2; c++) {
		state[c].setup(**kernel);
		in_block[c].resize(kernel->block);
		out_block[c].resize(kernel->block);
	}
	reset();
}

void CgameConvolutionEngine::reset() {
	if (kernel.is_null()) {
		return;
	}
	for (int c = 0; c < 2; c++) {
		state[c].reset();
		for (int i = 0; i < kernel->block; i++) {
			in_block[c][i] = 0.0f;
			out_block[c][i] = 0.0f;
		}
	}
	fill = 0;
	quiet_frames = 0;
}

bool CgameConvolutionEngine::is_tail_active() const {
	if (kernel.is_null()) {
		return false;
	}
	return quiet_frames < int64_t(kernel->length_frames) + 2 * int64_t(kernel->block);
}

void CgameConvolutionEngine::process(const AudioFrame *p_src, AudioFrame *r_wet, int p_frames) {
	if (kernel.is_null()) {
		for (int i = 0; i < p_frames; i++) {
			r_wet[i] = AudioFrame(0, 0);
		}
		return;
	}
	const int b = kernel->block;
	for (int i = 0; i < p_frames; i++) {
		const float l = p_src[i].left;
		const float r = p_src[i].right;
		r_wet[i] = AudioFrame(out_block[0][fill], out_block[1][fill]);
		in_block[0][fill] = l;
		in_block[1][fill] = r;
		if (Math::abs(l) > 1e-9f || Math::abs(r) > 1e-9f) {
			quiet_frames = 0;
		} else if (quiet_frames < INT64_MAX / 2) {
			quiet_frames++;
		}
		fill++;
		if (fill == b) {
			for (int c = 0; c < 2; c++) {
				state[c].process_block(**kernel, c, in_block[c].ptr(), out_block[c].ptr());
			}
			fill = 0;
		}
	}
}
