/**************************************************************************/
/*  test_cgame_terrain_authoring.h                                        */
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

#include "../cgame_hydraulic_erosion.h"
#include "../cgame_terrain_splines.h"

#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

// Mirrors tests/test_terrain_authoring.gd: hydraulic/thermal erosion and spline terrain authoring.
namespace TestCgameTerrainAuthoring {

constexpr int W = 64;
constexpr int H = 64;

static PackedFloat32Array make_slope() {
	// Tilted plane with a shallow trench and a little deterministic bumpiness.
	PackedFloat32Array a;
	a.resize(W * H);
	for (int y = 0; y < H; y++) {
		for (int x = 0; x < W; x++) {
			const double trench = -2.0 * Math::exp(-Math::pow(((double)x - 32.0) / 5.0, 2.0));
			const double bump = Math::sin((double)x * 0.7) * Math::cos((double)y * 0.5) * 0.3;
			a.set(y * W + x, (float)(30.0 - (double)y * 0.4 + trench + bump));
		}
	}
	return a;
}

static double sum_of(const PackedFloat32Array &p_a) {
	double s = 0.0;
	for (int i = 0; i < p_a.size(); i++) {
		s += p_a[i];
	}
	return s;
}

static bool arrays_equal(const PackedFloat32Array &p_a, const PackedFloat32Array &p_b) {
	if (p_a.size() != p_b.size()) {
		return false;
	}
	for (int i = 0; i < p_a.size(); i++) {
		if (p_a[i] != p_b[i]) {
			return false;
		}
	}
	return true;
}

static bool near_value(double p_a, double p_b, double p_tol) {
	return Math::abs(p_a - p_b) <= p_tol;
}

TEST_CASE("[CgameHydraulicErosion] Droplet erosion is deterministic, conservative and reshapes the valley") {
	const PackedFloat32Array base = make_slope();
	const PackedFloat32Array snapshot = base.duplicate();
	const PackedFloat32Array a = CgameHydraulicErosion::erode(base, W, H, 2000, 7);
	const PackedFloat32Array b = CgameHydraulicErosion::erode(base, W, H, 2000, 7);
	const PackedFloat32Array c = CgameHydraulicErosion::erode(base, W, H, 2000, 8);
	CHECK_MESSAGE(arrays_equal(a, b), "same seed gives same result");
	CHECK_FALSE_MESSAGE(arrays_equal(a, c), "different seed gives different result");
	CHECK_MESSAGE(arrays_equal(base, snapshot), "input array is not mutated");

	int lowered = 0;
	bool finite = true;
	int changed = 0;
	for (int i = 0; i < a.size(); i++) {
		if (a[i] < base[i] - 0.0001f) {
			lowered++;
		}
		if (!Math::is_finite(a[i])) {
			finite = false;
		}
		if (Math::abs(a[i] - base[i]) > 0.001f) {
			changed++;
		}
	}
	CHECK_MESSAGE(lowered > 0, "erosion lowers some cells");
	CHECK_MESSAGE(finite, "heights stay finite");
	const double before_sum = sum_of(base);
	CHECK_MESSAGE(Math::abs(sum_of(a) - before_sum) / Math::abs(before_sum) < 0.02, "mass conserved within 2%");
	CHECK_MESSAGE(changed > 100, "droplets reshape many cells");

	// Upper reach of the valley: the source zone (sediment settles further downslope).
	double valley_before = 0.0;
	double valley_after = 0.0;
	for (int y = 3; y < 14; y++) {
		for (int x = 30; x < 35; x++) {
			valley_before += base[y * W + x];
			valley_after += a[y * W + x];
		}
	}
	CHECK_MESSAGE(valley_after < valley_before, "valley cells lower on average (channel carved)");

	// Invalid input is returned unchanged.
	const PackedFloat32Array tiny = CgameHydraulicErosion::erode(base, 2, 2, 10, 1);
	CHECK(arrays_equal(tiny, base));
}

TEST_CASE("[CgameHydraulicErosion] Thermal erosion lowers slopes and conserves mass") {
	PackedFloat32Array spike = make_slope();
	spike.set(32 * W + 32, spike[32 * W + 32] + 12.0f);
	const double slope_before = CgameHydraulicErosion::max_slope(spike, W, H);
	const PackedFloat32Array th = CgameHydraulicErosion::thermal(spike, W, H, 40, 0.6);
	CHECK_MESSAGE(CgameHydraulicErosion::max_slope(th, W, H) < slope_before, "thermal reduces max slope");
	CHECK_MESSAGE(Math::abs(sum_of(th) - sum_of(spike)) < 0.01 * Math::abs(sum_of(spike)), "thermal conserves mass");
	CHECK_MESSAGE(th[32 * W + 32] < spike[32 * W + 32], "thermal lowers the spike");
}

TEST_CASE("[CgameHydraulicErosion] Thermal erosion is identical on repeated (threaded) runs") {
	// 160 x 160 cells crosses the threshold that distributes rows over the WorkerThreadPool.
	const int n = 160;
	PackedFloat32Array hs;
	hs.resize(n * n);
	for (int y = 0; y < n; y++) {
		for (int x = 0; x < n; x++) {
			hs.set(y * n + x, (float)(Math::sin((double)x * 0.31) * Math::cos((double)y * 0.17) * 6.0 + (double)((x * 7 + y * 13) % 5)));
		}
	}
	const PackedFloat32Array r1 = CgameHydraulicErosion::thermal(hs, n, n, 6, 0.5);
	const PackedFloat32Array r2 = CgameHydraulicErosion::thermal(hs, n, n, 6, 0.5);
	CHECK(arrays_equal(r1, r2));
	CHECK(CgameHydraulicErosion::max_slope(r1, n, n) < CgameHydraulicErosion::max_slope(hs, n, n));
}

TEST_CASE("[CgameTerrainSplines] Catmull-Rom passes through control points") {
	PackedVector3Array ctrl;
	ctrl.push_back(Vector3(4, 10, 4));
	ctrl.push_back(Vector3(20, 11, 30));
	ctrl.push_back(Vector3(40, 9, 36));
	ctrl.push_back(Vector3(58, 10, 58));
	const PackedVector3Array sp = CgameTerrainSplines::catmull_rom(ctrl, 8);
	CHECK(sp.size() == 3 * 8 + 1);
	bool passes = true;
	for (int i = 0; i < ctrl.size(); i++) {
		if (!sp[i * 8].is_equal_approx(ctrl[i])) {
			passes = false;
		}
	}
	CHECK_MESSAGE(passes, "spline passes through control points");

	PackedVector2Array seg;
	seg.push_back(Vector2(0, 0));
	seg.push_back(Vector2(10, 0));
	CHECK(near_value(CgameTerrainSplines::distance_to_polyline(Vector2(5, 5), seg), 5.0, 0.0001));
	CHECK(near_value(CgameTerrainSplines::distance_to_polyline(Vector2(15, 0), seg), 5.0, 0.0001));
	CHECK(Math::is_inf(CgameTerrainSplines::distance_to_polyline(Vector2(1, 1), PackedVector2Array())));
}

TEST_CASE("[CgameTerrainSplines] Deform flattens, carves and raises") {
	PackedFloat32Array flat;
	flat.resize(W * H);
	for (int i = 0; i < flat.size(); i++) {
		flat.set(i, 20.0f + (float)(i % 5) * 0.2f);
	}
	PackedVector3Array road;
	road.push_back(Vector3(0, 8, 32));
	road.push_back(Vector3(63, 8, 32));
	const PackedFloat32Array d = CgameTerrainSplines::deform(flat, W, H, 1.0, road, 3.0, 4.0, "flatten");
	CHECK_MESSAGE(near_value(d[32 * W + 30], 8.0, 0.001), "flatten sets road height under centre");
	CHECK_MESSAGE(d[10 * W + 30] == flat[10 * W + 30], "flatten leaves far cells untouched");
	CHECK_MESSAGE((d[36 * W + 30] > 8.0f && d[36 * W + 30] < flat[36 * W + 30]), "flatten blends across the falloff");

	PackedVector3Array river;
	river.push_back(Vector3(0, 20, 32));
	river.push_back(Vector3(63, 20, 32));
	const PackedFloat32Array cv = CgameTerrainSplines::deform(flat, W, H, 1.0, river, 2.0, 4.0, "carve");
	CHECK_MESSAGE(cv[32 * W + 30] < cv[37 * W + 30], "carved bed lies below the banks");
	CHECK_MESSAGE(cv[32 * W + 30] <= 19.0f + 0.001f, "river centre is depth 1 below the spline");
	CHECK_MESSAGE(cv[10 * W + 30] == flat[10 * W + 30], "carve leaves far cells untouched");

	PackedFloat32Array low;
	low.resize(W * H);
	low.fill(5.0f);
	PackedVector3Array embankment;
	embankment.push_back(Vector3(0, 8, 32));
	embankment.push_back(Vector3(63, 8, 32));
	const PackedFloat32Array emb = CgameTerrainSplines::deform(low, W, H, 1.0, embankment, 2.0, 3.0, "raise");
	CHECK_MESSAGE(near_value(emb[32 * W + 20], 8.0, 0.001), "raise lifts to embankment height");
	CHECK_MESSAGE(emb[5 * W + 20] == 5.0f, "raise leaves far cells untouched");

	// Unknown modes and invalid input leave the terrain unchanged.
	CHECK(arrays_equal(CgameTerrainSplines::deform(flat, W, H, 1.0, road, 3.0, 4.0, "bogus"), flat));
	CHECK(arrays_equal(CgameTerrainSplines::deform(flat, W, H, 1.0, PackedVector3Array(), 3.0, 4.0, "flatten"), flat));
}

TEST_CASE("[CgameTerrainSplines] Bridge spans cross ravines only") {
	PackedFloat32Array ravine;
	ravine.resize(W * H);
	for (int y = 0; y < H; y++) {
		for (int x = 0; x < W; x++) {
			ravine.set(y * W + x, 10.0f - ((x >= 24 && x <= 38) ? 8.0f : 0.0f));
		}
	}
	PackedVector3Array line;
	line.push_back(Vector3(0, 10, 32));
	line.push_back(Vector3(63, 10, 32));
	const PackedVector3Array dense = CgameTerrainSplines::catmull_rom(line, 63);
	const TypedArray<Dictionary> spans = CgameTerrainSplines::bridge_spans(ravine, W, H, 1.0, dense, 2.0);
	CHECK_MESSAGE(spans.size() == 1, "one bridge across the ravine");
	if (spans.size() == 1) {
		const Dictionary span = spans[0];
		const int s0 = span["start"];
		const int s1 = span["end"];
		CHECK_MESSAGE((s0 >= 22 && s0 <= 26 && s1 >= 36 && s1 <= 40), "span covers the ravine");
	}
	PackedFloat32Array flat;
	flat.resize(W * H);
	flat.fill(20.0f);
	PackedVector3Array level;
	level.push_back(Vector3(0, 20, 10));
	level.push_back(Vector3(63, 20, 10));
	CHECK_MESSAGE(CgameTerrainSplines::bridge_spans(flat, W, H, 1.0, level, 2.0).size() == 0, "no bridge on level ground");
}

} // namespace TestCgameTerrainAuthoring
