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
#include "scene/resources/image_texture.h"
#include "scene/resources/material.h"
#include "scene/resources/shader.h"

void HeightmapTerrain3D::_heightmap_changed() {
    if (heightmap.is_valid() && splatmap.is_valid() &&
            (splatmap->get_width() != heightmap->get_width() ||
                    splatmap->get_depth() != heightmap->get_depth())) {
        splatmap->set_dimensions(heightmap->get_width(), heightmap->get_depth());
    }
    _rebuild_mesh();
}

void HeightmapTerrain3D::_splatmap_changed() {
    _refresh_splat_texture();
}

void HeightmapTerrain3D::_refresh_splat_texture() {
    if (splatmap.is_null()) {
        splat_texture.unref();
        if (blend_material.is_valid()) {
            blend_material->set_shader_parameter(SNAME("splat_weights"), Ref<ImageTexture>());
        }
        return;
    }
    const Ref<Image> image = splatmap->to_image();
    if (splat_texture.is_valid() && splat_texture->get_width() == image->get_width() &&
            splat_texture->get_height() == image->get_height()) {
        splat_texture->update(image);
    } else {
        splat_texture = ImageTexture::create_from_image(image);
    }
    if (blend_material.is_valid()) {
        blend_material->set_shader_parameter(SNAME("splat_weights"), splat_texture);
    }
}

void HeightmapTerrain3D::_refresh_layer_material() {
    bool has_textures = false;
    for (int i = 0; i < 4; ++i) {
        has_textures |= texture_layers[i].is_valid();
    }
    if (!has_textures) {
        blend_material.unref();
        return;
    }
    if (blend_material.is_null()) {
        Ref<Shader> shader;
        shader.instantiate();
        shader->set_code(R"SHADER(shader_type spatial;
render_mode cull_back;

uniform sampler2D splat_weights : filter_linear, repeat_disable;
uniform sampler2D layer_0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_3 : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_tiling : hint_range(0.01, 256.0) = 8.0;

void fragment() {
    // Splatmap weights are linear data, never sRGB color channels.
    // Map grid vertex UVs to texel centers, preventing a half-pixel offset.
    vec2 mask_size = vec2(textureSize(splat_weights, 0));
    vec2 mask_uv = (UV * (mask_size - vec2(1.0)) + vec2(0.5)) / mask_size;
    vec4 weights = max(texture(splat_weights, mask_uv), vec4(0.0));
    weights /= max(dot(weights, vec4(1.0)), 0.00001);
    vec2 tiled_uv = UV * texture_tiling;
    vec3 a = texture(layer_0, tiled_uv).rgb;
    vec3 b = texture(layer_1, tiled_uv).rgb;
    vec3 c = texture(layer_2, tiled_uv).rgb;
    vec3 d = texture(layer_3, tiled_uv).rgb;
    ALBEDO = (a * weights.r + b * weights.g + c * weights.b + d * weights.a) * COLOR.rgb;
    ROUGHNESS = 1.0;
}
)SHADER");
        blend_material.instantiate();
        blend_material->set_shader(shader);
    }
    if (splat_texture.is_null() && splatmap.is_valid()) {
        _refresh_splat_texture();
    }
    if (white_texture.is_null()) {
        const Ref<Image> white = Image::create_empty(1, 1, false, Image::FORMAT_RGBA8);
        white->set_pixel(0, 0, Color(1, 1, 1));
        white_texture = ImageTexture::create_from_image(white);
    }

    blend_material->set_shader_parameter(SNAME("splat_weights"), splat_texture);
    blend_material->set_shader_parameter(SNAME("texture_tiling"), texture_tiling);
    blend_material->set_shader_parameter(SNAME("layer_0"), texture_layers[0].is_valid() ? texture_layers[0] : Ref<Texture2D>(white_texture));
    blend_material->set_shader_parameter(SNAME("layer_1"), texture_layers[1].is_valid() ? texture_layers[1] : Ref<Texture2D>(white_texture));
    blend_material->set_shader_parameter(SNAME("layer_2"), texture_layers[2].is_valid() ? texture_layers[2] : Ref<Texture2D>(white_texture));
    blend_material->set_shader_parameter(SNAME("layer_3"), texture_layers[3].is_valid() ? texture_layers[3] : Ref<Texture2D>(white_texture));
}

Ref<Material> HeightmapTerrain3D::_get_active_material() const {
    if (terrain_material.is_valid()) {
        return terrain_material;
    }
    if (blend_material.is_valid()) {
        return blend_material;
    }
    return default_material;
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

    Ref<Material> material = _get_active_material();
    if (material.is_valid()) {
        result->surface_set_material(0, material);
    }
    return result;
}

void HeightmapTerrain3D::_rebuild_mesh() {
    // This is a small terrain prototype: updates replace one mesh surface.
    // Chunking/LOD will be handled separately for large worlds.
    set_mesh(build_mesh());
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
    _heightmap_changed();
}

Ref<TerrainHeightmap> HeightmapTerrain3D::get_heightmap() const {
    return heightmap;
}

void HeightmapTerrain3D::set_splatmap(const Ref<TerrainSplatmap> &p_splatmap) {
    if (splatmap == p_splatmap) {
        return;
    }
    if (splatmap.is_valid()) {
        splatmap->disconnect_changed(callable_mp(this, &HeightmapTerrain3D::_splatmap_changed));
    }
    splatmap = p_splatmap;
    if (splatmap.is_valid()) {
        if (heightmap.is_valid()) {
            splatmap->set_dimensions(heightmap->get_width(), heightmap->get_depth());
        }
        splatmap->connect_changed(callable_mp(this, &HeightmapTerrain3D::_splatmap_changed));
    }
    _refresh_splat_texture();
    _refresh_layer_material();
    _rebuild_mesh();
}

Ref<TerrainSplatmap> HeightmapTerrain3D::get_splatmap() const {
    return splatmap;
}

void HeightmapTerrain3D::set_texture_layer(int p_layer, const Ref<Texture2D> &p_texture) {
    ERR_FAIL_INDEX(p_layer, 4);
    if (texture_layers[p_layer] == p_texture) {
        return;
    }
    texture_layers[p_layer] = p_texture;
    _refresh_layer_material();
    _rebuild_mesh();
}

Ref<Texture2D> HeightmapTerrain3D::get_texture_layer(int p_layer) const {
    ERR_FAIL_INDEX_V(p_layer, 4, Ref<Texture2D>());
    return texture_layers[p_layer];
}

void HeightmapTerrain3D::set_layer_0(const Ref<Texture2D> &p_texture) { set_texture_layer(0, p_texture); }
Ref<Texture2D> HeightmapTerrain3D::get_layer_0() const { return get_texture_layer(0); }
void HeightmapTerrain3D::set_layer_1(const Ref<Texture2D> &p_texture) { set_texture_layer(1, p_texture); }
Ref<Texture2D> HeightmapTerrain3D::get_layer_1() const { return get_texture_layer(1); }
void HeightmapTerrain3D::set_layer_2(const Ref<Texture2D> &p_texture) { set_texture_layer(2, p_texture); }
Ref<Texture2D> HeightmapTerrain3D::get_layer_2() const { return get_texture_layer(2); }
void HeightmapTerrain3D::set_layer_3(const Ref<Texture2D> &p_texture) { set_texture_layer(3, p_texture); }
Ref<Texture2D> HeightmapTerrain3D::get_layer_3() const { return get_texture_layer(3); }

void HeightmapTerrain3D::set_texture_tiling(real_t p_tiling) {
    ERR_FAIL_COND_MSG(!Math::is_finite(p_tiling) || p_tiling <= 0 || p_tiling > 256, "Texture tiling must be in the range (0, 256].");
    if (texture_tiling == p_tiling) {
        return;
    }
    texture_tiling = p_tiling;
    if (blend_material.is_valid()) {
        blend_material->set_shader_parameter(SNAME("texture_tiling"), texture_tiling);
    }
}

real_t HeightmapTerrain3D::get_texture_tiling() const {
    return texture_tiling;
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

void HeightmapTerrain3D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_heightmap", "heightmap"), &HeightmapTerrain3D::set_heightmap);
    ClassDB::bind_method(D_METHOD("get_heightmap"), &HeightmapTerrain3D::get_heightmap);
    ClassDB::bind_method(D_METHOD("set_splatmap", "splatmap"), &HeightmapTerrain3D::set_splatmap);
    ClassDB::bind_method(D_METHOD("get_splatmap"), &HeightmapTerrain3D::get_splatmap);
    ClassDB::bind_method(D_METHOD("set_texture_layer", "layer", "texture"), &HeightmapTerrain3D::set_texture_layer);
    ClassDB::bind_method(D_METHOD("get_texture_layer", "layer"), &HeightmapTerrain3D::get_texture_layer);
    ClassDB::bind_method(D_METHOD("set_layer_0", "texture"), &HeightmapTerrain3D::set_layer_0);
    ClassDB::bind_method(D_METHOD("get_layer_0"), &HeightmapTerrain3D::get_layer_0);
    ClassDB::bind_method(D_METHOD("set_layer_1", "texture"), &HeightmapTerrain3D::set_layer_1);
    ClassDB::bind_method(D_METHOD("get_layer_1"), &HeightmapTerrain3D::get_layer_1);
    ClassDB::bind_method(D_METHOD("set_layer_2", "texture"), &HeightmapTerrain3D::set_layer_2);
    ClassDB::bind_method(D_METHOD("get_layer_2"), &HeightmapTerrain3D::get_layer_2);
    ClassDB::bind_method(D_METHOD("set_layer_3", "texture"), &HeightmapTerrain3D::set_layer_3);
    ClassDB::bind_method(D_METHOD("get_layer_3"), &HeightmapTerrain3D::get_layer_3);
    ClassDB::bind_method(D_METHOD("set_texture_tiling", "tiling"), &HeightmapTerrain3D::set_texture_tiling);
    ClassDB::bind_method(D_METHOD("get_texture_tiling"), &HeightmapTerrain3D::get_texture_tiling);
    ClassDB::bind_method(D_METHOD("set_cell_size", "cell_size"), &HeightmapTerrain3D::set_cell_size);
    ClassDB::bind_method(D_METHOD("get_cell_size"), &HeightmapTerrain3D::get_cell_size);
    ClassDB::bind_method(D_METHOD("set_terrain_material", "material"), &HeightmapTerrain3D::set_terrain_material);
    ClassDB::bind_method(D_METHOD("get_terrain_material"), &HeightmapTerrain3D::get_terrain_material);
    ClassDB::bind_method(D_METHOD("sample_height_local", "x", "z"), &HeightmapTerrain3D::sample_height_local);
    ClassDB::bind_method(D_METHOD("build_mesh"), &HeightmapTerrain3D::build_mesh);

    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "heightmap", PROPERTY_HINT_RESOURCE_TYPE, "TerrainHeightmap",
                         PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT), "set_heightmap", "get_heightmap");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "splatmap", PROPERTY_HINT_RESOURCE_TYPE, "TerrainSplatmap",
                         PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT), "set_splatmap", "get_splatmap");
    ADD_GROUP("Terrain Textures", "layer_");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "layer_0", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_layer_0", "get_layer_0");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "layer_1", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_layer_1", "get_layer_1");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "layer_2", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_layer_2", "get_layer_2");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "layer_3", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_layer_3", "get_layer_3");
    ADD_GROUP("", "");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "texture_tiling", PROPERTY_HINT_RANGE, "0.01,256,0.01"), "set_texture_tiling", "get_texture_tiling");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "0.01,100,0.01,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain_material", PROPERTY_HINT_RESOURCE_TYPE, "BaseMaterial3D,ShaderMaterial"), "set_terrain_material", "get_terrain_material");
}

HeightmapTerrain3D::HeightmapTerrain3D() {
    Ref<StandardMaterial3D> material;
    material.instantiate();
    material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
    default_material = material;

    Ref<TerrainHeightmap> initial_heightmap;
    initial_heightmap.instantiate();
    set_heightmap(initial_heightmap);

    Ref<TerrainSplatmap> initial_splatmap;
    initial_splatmap.instantiate();
    set_splatmap(initial_splatmap);
}

HeightmapTerrain3D::~HeightmapTerrain3D() {
    if (heightmap.is_valid()) {
        heightmap->disconnect_changed(callable_mp(this, &HeightmapTerrain3D::_heightmap_changed));
    }
    if (splatmap.is_valid()) {
        splatmap->disconnect_changed(callable_mp(this, &HeightmapTerrain3D::_splatmap_changed));
    }
}
