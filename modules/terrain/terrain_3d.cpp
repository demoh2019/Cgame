/**************************************************************************/
/*  terrain_3d.cpp                                                        */
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
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR AND NONINFRINGEMENT. */
/**************************************************************************/

#include "terrain_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"

#include <cmath>

Terrain3D::Terrain3D() {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    set_terrain_data(data);
}

Terrain3D::~Terrain3D() {
    if (terrain_data.is_valid()) {
        terrain_data->disconnect_changed(callable_mp(this, &Terrain3D::_terrain_changed));
    }
}

void Terrain3D::set_terrain_data(const Ref<TerrainHeightmap> &p_data) {
    if (terrain_data == p_data) {
        return;
    }
    if (terrain_data.is_valid()) {
        terrain_data->disconnect_changed(callable_mp(this, &Terrain3D::_terrain_changed));
    }
    terrain_data = p_data;
    if (terrain_data.is_valid()) {
        terrain_data->connect_changed(callable_mp(this, &Terrain3D::_terrain_changed));
    }
    rebuild();
}

Ref<TerrainHeightmap> Terrain3D::get_terrain_data() const {
    return terrain_data;
}

void Terrain3D::set_cell_size(float p_size) {
    ERR_FAIL_COND_MSG(!std::isfinite(p_size) || p_size <= 0, "Terrain cell size must be finite and positive.");
    if (cell_size == p_size) {
        return;
    }
    cell_size = p_size;
    rebuild();
}

float Terrain3D::get_cell_size() const {
    return cell_size;
}

void Terrain3D::_terrain_changed() {
    rebuild();
}

void Terrain3D::rebuild() {
    if (terrain_data.is_valid()) {
        set_mesh(terrain_data->build_mesh(cell_size));
    } else {
        set_mesh(Ref<Mesh>());
    }
}

void Terrain3D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_terrain_data", "data"), &Terrain3D::set_terrain_data);
    ClassDB::bind_method(D_METHOD("get_terrain_data"), &Terrain3D::get_terrain_data);
    ClassDB::bind_method(D_METHOD("set_cell_size", "cell_size"), &Terrain3D::set_cell_size);
    ClassDB::bind_method(D_METHOD("get_cell_size"), &Terrain3D::get_cell_size);
    ClassDB::bind_method(D_METHOD("rebuild"), &Terrain3D::rebuild);

    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain_data", PROPERTY_HINT_RESOURCE_TYPE, "TerrainHeightmap"), "set_terrain_data", "get_terrain_data");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "0.01,100.0,0.01,or_greater"), "set_cell_size", "get_cell_size");
}
