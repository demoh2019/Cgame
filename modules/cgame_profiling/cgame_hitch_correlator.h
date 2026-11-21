/**************************************************************************/
/*  cgame_hitch_correlator.h                                              */
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
#include "core/templates/local_vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Explains frame hitches. The static correlate() names, for every frame slower than a threshold,
// the scopes that grew most versus the rolling median of the preceding frames and the counters
// that jumped. The instance API (sample()) classifies live hitches by the engine counter that
// moved with them: pipeline compilation, world streaming or VRAM growth.
class CgameHitchCorrelator : public RefCounted {
	GDCLASS(CgameHitchCorrelator, RefCounted);

public:
	static constexpr int WINDOW = 60;
	static constexpr int TOP_SCOPES = 3;
	static constexpr int SAMPLE_WINDOW = 120;
	static constexpr int SAMPLE_KEEP = 32;
	static constexpr double MIN_HITCH_SEC = 0.05;
	static constexpr double HITCH_FACTOR = 2.5;
	static constexpr double VRAM_JUMP = 64.0 * 1024.0 * 1024.0;

private:
	TypedArray<Dictionary> hitches;
	Dictionary counts;
	LocalVector<double> sampled_frames;
	Dictionary last_counters;

protected:
	static void _bind_methods();

public:
	static Array correlate(const Array &p_frames, double p_threshold_ms);
	static Dictionary read_counters(int p_loaded_cells = 0);
	static String cause(const Dictionary &p_before, const Dictionary &p_after);

	Dictionary sample(double p_delta, const Dictionary &p_counters, double p_now = 0.0);
	double median() const;
	String describe() const;
	TypedArray<Dictionary> get_hitches() const { return hitches; }
	Dictionary get_counts() const { return counts; }
	void reset();

	CgameHitchCorrelator();
};
