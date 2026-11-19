/**************************************************************************/
/*  random_number_generator.cpp                                           */
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

#include "random_number_generator.h"

#include "core/object/class_db.h"

void RandomNumberGenerator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &RandomNumberGenerator::set_seed);
	ClassDB::bind_method(D_METHOD("get_seed"), &RandomNumberGenerator::get_seed);

	ClassDB::bind_method(D_METHOD("set_state", "state"), &RandomNumberGenerator::set_state);
	ClassDB::bind_method(D_METHOD("get_state"), &RandomNumberGenerator::get_state);

	ClassDB::bind_method(D_METHOD("randi"), &RandomNumberGenerator::randi);
	ClassDB::bind_method(D_METHOD("randf"), &RandomNumberGenerator::randf);
	ClassDB::bind_method(D_METHOD("randfn", "mean", "deviation"), &RandomNumberGenerator::randfn, DEFVAL(0.0), DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("randf_range", "from", "to"), &RandomNumberGenerator::randf_range);
	ClassDB::bind_method(D_METHOD("randi_range", "from", "to"), &RandomNumberGenerator::randi_range);
	ClassDB::bind_method(D_METHOD("rand_weighted", "weights"), &RandomNumberGenerator::rand_weighted);

	ClassDB::bind_method(D_METHOD("rand_in_circle", "radius"), &RandomNumberGenerator::rand_in_circle, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("rand_on_circle", "radius"), &RandomNumberGenerator::rand_on_circle, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("rand_in_sphere", "radius"), &RandomNumberGenerator::rand_in_sphere, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("rand_on_sphere", "radius"), &RandomNumberGenerator::rand_on_sphere, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("rand_rotation"), &RandomNumberGenerator::rand_rotation);
	ClassDB::bind_method(D_METHOD("rand_color_hsv", "hue_min", "hue_max", "saturation_min", "saturation_max", "value_min", "value_max", "alpha_min", "alpha_max"), &RandomNumberGenerator::rand_color_hsv, DEFVAL(0.0), DEFVAL(1.0), DEFVAL(0.0), DEFVAL(1.0), DEFVAL(0.0), DEFVAL(1.0), DEFVAL(1.0), DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("randomize"), &RandomNumberGenerator::randomize);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "state"), "set_state", "get_state");
	// Default values are non-deterministic, override for doc generation purposes.
	ADD_PROPERTY_DEFAULT("seed", 0);
	ADD_PROPERTY_DEFAULT("state", 0);
}

// Uniform over the disk area: the radius needs a square root, otherwise points cluster at the center.
Vector2 RandomNumberGenerator::rand_in_circle(real_t p_radius) {
	const real_t angle = randf() * real_t(Math::TAU);
	const real_t distance = Math::sqrt(randf()) * p_radius;
	return Vector2(Math::cos(angle), Math::sin(angle)) * distance;
}

Vector2 RandomNumberGenerator::rand_on_circle(real_t p_radius) {
	const real_t angle = randf() * real_t(Math::TAU);
	return Vector2(Math::cos(angle), Math::sin(angle)) * p_radius;
}

// Archimedes: the height along one axis of a uniform point on a sphere is uniform in [-1, 1].
Vector3 RandomNumberGenerator::rand_on_sphere(real_t p_radius) {
	const real_t z = randf_range(real_t(-1.0), real_t(1.0));
	const real_t angle = randf() * real_t(Math::TAU);
	const real_t ring = Math::sqrt(MAX(real_t(0.0), real_t(1.0) - z * z));
	return Vector3(ring * Math::cos(angle), ring * Math::sin(angle), z) * p_radius;
}

// Uniform over the ball volume: the radius needs a cube root.
Vector3 RandomNumberGenerator::rand_in_sphere(real_t p_radius) {
	return rand_on_sphere(Math::pow(randf(), real_t(1.0) / real_t(3.0)) * p_radius);
}

// Shoemake's method: a uniformly distributed unit quaternion, i.e. an unbiased random orientation.
Quaternion RandomNumberGenerator::rand_rotation() {
	const real_t u1 = randf();
	const real_t u2 = randf() * real_t(Math::TAU);
	const real_t u3 = randf() * real_t(Math::TAU);
	const real_t a = Math::sqrt(real_t(1.0) - u1);
	const real_t b = Math::sqrt(u1);
	return Quaternion(a * Math::sin(u2), a * Math::cos(u2), b * Math::sin(u3), b * Math::cos(u3));
}

Color RandomNumberGenerator::rand_color_hsv(real_t p_hue_min, real_t p_hue_max, real_t p_saturation_min, real_t p_saturation_max, real_t p_value_min, real_t p_value_max, real_t p_alpha_min, real_t p_alpha_max) {
	return Color::from_hsv(randf_range(p_hue_min, p_hue_max), randf_range(p_saturation_min, p_saturation_max), randf_range(p_value_min, p_value_max), randf_range(p_alpha_min, p_alpha_max));
}
