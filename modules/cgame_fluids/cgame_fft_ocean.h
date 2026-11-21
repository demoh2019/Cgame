/**************************************************************************/
/*  cgame_fft_ocean.h                                                     */
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

// Tessendorf FFT ocean heightfield (J. Tessendorf, "Simulating Ocean Water", 2001).
// A Phillips spectrum h0(k) is built once from a seed; each evaluation computes
// h(k,t) = h0(k) e^{iwt} + conj(h0(-k)) e^{-iwt} (w = sqrt(g|k|), deep water
// dispersion) and transforms it with an inverse 2D radix-2 Cooley-Tukey FFT into a
// real, tileable height grid that can be sampled on the CPU (buoyancy) or uploaded
// as a shader texture (vertex displacement). Rows and columns of the 2D transform
// are independent and run on the WorkerThreadPool; the result is bit-identical to a
// serial run.

#include "cgame_fluids_common.h"

#include "core/io/image.h"
#include "core/math/vector2.h"
#include "core/object/ref_counted.h"
#include "core/variant/array.h"

class CgameFFTOcean : public RefCounted {
	GDCLASS(CgameFFTOcean, RefCounted);

public:
	static constexpr real_t GRAVITY = 9.81;

private:
	int n = 0;
	real_t patch_size = 1.0;
	// Largest |imag| seen by the last evaluate() (should be ~0 for a real field).
	real_t last_max_imag = 0.0;

	Vector<float> h0_re;
	Vector<float> h0_im;
	Vector<float> omega;

	void _fft_2d_inverse(float *r_re, float *r_im) const;

protected:
	static void _bind_methods();

	// Script-facing wrapper: returns [re, im] because packed arrays are passed by value.
	static Array _fft_1d_bind(const Vector<float> &p_re, const Vector<float> &p_im, bool p_inverse);

public:
	// Builds the Phillips spectrum deterministically. grid must be a power of two >= 4.
	void setup(int p_grid, real_t p_patch, const Vector2 &p_wind, real_t p_amplitude, int64_t p_seed);

	// Returns n*n heights (row-major) at the given time.
	Vector<float> evaluate(real_t p_time);
	// Heights as a single-channel float image for a displacement shader.
	Ref<Image> displacement_image(real_t p_time);
	// Bilinear, wrapping sample of a previously evaluated height grid at world xz.
	real_t sample_height(const Vector<float> &p_heights, const Vector2 &p_position) const;

	// In-place radix-2 FFT on raw arrays of length p_size (a power of two). Forward uses
	// e^{-i...}; the inverse uses e^{+i...} and scales by 1/N so inverse(forward(x)) == x.
	static void fft_1d_inplace(float *r_re, float *r_im, int p_size, bool p_inverse);

	CGF_GETTER(int, n)
	CGF_GETTER(real_t, patch_size)
	CGF_GETTER(real_t, last_max_imag)

	CgameFFTOcean() {}
};
