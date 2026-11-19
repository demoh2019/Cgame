/**************************************************************************/
/*  test_physics_vehicle_combined_tire_grip.cpp                           */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/*  a copy of this software and associated documentation files (the       */
/*  "Software"), to deal in the Software without restriction, including   */
/*  without limitation the rights to use, copy, modify, merge, publish,   */
/*  distribute, sublicense, and/or sell copies of the Software, and to    */
/*  permit persons to whom the Software is furnished to do so, subject to */
/*  the following conditions:                                             */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#include "servers/physics_vehicle_combined_tire_grip.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_vehicle_combined_tire_grip)

namespace TestPhysicsVehicleCombinedTireGrip {

TEST_CASE("[PhysicsVehicle] Original isotropic wheel grip is unchanged below the traction budget") {
	double forward = -1.0, side = -1.0, skid = 0.0;
	CHECK(physics_vehicle_project_combined_tire_impulses(4, -3, 10, 1, 1, 1, forward, side, skid));
	CHECK(forward == doctest::Approx(4));
	CHECK(side == doctest::Approx(-3));
	CHECK(skid == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsVehicle] Pure longitudinal wheelspin is now capped without side slip") {
	double forward = 0.0, side = 5.0, skid = 1.0;
	CHECK(physics_vehicle_project_combined_tire_impulses(-100, 0, 10, 1, 1, 1, forward, side, skid));
	CHECK(forward == doctest::Approx(-20.0));
	CHECK(side == doctest::Approx(0.0));
	CHECK(skid == doctest::Approx(0.2));
}

TEST_CASE("[PhysicsVehicle] Cornering and acceleration share one friction ellipse") {
	double forward = 0.0, side = 0.0, skid = 1.0;
	CHECK(physics_vehicle_project_combined_tire_impulses(20, 10, 10, 1, 1, 1, forward, side, skid));
	CHECK(skid == doctest::Approx(1.0 / Math::sqrt(2.0)));
	CHECK(forward == doctest::Approx(20.0 / Math::sqrt(2.0)));
	CHECK(side == doctest::Approx(10.0 / Math::sqrt(2.0)));
}

TEST_CASE("[PhysicsVehicle] Per-wheel directional tire grip preserves independent caps") {
	double f = 0.0, s = 0.0, skid = 0.0;
	CHECK(physics_vehicle_project_combined_tire_impulses(20, 10, 10, 1, .5, 2, f, s, skid));
	CHECK(f == doctest::Approx(20.0 / Math::sqrt(4.25)));
	CHECK(s == doctest::Approx(10.0 / Math::sqrt(4.25)));
	CHECK(skid == doctest::Approx(1.0 / Math::sqrt(4.25)));
}

TEST_CASE("[PhysicsVehicle] Disabling a single traction direction leaves the other usable") {
	double f = -1.0, s = -1.0, skid = 1.0;
	CHECK(physics_vehicle_project_combined_tire_impulses(100, 6, 10, 1, 0, 1, f, s, skid));
	CHECK(f == 0.0);
	CHECK(s == doctest::Approx(6.0));
	CHECK(skid == 0.0);
	CHECK(physics_vehicle_project_combined_tire_impulses(8, -100, 10, 1, 1, 0, f, s, skid));
	CHECK(f == doctest::Approx(8.0));
	CHECK(s == 0.0);
	CHECK(skid == 0.0);
}

TEST_CASE("[PhysicsVehicle] No normal suspension impulse means zero tire traction") {
	double f = 4.0, s = 8.0, skid = 1.0;
	CHECK(physics_vehicle_project_combined_tire_impulses(400, 100, 0, 1, 1, 1, f, s, skid));
	CHECK(f == 0.0);
	CHECK(s == 0.0);
	CHECK(skid == 0.0);
	CHECK(physics_vehicle_project_combined_tire_impulses(0, 0, 0, 1, 1, 1, f, s, skid));
	CHECK(skid == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsVehicle] Slip power, direction and suspension load scale together") {
	double f1 = 0.0, s1 = 0.0, skid1 = 0.0;
	double f2 = 0.0, s2 = 0.0, skid2 = 0.0;
	CHECK(physics_vehicle_project_combined_tire_impulses(-30, 12, 10, 1, 1, 1, f1, s1, skid1));
	CHECK(physics_vehicle_project_combined_tire_impulses(-60, 24, 20, 1, 1, 1, f2, s2, skid2));
	CHECK(f2 == doctest::Approx(f1 * 2));
	CHECK(s2 == doctest::Approx(s1 * 2));
	CHECK(skid1 == doctest::Approx(skid2));
}

TEST_CASE("[PhysicsVehicle] Invalid tire inputs never propagate NaN or infinite impulses") {
	const double inf = std::numeric_limits<double>::infinity();
	const double nan = std::numeric_limits<double>::quiet_NaN();
	double f = -100.0, s = 5.0, skid = 1.0;
	CHECK_FALSE(physics_vehicle_project_combined_tire_impulses(nan, 5, 10, 1, 1, 1, f, s, skid));
	CHECK(f == 0.0);
	CHECK(s == 0.0);
	CHECK(skid == 0.0);
	CHECK_FALSE(physics_vehicle_project_combined_tire_impulses(2, inf, 10, 1, 1, 1, f, s, skid));
	CHECK_FALSE(physics_vehicle_project_combined_tire_impulses(2, 2, -1, 1, 1, 1, f, s, skid));
	CHECK_FALSE(physics_vehicle_project_combined_tire_impulses(2, 2, 10, -1, 1, 1, f, s, skid));
	CHECK_FALSE(physics_vehicle_project_combined_tire_impulses(2, 2, 10, 1, 5, 1, f, s, skid));
	CHECK_FALSE(physics_vehicle_project_combined_tire_impulses(2, 2, 10, 1, 1, nan, f, s, skid));
	CHECK(f == 0.0);
	CHECK(s == 0.0);
	CHECK(skid == 0.0);
}

} // namespace TestPhysicsVehicleCombinedTireGrip
