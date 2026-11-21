/**************************************************************************/
/*  cgame_vram_budget.h                                                   */
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

// GPU memory budget (UE5 r.Streaming.PoolSize / texture budget, Unity memory budget): watches live
// video memory and, under sustained pressure, tells Auto quality to step down before the driver
// starts paging.
class CgameVRAMBudget : public RefCounted {
	GDCLASS(CgameVRAMBudget, RefCounted);

public:
	static constexpr double BUDGET_MB[4] = { 1536.0, 2560.0, 4096.0, 6144.0 };
	static constexpr double PRESSURE = 0.92; // Share of the budget that counts as pressure.
	static constexpr double RELIEF = 0.75; // Upgrades are blocked above this share.
	static constexpr double SUSTAIN = 2.0; // Seconds of pressure before sample() reports it.

private:
	double pressure_seconds = 0.0;

protected:
	static void _bind_methods();

public:
	static double budget_bytes(int p_level);
	static double used_bytes();
	static bool upgrade_allowed(double p_used, int p_level);

	// True once memory has stayed above the pressure line for SUSTAIN seconds.
	bool sample(double p_used, int p_level, double p_delta);
	double get_pressure_seconds() const { return pressure_seconds; }
	void reset();
};
