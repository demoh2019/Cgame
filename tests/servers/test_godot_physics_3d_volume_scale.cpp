/**************************************************************************/
/*  test_godot_physics_3d_volume_scale.cpp                                 */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, FITNESS FOR A PARTICULAR PURPOSE AND */
/* NONINFRINGEMENT.                                                        */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_3d_volume_scale)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_shape_volume_3d.h"

namespace TestGodotPhysics3DVolumeScale {

TEST_CASE("[GodotPhysics3D] Shape volume scale from basis determinant") {
	SUBCASE("Identity is volume-preserving") {
		CHECK(godot_physics_3d_volume_scale(Basis()) == doctest::Approx(1.0));
	}

	SUBCASE("Nonuniform scaling multiplies volume") {
		CHECK(godot_physics_3d_volume_scale(Basis::from_scale(Vector3(2.0, 3.0, 4.0))) == doctest::Approx(24.0));
	}

	SUBCASE("Mirroring preserves positive physical volume") {
		CHECK(godot_physics_3d_volume_scale(Basis::from_scale(Vector3(-2.0, 3.0, 4.0))) == doctest::Approx(24.0));
	}

	SUBCASE("Shear does not alter volume") {
		const Basis shear(
				real_t(1.0), real_t(1.0), real_t(0.0),
				real_t(0.0), real_t(1.0), real_t(0.0),
				real_t(0.0), real_t(0.0), real_t(1.0));
		CHECK(godot_physics_3d_volume_scale(shear) == doctest::Approx(1.0));
	}

	SUBCASE("Rotation leaves nonuniform scale volume unchanged") {
		const Basis rotation(Vector3(0.0, 0.0, 1.0), real_t(Math::PI / 3.0));
		const Basis scaled = rotation * Basis::from_scale(Vector3(2.0, 3.0, 4.0));
		CHECK(godot_physics_3d_volume_scale(scaled) == doctest::Approx(24.0));
	}

	SUBCASE("Collapsed axis has zero volume") {
		CHECK(godot_physics_3d_volume_scale(Basis::from_scale(Vector3(1.0, 0.0, 1.0))) == doctest::Approx(0.0));
	}
}

} // namespace TestGodotPhysics3DVolumeScale

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
