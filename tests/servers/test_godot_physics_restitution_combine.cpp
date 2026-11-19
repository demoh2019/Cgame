/**************************************************************************/
/*  test_godot_physics_restitution_combine.cpp                             */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#include "tests/test_macros.h"
#include "servers/physics_restitution_combine.h"

TEST_FORCE_LINK(test_godot_physics_restitution_combine)

namespace TestGodotPhysicsRestitutionCombine {

TEST_CASE("[GodotPhysics] Restitution combine modes") {
	const real_t a = real_t(0.25);
	const real_t b = real_t(0.5);
	CHECK(godot_physics_combine_restitution(a, b, 0) == doctest::Approx(0.75));
	CHECK(godot_physics_combine_restitution(a, b, 1) == doctest::Approx(0.5));
	CHECK(godot_physics_combine_restitution(a, b, 2) == doctest::Approx(0.375));
	CHECK(godot_physics_combine_restitution(a, b, 3) == doctest::Approx(0.25));
	CHECK(godot_physics_combine_restitution(a, b, 4) == doctest::Approx(0.125));
	CHECK(godot_physics_combine_restitution(a, b, 5) == doctest::Approx(Math::sqrt(0.125)));
}

TEST_CASE("[GodotPhysics] Restitution is bounded and symmetric") {
	for (int mode = 0; mode <= 5; ++mode) {
		SUBCASE("Symmetric material order") {
			CHECK(godot_physics_combine_restitution(0.2, 0.8, mode) ==
					doctest::Approx(godot_physics_combine_restitution(0.8, 0.2, mode)));
		}
		SUBCASE("Clamps invalid material coefficients") {
			const real_t result = godot_physics_combine_restitution(real_t(-2.0), real_t(4.0), mode);
			CHECK(result >= real_t(0.0));
			CHECK(result <= real_t(1.0));
		}
	}
	CHECK(godot_physics_combine_restitution(0.2, 0.4, -1) == doctest::Approx(0.6));
	CHECK(godot_physics_combine_restitution(0.2, 0.4, 99) == doctest::Approx(0.6));
	CHECK(godot_physics_combine_restitution(0.0, 0.9, 4) == doctest::Approx(0.0));
	CHECK(godot_physics_combine_restitution(0.0, 0.9, 5) == doctest::Approx(0.0));
}

} // namespace TestGodotPhysicsRestitutionCombine
