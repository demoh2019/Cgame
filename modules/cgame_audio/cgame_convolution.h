/**************************************************************************/
/*  cgame_convolution.h                                                   */
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

// Uniformly partitioned overlap-save FFT convolution (frequency-domain delay line).
//
// Algorithm: classic uniformly partitioned convolution, see W. G. Gardner, "Efficient
// Convolution without Input-Output Delay", JAES 43(3), 1995 and F. Wefers, "Partitioned
// convolution algorithms for real-time auralization", 2015. The impulse response is cut
// into partitions of `block` samples, each zero-padded to 2 * block and transformed once.
// Every input block is transformed once, stored in a ring of past spectra and multiplied
// and accumulated with the matching IR partition spectra; one inverse FFT per block yields
// the output. FFT: own iterative radix-2 Cooley-Tukey, written from scratch for this module.
//
// Latency: the streaming engine collects `block` input frames before it can emit the
// matching output block, so the wet signal is delayed by exactly `block` frames.

#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "servers/audio/audio_frame.h"

class CgameFFT {
	int n = 0;
	LocalVector<double> cos_table;
	LocalVector<double> sin_table;
	LocalVector<int> rev;

public:
	// Size must be a power of two >= 2.
	void init(int p_size);
	int size() const { return n; }
	// In-place transform. The inverse is scaled by 1/N.
	void transform(double *r_re, double *r_im, bool p_inverse) const;
};

class CgameConvolutionKernel : public RefCounted {
	GDCLASS(CgameConvolutionKernel, RefCounted);

public:
	static constexpr int MIN_BLOCK = 16;
	static constexpr int MAX_BLOCK = 16384;

	int block = 0; // Partition length (power of two).
	int fft_size = 0; // 2 * block.
	int bins = 0; // block + 1 (non-redundant real spectrum).
	int parts = 0;
	int channels = 0; // 1 (mono IR shared by both channels) or 2.
	int length_frames = 0; // Longest IR in samples.
	CgameFFT fft;
	LocalVector<double> h_re[2];
	LocalVector<double> h_im[2];

	static int round_block(int p_block);

	// Builds partition spectra. Right may be null to share left across both channels.
	bool build(const float *p_left, int p_left_len, const float *p_right, int p_right_len, int p_block);

	// Reference O(N*M) convolution; r_out must hold p_n + p_m - 1 samples.
	static void direct_convolve(const float *p_x, int p_n, const float *p_h, int p_m, float *r_out);
};

// Per-channel streaming state (frequency-domain delay line and scratch buffers).
class CgameConvolutionState {
	int head = 0;
	LocalVector<double> fdl_re;
	LocalVector<double> fdl_im;
	LocalVector<float> prev;
	LocalVector<double> re;
	LocalVector<double> im;
	LocalVector<double> acc_re;
	LocalVector<double> acc_im;

public:
	void setup(const CgameConvolutionKernel &p_kernel);
	void reset();
	// Convolves exactly one block (kernel.block samples).
	void process_block(const CgameConvolutionKernel &p_kernel, int p_channel, const float *p_in, float *r_out);
};

// Stereo streaming convolver working on arbitrary frame counts. Allocation happens only in
// setup(); process() never allocates and is safe to call from the audio thread.
class CgameConvolutionEngine {
	Ref<CgameConvolutionKernel> kernel;
	CgameConvolutionState state[2];
	LocalVector<float> in_block[2];
	LocalVector<float> out_block[2];
	int fill = 0;
	int64_t quiet_frames = 0;

public:
	void setup(const Ref<CgameConvolutionKernel> &p_kernel);
	void reset();
	const Ref<CgameConvolutionKernel> &get_kernel() const { return kernel; }
	int get_latency_frames() const { return kernel.is_valid() ? kernel->block : 0; }
	// True while the reverb tail of previously received input can still be audible.
	bool is_tail_active() const;
	// Wet output only (no dry mix); p_src and r_wet must not overlap.
	void process(const AudioFrame *p_src, AudioFrame *r_wet, int p_frames);
};
