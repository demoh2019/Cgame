/**************************************************************************/
/*  ai_visual_sensor_2d                                                  */
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

// Single-target deterministic visual perception. The caller supplies LOS from
// its own physics world; the sensor handles cone/range checks and target memory.
class AIVisualSensor2D : public RefCounted {
    GDCLASS(AIVisualSensor2D, RefCounted);

    real_t sight_radius = 240.0;
    real_t lose_sight_radius = 300.0;
    real_t field_of_view_degrees = 180.0;
    real_t memory_duration = 1.5;

    bool target_visible = false;
    real_t memory_remaining = 0.0;
    Vector2 last_known_position;

protected:
    static void _bind_methods();

public:
    void set_sight_radius(real_t p_radius);
    real_t get_sight_radius() const;

    void set_lose_sight_radius(real_t p_radius);
    real_t get_lose_sight_radius() const;

    void set_field_of_view_degrees(real_t p_degrees);
    real_t get_field_of_view_degrees() const;

    void set_memory_duration(real_t p_seconds);
    real_t get_memory_duration() const;

    // Update once per AI/physics tick. An unobstructed ray from observer to
    // target should be passed as p_has_line_of_sight.
    void observe(const Vector2 &p_observer, const Vector2 &p_forward, const Vector2 &p_target, bool p_has_line_of_sight, real_t p_delta);
    bool is_target_visible() const;
    bool has_target_memory() const;
    Vector2 get_last_known_position() const;
    real_t get_memory_remaining() const;
    void reset();
};
