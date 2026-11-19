/**************************************************************************/
/*  test_physics_fem_tetra_cycle_fatigue.cpp                                     */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_fem_tetra_cycle_fatigue.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_cycle_fatigue)

namespace TestPhysicsFEMTetraCycleFatigue {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest));
	return rest;
}

static bool sample(PhysicsFEMTetraCycleFatigueState &s, double x, double &d,
		double endurance = 0.1, double reference = 0.3,
		double n = 10.0, double exponent = 2.0, double noise = 0.0) {
	return PhysicsFEMTetraCycleFatigue::evolve(x, endurance, reference,
			n, exponent, noise, s, d);
}

static void cycles(PhysicsFEMTetraCycleFatigueState &s, double &d,
		double height, int count) {
	CHECK(sample(s, 0.0, d));
	for (int i = 0; i < count; ++i) {
		CHECK(sample(s, height, d));
		CHECK(sample(s, 0.0, d));
	}
}

TEST_CASE("[PhysicsFEM] Cycle fatigue initialized state has no damage") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	CHECK(sample(s, 0.0, d));
	CHECK(s.initialized);
	CHECK(s.cycles == 0);
	CHECK(d == 0.0);
}

TEST_CASE("[PhysicsFEM] Fatigue constant high load does not accrue cycles") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	CHECK(sample(s, 0.0, d));
	CHECK(sample(s, 0.8, d));
	for (int i=0; i<100; ++i) CHECK(sample(s, 0.8, d));
	CHECK(d == 0.0);
	CHECK(s.cycles == 0);
}

TEST_CASE("[PhysicsFEM] Fatigue monotonic deformation does not accrue cycles") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	CHECK(sample(s, 0.0, d));
	for (int i=1; i<=50; ++i) CHECK(sample(s, 0.01*i, d));
	CHECK(d == 0.0);
	CHECK(s.cycles == 0);
}

TEST_CASE("[PhysicsFEM] Fatigue complete cycles apply Miner linear damage") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	cycles(s,d,0.6,4);
	CHECK(s.cycles == 3);
	CHECK(d == doctest::Approx(0.3).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEM] Fatigue repeated low amplitudes accumulate more slowly") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	cycles(s,d,0.4,6);
	CHECK(s.cycles == 5);
	CHECK(d == doctest::Approx(0.125).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEM] Fatigue below endurance limit counts without damage") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	cycles(s,d,0.18,8);
	CHECK(s.cycles == 7);
	CHECK(d == 0.0);
}

TEST_CASE("[PhysicsFEM] Fatigue compression cycles also contribute") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	cycles(s,d,-0.6,5);
	CHECK(s.cycles == 3);
	CHECK(d == doctest::Approx(0.3).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEM] Fatigue remains irreversible and bounded") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	cycles(s,d,1.0,20);
	CHECK(d == doctest::Approx(PhysicsFEMTetraDamage::MAX_DAMAGE));
	CHECK(sample(s, 0.0, d));
	CHECK(d == doctest::Approx(0.95));
}

TEST_CASE("[PhysicsFEM] Fatigue damage respects previous overload damage") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.35;
	cycles(s,d,0.6,2);
	CHECK(d == doctest::Approx(0.45).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Fatigue amplitude and S-N exponent change the loss") {
	PhysicsFEMTetraCycleFatigueState a,b;
	double da=0.0,db=0.0;
	cycles(a,da,0.4,4);
	cycles(b,db,0.6,4);
	CHECK(db > da);
	PhysicsFEMTetraCycleFatigueState c;
	double dc=0.0;
	CHECK(sample(c,0.0,dc,0.1,0.3,10,4));
	for (int i=0;i<4;++i) {
		CHECK(sample(c,0.4,dc,0.1,0.3,10,4));
		CHECK(sample(c,0.0,dc,0.1,0.3,10,4));
	}
	CHECK(dc < da);
}

TEST_CASE("[PhysicsFEM] Fatigue deadband suppresses subthreshold noise") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.0;
	CHECK(sample(s,0.0,d,0.1,0.3,10,2,0.05));
	for (int i=0;i<30;++i) CHECK(sample(s,(i%2?0.02:-0.02),d,0.1,0.3,10,2,0.05));
	CHECK(s.cycles == 0);
	CHECK(d == 0.0);
	CHECK(sample(s,0.3,d,0.1,0.3,10,2,0.05));
	CHECK(s.direction == 1);
}

TEST_CASE("[PhysicsFEM] Fatigue rejects bad parameter combinations atomically") {
	PhysicsFEMTetraCycleFatigueState s;
	double d=0.21;
	CHECK_FALSE(sample(s,0.4,d,0.2,0.1));
	CHECK_FALSE(sample(s,0.4,d,0.1,0.3,0));
	CHECK_FALSE(sample(s,0.4,d,0.1,0.3,10,-1));
	CHECK_FALSE(sample(s,0.4,d,0.1,0.3,10,2,-1));
	CHECK_FALSE(sample(s,std::numeric_limits<double>::quiet_NaN(),d));
	CHECK(d == 0.21);
	CHECK_FALSE(s.initialized);
}

TEST_CASE("[PhysicsFEM] Fatigue signed principal strain handles axial stretch") {
	const PhysicsFEMTetraRest r = unit_rest();
	const Vector3 x[4] = {Vector3(), Vector3(real_t(1.3),0,0),
		Vector3(0,1,0),Vector3(0,0,1)};
	double strain=0.0;
	CHECK(PhysicsFEMTetraCycleFatigue::measure_strain(x,r,strain));
	CHECK(strain == doctest::Approx(std::log(1.3)).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Fatigue negative log principal strain detects compression") {
	const PhysicsFEMTetraRest r = unit_rest();
	const Vector3 x[4] = {Vector3(), Vector3(real_t(0.6),0,0),
		Vector3(0,1,0),Vector3(0,0,1)};
	double strain=0.0;
	CHECK(PhysicsFEMTetraCycleFatigue::measure_strain(x,r,strain));
	CHECK(strain == doctest::Approx(std::log(0.6)).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Fatigue is objective under translation and rotation") {
	const PhysicsFEMTetraRest r = unit_rest();
	const Vector3 x[4] = {Vector3(), Vector3(real_t(1.3),0,0),
		Vector3(0,1,0),Vector3(0,0,1)};
	const Vector3 rotated[4] = {Vector3(3,4,5),Vector3(3,real_t(5.3),5),
		Vector3(2,4,5),Vector3(3,4,6)};
	double a=0.0,b=0.0;
	CHECK(PhysicsFEMTetraCycleFatigue::measure_strain(x,r,a));
	CHECK(PhysicsFEMTetraCycleFatigue::measure_strain(rotated,r,b));
	CHECK(a == doctest::Approx(b).epsilon(1e-4));
}

TEST_CASE("[PhysicsFEM] Fatigue detects shear through principal stretches") {
	const PhysicsFEMTetraRest r = unit_rest();
	const Vector3 x[4] = {Vector3(), Vector3(1,0,0),
		Vector3(real_t(0.5),1,0),Vector3(0,0,1)};
	double s=0.0;
	CHECK(PhysicsFEMTetraCycleFatigue::measure_strain(x,r,s));
	CHECK(Math::abs(s)>0.2);
}

TEST_CASE("[PhysicsFEM] Fatigue supports opposite winding and rejects inversion") {
	PhysicsFEMTetraRest reverse;
	const Vector3 x[4]={Vector3(),Vector3(0,1,0),Vector3(1,0,0),Vector3(0,0,1)};
	CHECK(physics_fem_tetra_make_rest(x[0],x[1],x[2],x[3],reverse));
	double s=100;
	CHECK(PhysicsFEMTetraCycleFatigue::measure_strain(x,reverse,s));
	CHECK(s == doctest::Approx(0.0));
	const Vector3 flipped[4]={Vector3(),Vector3(1,0,0),Vector3(0,1,0),Vector3(0,0,-1)};
	CHECK_FALSE(PhysicsFEMTetraCycleFatigue::measure_strain(flipped,unit_rest(),s));
}

TEST_CASE("[PhysicsFEM] Fatigue damage softens the actual FEM compliance") {
	double result=0;
	CHECK(PhysicsFEMTetraDamage::effective_compliance(0.001,0.5,result));
	CHECK(result == doctest::Approx(0.002));
}

} // namespace TestPhysicsFEMTetraCycleFatigue
