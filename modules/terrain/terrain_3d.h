/**************************************************************************/
/*  terrain_3d.h                                                          */
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
/**************************************************************************/

#pragma once

#include "scene/3d/mesh_instance_3d.h"
#include "terrain_heightmap.h"

// Editor-visible mesh node driven by a serializable TerrainHeightmap resource.
class Terrain3D : public MeshInstance3D {
    GDCLASS(Terrain3D, MeshInstance3D);

    Ref<TerrainHeightmap> terrain_data;
    float cell_size = 1.0f;

    void _terrain_changed();

protected:
    static void _bind_methods();

public:
    void set_terrain_data(const Ref<TerrainHeightmap> &p_data);
    Ref<TerrainHeightmap> get_terrain_data() const;

    void set_cell_size(float p_size);
    float get_cell_size() const;

    void rebuild();

    Terrain3D();
    ~Terrain3D();
};
