/**************************************************************************/
/*  terrain_collision_3d.cpp                                              */
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

#ifndef PHYSICS_3D_DISABLED

#include "terrain_collision_3d.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"

void TerrainCollision3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_terrain", "terrain"), &TerrainCollision3D::set_terrain);
	ClassDB::bind_method(D_METHOD("get_terrain"), &TerrainCollision3D::get_terrain);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain", PROPERTY_HINT_RESOURCE_TYPE, "TerrainMesh"), "set_terrain", "get_terrain");
}

void TerrainCollision3D::_terrain_changed() {
	if (terrain.is_null()) {
		generated_shape.unref();
		set_shape(Ref<Shape3D>());
		return;
	}

	// Collision vertices already contain cell_size and height_scale,
	// unlike HeightMapShape3D, which assumes unit-spaced X/Z samples.
	// No non-uniform CollisionShape3D scaling is required.
	const Vector<Face3> faces = terrain->get_faces();
	Vector<Vector3> triangles;
	triangles.resize(faces.size() * 3);
	Vector3 *w = triangles.ptrw();
	for (int i = 0; i < faces.size(); i++) {
		w[i * 3] = faces[i].vertex[0];
		w[i * 3 + 1] = faces[i].vertex[1];
		w[i * 3 + 2] = faces[i].vertex[2];
	}

	if (generated_shape.is_null()) {
		generated_shape.instantiate();
	}
	generated_shape->set_faces(triangles);
	if (get_shape().ptr() != generated_shape.ptr()) {
		set_shape(generated_shape);
	}
}

void TerrainCollision3D::set_terrain(const Ref<TerrainMesh> &p_terrain) {
	if (terrain == p_terrain) {
		return;
	}
	const Callable changed = callable_mp(this, &TerrainCollision3D::_terrain_changed);
	if (terrain.is_valid()) {
		terrain->disconnect_changed(changed);
	}
	terrain = p_terrain;
	if (terrain.is_valid()) {
		terrain->connect_changed(changed);
	}
	_terrain_changed();
}

Ref<TerrainMesh> TerrainCollision3D::get_terrain() const {
	return terrain;
}

TerrainCollision3D::~TerrainCollision3D() {
	if (terrain.is_valid()) {
		terrain->disconnect_changed(callable_mp(this, &TerrainCollision3D::_terrain_changed));
	}
}

#endif // PHYSICS_3D_DISABLED
