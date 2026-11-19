/**************************************************************************/
/*  physics_xpbd_rod_torsion.h                                            */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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

#include "servers/physics_xpbd_dihedral.h"

// Signed GEOMETRIC torsion of a four-particle rod centerline (a,b,c,d).
// It is the signed angle between the bending planes (a,b,c) and (b,c,d)
// around the middle segment (b,c). The dihedral kernel is reused with
// pivot=(b,c), opposite vertices=(a,d); its robust wrapped angular error,
// analytical gradients, pin handling, and finite checks are shared.
//
// IMPORTANT: this is not the material-frame twist of a Cosserat rod. A
// perfectly straight centerline has undefined bending-plane normals, so
// its twist about the longitudinal axis cannot be represented with only
// particle positions. Real material-frame twist needs independent segment
// orientations, angular inertia, and bend/twist coupling.
_FORCE_INLINE_ static bool physics_xpbd_rod_geometric_torsion_angle(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d, real_t &r_angle) {
	return physics_xpbd_dihedral_angle(p_b, p_c, p_a, p_d, r_angle);
}

// XPBD torsion projection: uses compliance/dt^2 and one step-local lambda.
// Correct node-to-dihedral mapping matters; the outer positions are a,d,
// and b,c are the two shared middle segment vertices.
_FORCE_INLINE_ static bool physics_xpbd_solve_rod_geometric_torsion(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_rest_angle, real_t p_alpha, real_t &r_lambda) {
	return physics_xpbd_solve_dihedral(r_b, r_c, r_a, r_d,
			p_inv_b, p_inv_c, p_inv_a, p_inv_d,
			p_rest_angle, p_alpha, r_lambda);
}
