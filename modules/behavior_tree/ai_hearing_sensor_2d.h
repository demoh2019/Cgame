/**************************************************************************/
/*  ai_hearing_sensor_2d.h                                                 */
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

#include "core/math/vector2.h"
#include "core/object/ref_counted.h"

// Event-driven single-listener hearing and stimulus memory. Games emit explicit
// noise events, optionally attenuated by walls; this class does not play audio.
class AIHearingSensor2D : public RefCounted {
	GDCLASS(AIHearingSensor2D, RefCounted);

	real_t hearing_radius = 550.0;
	real_t memory_duration = 3.0;
	real_t memory_remaining = 0.0;
	real_t last_heard_loudness = 0.0;
	Vector2 last_heard_position;

protected:
	static void _bind_methods();

public:
	void set_hearing_radius(real_t p_radius);
	real_t get_hearing_radius() const;

	void set_memory_duration(real_t p_seconds);
	real_t get_memory_duration() const;

	// Loudness is a positive multiplier of hearing_radius (1 = normal). The
	// occlusion factor [0, 1] is chosen by the game for its world geometry.
	// Returns whether this listener perceived the reported event.
	bool report_noise(const Vector2 &p_listener, const Vector2 &p_source, real_t p_loudness, real_t p_occlusion = 1.0);
	void advance_time(real_t p_delta);
	bool has_sound_memory() const;
	Vector2 get_last_heard_position() const;
	real_t get_last_heard_loudness() const;
	real_t get_memory_remaining() const;
	void reset();
};
