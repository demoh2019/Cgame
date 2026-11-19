/**************************************************************************/
/*  physics_cast_motion_pruning.h                                         */
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

#include "core/math/aabb.h"
#include "core/math/rect2.h"

// Conservative query bound for a shape cast whose closest known unsafe
// fraction has decreased. A collision earlier than p_max_fraction must
// overlap this union of the starting and clipped ending shape AABBs.
// Expand slightly so boundary contacts and floating-point roundoff are
// not removed by the optional second broadphase filter.
template <typename TBounds, typename TVector>
_FORCE_INLINE_ TBounds godot_physics_cast_motion_clipped_aabb(const TBounds &p_start_aabb, const TVector &p_motion, real_t p_max_fraction, real_t p_margin) {
	const TBounds end_aabb(p_start_aabb.position + p_motion * p_max_fraction, p_start_aabb.size);
	return p_start_aabb.merge(end_aabb).grow(MAX(real_t(0.0), p_margin) + real_t(CMP_EPSILON));
}
