/**************************************************************************/
/*  heightmap_terrain_3d.cpp                                              */
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

#include "heightmap_terrain_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/resources/material.h"
#ifndef PHYSICS_3D_DISABLED
#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/3d/physics/static_body_3d.h"
#include "scene/resources/3d/concave_polygon_shape_3d.h"
#endif

void HeightmapTerrain3D::_heightmap_changed() {
    _rebuild_mesh();
}

Ref<ArrayMesh> HeightmapTerrain3D::build_mesh() const {
    Ref<ArrayMesh> result;
    result.instantiate();
    if (heightmap.is_null()) {
        return result;
    }

    const int w = heightmap->get_width();
    const int d = heightmap->get_depth();
    const PackedFloat32Array heights = heightmap->get_heights();
    const PackedColorArray colors = heightmap->get_colors();
    if (w < 2 || d < 2 || heights.size() != w * d || colors.size() != w * d) {
        return result;
    }

    const int count = w * d;
    const int triangle_index_count = (w - 1) * (d - 1) * 6;

    PackedVector3Array vertices;
    PackedVector3Array normals;
    PackedVector2Array uvs;
    PackedColorArray vertex_colors;
    PackedInt32Array indices;

    vertices.resize(count);
    normals.resize(count);
    uvs.resize(count);
    vertex_colors.resize(count);
    indices.resize(triangle_index_count);

    Vector3 *vertex_write = vertices.ptrw();
    Vector3 *normal_write = normals.ptrw();
    Vector2 *uv_write = uvs.ptrw();
    Color *color_write = vertex_colors.ptrw();
    int32_t *index_write = indices.ptrw();

    for (int z = 0; z < d; ++z) {
        for (int x = 0; x < w; ++x) {
            const int index = z * w + x;
            vertex_write[index] = Vector3(x * cell_size, heights[index], z * cell_size);
            uv_write[index] = Vector2(real_t(x) / (w - 1), real_t(z) / (d - 1));
            color_write[index] = colors[index];

            const int left = MAX(x - 1, 0);
            const int right = MIN(x + 1, w - 1);
            const int up = MAX(z - 1, 0);
            const int down = MIN(z + 1, d - 1);
            const real_t dx = (real_t(heights[z * w + left]) - real_t(heights[z * w + right])) /
                              ((right - left) * cell_size);
            const real_t dz = (real_t(heights[up * w + x]) - real_t(heights[down * w + x])) /
                              ((down - up) * cell_size);
            normal_write[index] = Vector3(dx, 1.0, dz).normalized();
        }
    }

    int next = 0;
    for (int z = 0; z < d - 1; ++z) {
        for (int x = 0; x < w - 1; ++x) {
            const int a = z * w + x;
            const int b = a + 1;
            const int c = a + w;
            const int e = c + 1;
            // Consistent counter-clockwise winding viewed from above (+Y).
            index_write[next++] = a;
            index_write[next++] = c;
            index_write[next++] = b;
            index_write[next++] = b;
            index_write[next++] = c;
            index_write[next++] = e;
        }
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    arrays[Mesh::ARRAY_NORMAL] = normals;
    arrays[Mesh::ARRAY_TEX_UV] = uvs;
    arrays[Mesh::ARRAY_COLOR] = vertex_colors;
    arrays[Mesh::ARRAY_INDEX] = indices;
    result->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);

    Ref<Material> material = terrain_material.is_valid() ? terrain_material : default_material;
    if (material.is_valid()) {
        result->surface_set_material(0, material);
    }
    return result;
}

void HeightmapTerrain3D::_rebuild_mesh() {
    // This is a small terrain prototype: updates replace one mesh surface.
    // Chunking/LOD will be handled separately for large worlds.
    set_mesh(build_mesh());
#ifndef PHYSICS_3D_DISABLED
    _queue_collision_rebuild();
#endif
}

void HeightmapTerrain3D::set_heightmap(const Ref<TerrainHeightmap> &p_heightmap) {
    if (heightmap == p_heightmap) {
        return;
    }
    if (heightmap.is_valid()) {
        heightmap->disconnect_changed(callable_mp(this, &HeightmapTerrain3D::_heightmap_changed));
    }
    heightmap = p_heightmap;
    if (heightmap.is_valid()) {
        heightmap->connect_changed(callable_mp(this, &HeightmapTerrain3D::_heightmap_changed));
    }
    _rebuild_mesh();
}

Ref<TerrainHeightmap> HeightmapTerrain3D::get_heightmap() const {
    return heightmap;
}

void HeightmapTerrain3D::set_cell_size(real_t p_size) {
    ERR_FAIL_COND_MSG(!Math::is_finite(p_size) || p_size <= CMP_EPSILON, "Terrain cell size must be positive and finite.");
    if (cell_size == p_size) {
        return;
    }
    cell_size = p_size;
    _rebuild_mesh();
}

real_t HeightmapTerrain3D::get_cell_size() const {
    return cell_size;
}

void HeightmapTerrain3D::set_terrain_material(const Ref<Material> &p_material) {
    if (terrain_material == p_material) {
        return;
    }
    terrain_material = p_material;
    _rebuild_mesh();
}

Ref<Material> HeightmapTerrain3D::get_terrain_material() const {
    return terrain_material;
}

real_t HeightmapTerrain3D::sample_height_local(real_t p_x, real_t p_z) const {
    if (heightmap.is_null()) {
        return 0.0;
    }
    return heightmap->sample_height(p_x / cell_size, p_z / cell_size);
}


#ifndef PHYSICS_3D_DISABLED
// The edited vertex colors and materials do not change the shape; on
// terrain-height edits, coalesce all physics-server mutations into one
// deferred main-thread update. Standalone nodes rebuild synchronously
// so they can also be used by offline asset tools and doctests.
void HeightmapTerrain3D::_queue_collision_rebuild() {
    if (!automatic_collision) {
        return;
    }
    if (is_inside_tree()) {
        if (!collision_rebuild_pending) {
            collision_rebuild_pending = true;
            call_deferred(SNAME("_update_auto_collision"));
        }
    } else {
        _update_auto_collision();
    }
}

void HeightmapTerrain3D::_update_auto_collision() {
    collision_rebuild_pending = false;
    if (!automatic_collision || heightmap.is_null()) {
        return;
    }
    const int w = heightmap->get_width();
    const int d = heightmap->get_depth();
    const PackedFloat32Array heights = heightmap->get_heights();
    if (w < 2 || d < 2 || heights.size() != w * d) {
        if (collision_shape != nullptr) {
            collision_shape->set_disabled(true);
        }
        generated_collision_triangles = 0;
        return;
    }
    if (collision_shape != nullptr && collision_shape->get_shape().is_valid() &&
            w == last_collision_width && d == last_collision_depth &&
            collision_step == last_collision_step && cell_size == last_collision_cell_size &&
            heights == last_collision_heights) {
        collision_shape->set_disabled(false);
        return; // Painting vertex colors or changing materials is collision-neutral.
    }
    // Bound collision geometry even on 513x513 source terrains. Coarsen only
    // the physics mesh; full-resolution visual data is never overwritten.
    constexpr int MAX_COLLISION_TRIANGLES = 8192;
    int step = collision_step;
    while (((w - 2) / step + 1) * ((d - 2) / step + 1) * 2 > MAX_COLLISION_TRIANGLES) {
        step *= 2;
    }
    const int count = ((w - 2) / step + 1) * ((d - 2) / step + 1) * 2;
    Vector<Vector3> faces;
    faces.resize(count * 3);
    Vector3 *write = faces.ptrw();
    const float *hr = heights.ptr();
    int cursor = 0;
    for (int z = 0; z < d - 1; z += step) {
        const int z1 = MIN(z + step, d - 1);
        for (int x = 0; x < w - 1; x += step) {
            const int x1 = MIN(x + step, w - 1);
            const Vector3 a(x * cell_size, hr[z * w + x], z * cell_size);
            const Vector3 b(x1 * cell_size, hr[z * w + x1], z * cell_size);
            const Vector3 c(x * cell_size, hr[z1 * w + x], z1 * cell_size);
            const Vector3 e(x1 * cell_size, hr[z1 * w + x1], z1 * cell_size);
            write[cursor++] = a;
            write[cursor++] = c;
            write[cursor++] = b;
            write[cursor++] = b;
            write[cursor++] = c;
            write[cursor++] = e;
        }
    }
    Ref<ConcavePolygonShape3D> shape;
    shape.instantiate();
    shape->set_faces(faces);
    if (collision_body == nullptr) {
        collision_body = memnew(StaticBody3D);
        collision_body->set_name("TerrainAutoCollisionBody");
        add_child(collision_body, false, Node::INTERNAL_MODE_BACK);
        collision_shape = memnew(CollisionShape3D);
        collision_shape->set_name("TerrainAutoCollisionShape");
        collision_body->add_child(collision_shape, false, Node::INTERNAL_MODE_BACK);
    }
    collision_shape->set_shape(shape);
    collision_shape->set_disabled(false);
    generated_collision_triangles = count;
    last_collision_width = w;
    last_collision_depth = d;
    last_collision_step = collision_step;
    last_collision_cell_size = cell_size;
    last_collision_heights = heights;
}

void HeightmapTerrain3D::set_auto_collision_enabled(bool p_enabled) {
    if (automatic_collision == p_enabled) {
        return;
    }
    automatic_collision = p_enabled;
    if (automatic_collision) {
        _queue_collision_rebuild();
    } else if (collision_shape != nullptr) {
        collision_shape->set_disabled(true);
    }
}

bool HeightmapTerrain3D::is_auto_collision_enabled() const {
    return automatic_collision;
}

void HeightmapTerrain3D::set_auto_collision_step(int p_step) {
    ERR_FAIL_COND_MSG(p_step < 1 || p_step > 16, "Terrain collision step must be in [1, 16].");
    if (collision_step == p_step) {
        return;
    }
    collision_step = p_step;
    _queue_collision_rebuild();
}

int HeightmapTerrain3D::get_auto_collision_step() const {
    return collision_step;
}

int HeightmapTerrain3D::get_auto_collision_triangle_count() const {
    return automatic_collision ? generated_collision_triangles : 0;
}

Ref<Shape3D> HeightmapTerrain3D::get_auto_collision_shape() const {
    return collision_shape != nullptr ? collision_shape->get_shape() : Ref<Shape3D>();
}
#endif // PHYSICS_3D_DISABLED

void HeightmapTerrain3D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_heightmap", "heightmap"), &HeightmapTerrain3D::set_heightmap);
    ClassDB::bind_method(D_METHOD("get_heightmap"), &HeightmapTerrain3D::get_heightmap);
    ClassDB::bind_method(D_METHOD("set_cell_size", "cell_size"), &HeightmapTerrain3D::set_cell_size);
    ClassDB::bind_method(D_METHOD("get_cell_size"), &HeightmapTerrain3D::get_cell_size);
    ClassDB::bind_method(D_METHOD("set_terrain_material", "material"), &HeightmapTerrain3D::set_terrain_material);
    ClassDB::bind_method(D_METHOD("get_terrain_material"), &HeightmapTerrain3D::get_terrain_material);
    ClassDB::bind_method(D_METHOD("sample_height_local", "x", "z"), &HeightmapTerrain3D::sample_height_local);
    ClassDB::bind_method(D_METHOD("build_mesh"), &HeightmapTerrain3D::build_mesh);
#ifndef PHYSICS_3D_DISABLED
    ClassDB::bind_method(D_METHOD("_update_auto_collision"), &HeightmapTerrain3D::_update_auto_collision);
    ClassDB::bind_method(D_METHOD("set_auto_collision_enabled", "enabled"), &HeightmapTerrain3D::set_auto_collision_enabled);
    ClassDB::bind_method(D_METHOD("is_auto_collision_enabled"), &HeightmapTerrain3D::is_auto_collision_enabled);
    ClassDB::bind_method(D_METHOD("set_auto_collision_step", "step"), &HeightmapTerrain3D::set_auto_collision_step);
    ClassDB::bind_method(D_METHOD("get_auto_collision_step"), &HeightmapTerrain3D::get_auto_collision_step);
    ClassDB::bind_method(D_METHOD("get_auto_collision_triangle_count"), &HeightmapTerrain3D::get_auto_collision_triangle_count);
    ClassDB::bind_method(D_METHOD("get_auto_collision_shape"), &HeightmapTerrain3D::get_auto_collision_shape);
#endif

    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "heightmap", PROPERTY_HINT_RESOURCE_TYPE, "TerrainHeightmap",
                         PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT), "set_heightmap", "get_heightmap");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "0.01,100,0.01,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain_material", PROPERTY_HINT_RESOURCE_TYPE, "BaseMaterial3D,ShaderMaterial"), "set_terrain_material", "get_terrain_material");
#ifndef PHYSICS_3D_DISABLED
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_collision_enabled"), "set_auto_collision_enabled", "is_auto_collision_enabled");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "auto_collision_step", PROPERTY_HINT_RANGE, "1,16,1"), "set_auto_collision_step", "get_auto_collision_step");
#endif
}

HeightmapTerrain3D::HeightmapTerrain3D() {
    Ref<StandardMaterial3D> material;
    material.instantiate();
    material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
    default_material = material;

    Ref<TerrainHeightmap> initial_heightmap;
    initial_heightmap.instantiate();
    set_heightmap(initial_heightmap);
}

HeightmapTerrain3D::~HeightmapTerrain3D() {
    if (heightmap.is_valid()) {
        heightmap->disconnect_changed(callable_mp(this, &HeightmapTerrain3D::_heightmap_changed));
    }
}
