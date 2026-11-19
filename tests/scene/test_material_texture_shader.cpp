/**************************************************************************/
/*  test_material_texture_shader.cpp                                       */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_material_texture_shader)

#ifndef _3D_DISABLED

#include "core/io/image.h"
#include "scene/resources/image_texture.h"
#include "scene/resources/material.h"
#include "servers/rendering/rendering_server.h"

namespace TestMaterialTextureShader {

// [SceneTree] initializes the mock renderer, whose shader compiler validates
// the dynamically emitted shader and exposes its declared uniforms.
static bool has_sampler(BaseMaterial3D *p_material, const StringName &p_sampler) {
	const RID shader = p_material->get_shader_rid();
	if (!shader.is_valid()) {
		return false;
	}
	List<PropertyInfo> properties;
	RenderingServer::get_singleton()->get_shader_parameter_list(shader, &properties);
	for (const PropertyInfo &property : properties) {
		if (property.name == p_sampler) {
			return true;
		}
	}
	return false;
}

static Ref<ImageTexture> make_test_texture() {
	Ref<Image> image = memnew(Image(2, 2, false, Image::FORMAT_RGBA8));
	return ImageTexture::create_from_image(image);
}

TEST_CASE("[SceneTree][Material3D] Unused metallic and roughness samplers are not generated") {
	Ref<StandardMaterial3D> material;
	material.instantiate();

	CHECK_FALSE(has_sampler(material.ptr(), "texture_metallic"));
	CHECK_FALSE(has_sampler(material.ptr(), "texture_roughness"));

	Ref<ImageTexture> texture = make_test_texture();
	REQUIRE(texture.is_valid());

	material->set_texture(BaseMaterial3D::TEXTURE_METALLIC, texture);
	CHECK(has_sampler(material.ptr(), "texture_metallic"));
	CHECK_FALSE(has_sampler(material.ptr(), "texture_roughness"));

	material->set_texture(BaseMaterial3D::TEXTURE_ROUGHNESS, texture);
	CHECK(has_sampler(material.ptr(), "texture_metallic"));
	CHECK(has_sampler(material.ptr(), "texture_roughness"));

	material->set_texture(BaseMaterial3D::TEXTURE_METALLIC, Ref<Texture2D>());
	CHECK_FALSE(has_sampler(material.ptr(), "texture_metallic"));
	CHECK(has_sampler(material.ptr(), "texture_roughness"));
}

TEST_CASE("[SceneTree][Material3D] Enabled features use optional samplers only when present") {
	Ref<StandardMaterial3D> material;
	material.instantiate();
	Ref<ImageTexture> texture = make_test_texture();
	REQUIRE(texture.is_valid());

	material->set_feature(BaseMaterial3D::FEATURE_EMISSION, true);
	material->set_feature(BaseMaterial3D::FEATURE_HEIGHT_MAPPING, true);
	material->set_feature(BaseMaterial3D::FEATURE_SUBSURFACE_TRANSMITTANCE, true);
	material->set_feature(BaseMaterial3D::FEATURE_DETAIL, true);

	// Compiling this variant also ensures no undeclared heightmap or %s
	// subsurface uniform is emitted when the texture is absent.
	CHECK_FALSE(has_sampler(material.ptr(), "texture_emission"));
	CHECK_FALSE(has_sampler(material.ptr(), "texture_heightmap"));
	CHECK_FALSE(has_sampler(material.ptr(), "texture_subsurface_transmittance"));
	CHECK_FALSE(has_sampler(material.ptr(), "texture_detail_albedo"));

	material->set_texture(BaseMaterial3D::TEXTURE_EMISSION, texture);
	material->set_texture(BaseMaterial3D::TEXTURE_HEIGHTMAP, texture);
	material->set_texture(BaseMaterial3D::TEXTURE_SUBSURFACE_TRANSMITTANCE, texture);
	material->set_texture(BaseMaterial3D::TEXTURE_DETAIL_ALBEDO, texture);
	CHECK(has_sampler(material.ptr(), "texture_emission"));
	CHECK(has_sampler(material.ptr(), "texture_heightmap"));
	CHECK(has_sampler(material.ptr(), "texture_subsurface_transmittance"));
	CHECK(has_sampler(material.ptr(), "texture_detail_albedo"));

	material->set_feature(BaseMaterial3D::FEATURE_EMISSION, false);
	CHECK_FALSE(has_sampler(material.ptr(), "texture_emission"));
}

TEST_CASE("[SceneTree][Material3D] ORM shader includes sampler only for an assigned ORM texture") {
	Ref<ORMMaterial3D> material;
	material.instantiate();
	CHECK_FALSE(has_sampler(material.ptr(), "texture_orm"));
	CHECK_FALSE(has_sampler(material.ptr(), "texture_metallic"));
	CHECK_FALSE(has_sampler(material.ptr(), "texture_roughness"));

	Ref<ImageTexture> texture = make_test_texture();
	REQUIRE(texture.is_valid());
	material->set_texture(BaseMaterial3D::TEXTURE_ORM, texture);
	CHECK(has_sampler(material.ptr(), "texture_orm"));

	material->set_texture(BaseMaterial3D::TEXTURE_ORM, Ref<Texture2D>());
	CHECK_FALSE(has_sampler(material.ptr(), "texture_orm"));
}

TEST_CASE("[SceneTree][Material3D] Each optional feature sampler tracks its texture") {
	struct TextureCase {
		BaseMaterial3D::Feature feature;
		BaseMaterial3D::TextureParam param;
		const char *uniform_name;
	};
	const TextureCase cases[] = {
		{ BaseMaterial3D::FEATURE_NORMAL_MAPPING, BaseMaterial3D::TEXTURE_NORMAL, "texture_normal" },
		{ BaseMaterial3D::FEATURE_BENT_NORMAL_MAPPING, BaseMaterial3D::TEXTURE_BENT_NORMAL, "texture_bent_normal" },
		{ BaseMaterial3D::FEATURE_RIM, BaseMaterial3D::TEXTURE_RIM, "texture_rim" },
		{ BaseMaterial3D::FEATURE_CLEARCOAT, BaseMaterial3D::TEXTURE_CLEARCOAT, "texture_clearcoat" },
		{ BaseMaterial3D::FEATURE_ANISOTROPY, BaseMaterial3D::TEXTURE_FLOWMAP, "texture_flowmap" },
		{ BaseMaterial3D::FEATURE_AMBIENT_OCCLUSION, BaseMaterial3D::TEXTURE_AMBIENT_OCCLUSION, "texture_ambient_occlusion" },
		{ BaseMaterial3D::FEATURE_SUBSURFACE_SCATTERING, BaseMaterial3D::TEXTURE_SUBSURFACE_SCATTERING, "texture_subsurface_scattering" },
		{ BaseMaterial3D::FEATURE_SUBSURFACE_TRANSMITTANCE, BaseMaterial3D::TEXTURE_SUBSURFACE_TRANSMITTANCE, "texture_subsurface_transmittance" },
		{ BaseMaterial3D::FEATURE_BACKLIGHT, BaseMaterial3D::TEXTURE_BACKLIGHT, "texture_backlight" },
		{ BaseMaterial3D::FEATURE_REFRACTION, BaseMaterial3D::TEXTURE_REFRACTION, "texture_refraction" },
		{ BaseMaterial3D::FEATURE_DETAIL, BaseMaterial3D::TEXTURE_DETAIL_MASK, "texture_detail_mask" },
		{ BaseMaterial3D::FEATURE_DETAIL, BaseMaterial3D::TEXTURE_DETAIL_NORMAL, "texture_detail_normal" },
	};

	Ref<ImageTexture> texture = make_test_texture();
	REQUIRE(texture.is_valid());
	for (const TextureCase &test_case : cases) {
		Ref<StandardMaterial3D> material;
		material.instantiate();
		const StringName sampler_name(test_case.uniform_name);
		material->set_texture(test_case.param, texture);
		// Feature disabled: assigned but unused texture must not affect shader.
		CHECK_FALSE(has_sampler(material.ptr(), sampler_name));
		material->set_feature(test_case.feature, true);
		CHECK(has_sampler(material.ptr(), sampler_name));
		material->set_texture(test_case.param, Ref<Texture2D>());
		CHECK_FALSE(has_sampler(material.ptr(), sampler_name));
	}
}

} // namespace TestMaterialTextureShader

#endif // _3D_DISABLED
