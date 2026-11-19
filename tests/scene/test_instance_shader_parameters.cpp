/**************************************************************************/
/*  test_instance_shader_parameters.cpp                                   */
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
/* whom the Software is furnished to do so, subject to the following      */
/* conditions:                                                            */
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

TEST_FORCE_LINK(test_instance_shader_parameters)

#include "scene/2d/sprite_2d.h"
#include "scene/resources/image_texture.h"
#include "scene/resources/packed_scene.h"
#include "scene/resources/texture.h"

#ifndef _3D_DISABLED
#include "scene/3d/mesh_instance_3d.h"
#endif

namespace TestInstanceShaderParameters {

static bool has_storage_only_parameter(const Object *p_object, const String &p_name) {
	List<PropertyInfo> list;
	p_object->get_property_list(&list);
	for (const PropertyInfo &pi : list) {
		if (pi.name == p_name) {
			return (pi.usage & PROPERTY_USAGE_STORAGE) != 0 && (pi.usage & PROPERTY_USAGE_EDITOR) == 0;
		}
	}
	return false;
}

static bool has_parameter(const Object *p_object, const String &p_name) {
	List<PropertyInfo> list;
	p_object->get_property_list(&list);
	for (const PropertyInfo &pi : list) {
		if (pi.name == p_name) {
			return true;
		}
	}
	return false;
}

TEST_CASE("[InstanceShaderParameters] 2D unresolved color override remains serializable") {
	Sprite2D *sprite = memnew(Sprite2D);
	const Color expected(0.1, 0.2, 0.3, 0.4);
	sprite->set_instance_shader_parameter("orphan_color", expected);
	CHECK(has_storage_only_parameter(sprite, "instance_shader_parameters/orphan_color"));
	CHECK(sprite->get("instance_shader_parameters/orphan_color") == Variant(expected));

	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(sprite) == OK);

	Node *node = packed->instantiate();
	REQUIRE(node != nullptr);
	Sprite2D *roundtrip = Object::cast_to<Sprite2D>(node);
	REQUIRE(roundtrip != nullptr);
	CHECK(has_storage_only_parameter(roundtrip, "instance_shader_parameters/orphan_color"));
	CHECK(roundtrip->get("instance_shader_parameters/orphan_color") == Variant(expected));

	memdelete(node);
	memdelete(sprite);
}

TEST_CASE("[InstanceShaderParameters] 2D unresolved scalar survives a scene pack") {
	Sprite2D *sprite = memnew(Sprite2D);
	sprite->set_instance_shader_parameter("orphan_scalar", 0.75f);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(sprite) == OK);
	Node *node = packed->instantiate();
	REQUIRE(node != nullptr);
	CHECK(node->get("instance_shader_parameters/orphan_scalar") == Variant(0.75f));
	memdelete(node);
	memdelete(sprite);
}

TEST_CASE("[InstanceShaderParameters] 2D unresolved resource is a resource, not RID") {
	Sprite2D *sprite = memnew(Sprite2D);
	Ref<ImageTexture> texture;
	texture.instantiate();
	sprite->set_instance_shader_parameter("orphan_texture", texture);
	CHECK(has_storage_only_parameter(sprite, "instance_shader_parameters/orphan_texture"));
	Variant stored = sprite->get("instance_shader_parameters/orphan_texture");
	CHECK(stored.get_type() == Variant::OBJECT);
	CHECK(stored == Variant(texture));
	memdelete(sprite);
}

TEST_CASE("[InstanceShaderParameters] 2D removing override removes storage property") {
	Sprite2D *sprite = memnew(Sprite2D);
	sprite->set_instance_shader_parameter("temporary", Color(1, 0, 0));
	CHECK(has_storage_only_parameter(sprite, "instance_shader_parameters/temporary"));
	sprite->set_instance_shader_parameter("temporary", Variant());
	CHECK_FALSE(has_parameter(sprite, "instance_shader_parameters/temporary"));
	memdelete(sprite);
}

TEST_CASE("[InstanceShaderParameters] 2D multiple unresolved overrides remain independently stored") {
	Sprite2D *sprite = memnew(Sprite2D);
	sprite->set_instance_shader_parameter("first", 17);
	sprite->set_instance_shader_parameter("second", Color(0, 1, 0));
	CHECK(has_storage_only_parameter(sprite, "instance_shader_parameters/first"));
	CHECK(has_storage_only_parameter(sprite, "instance_shader_parameters/second"));
	CHECK(sprite->get("instance_shader_parameters/first") == Variant(17));
	CHECK(sprite->get("instance_shader_parameters/second") == Variant(Color(0, 1, 0)));
	memdelete(sprite);
}

#ifndef _3D_DISABLED
TEST_CASE("[InstanceShaderParameters] 3D unresolved color override remains serializable") {
	MeshInstance3D *mesh = memnew(MeshInstance3D);
	const Color expected(0.6, 0.4, 0.2, 1.0);
	mesh->set_instance_shader_parameter("orphan_color", expected);
	CHECK(has_storage_only_parameter(mesh, "instance_shader_parameters/orphan_color"));
	CHECK(mesh->get("instance_shader_parameters/orphan_color") == Variant(expected));

	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(mesh) == OK);

	Node *node = packed->instantiate();
	REQUIRE(node != nullptr);
	MeshInstance3D *roundtrip = Object::cast_to<MeshInstance3D>(node);
	REQUIRE(roundtrip != nullptr);
	CHECK(has_storage_only_parameter(roundtrip, "instance_shader_parameters/orphan_color"));
	CHECK(roundtrip->get("instance_shader_parameters/orphan_color") == Variant(expected));

	memdelete(node);
	memdelete(mesh);
}

TEST_CASE("[InstanceShaderParameters] 3D unresolved scalar survives a scene pack") {
	MeshInstance3D *mesh = memnew(MeshInstance3D);
	mesh->set_instance_shader_parameter("orphan_scalar", 0.75f);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(mesh) == OK);
	Node *node = packed->instantiate();
	REQUIRE(node != nullptr);
	CHECK(node->get("instance_shader_parameters/orphan_scalar") == Variant(0.75f));
	memdelete(node);
	memdelete(mesh);
}

TEST_CASE("[InstanceShaderParameters] 3D unresolved resource is a resource, not RID") {
	MeshInstance3D *mesh = memnew(MeshInstance3D);
	Ref<ImageTexture> texture;
	texture.instantiate();
	mesh->set_instance_shader_parameter("orphan_texture", texture);
	CHECK(has_storage_only_parameter(mesh, "instance_shader_parameters/orphan_texture"));
	Variant stored = mesh->get("instance_shader_parameters/orphan_texture");
	CHECK(stored.get_type() == Variant::OBJECT);
	CHECK(stored == Variant(texture));
	memdelete(mesh);
}

TEST_CASE("[InstanceShaderParameters] 3D removing override removes storage property") {
	MeshInstance3D *mesh = memnew(MeshInstance3D);
	mesh->set_instance_shader_parameter("temporary", Color(1, 0, 0));
	CHECK(has_storage_only_parameter(mesh, "instance_shader_parameters/temporary"));
	mesh->set_instance_shader_parameter("temporary", Variant());
	CHECK_FALSE(has_parameter(mesh, "instance_shader_parameters/temporary"));
	memdelete(mesh);
}

TEST_CASE("[InstanceShaderParameters] 3D multiple unresolved overrides remain independently stored") {
	MeshInstance3D *mesh = memnew(MeshInstance3D);
	mesh->set_instance_shader_parameter("first", 17);
	mesh->set_instance_shader_parameter("second", Color(0, 1, 0));
	CHECK(has_storage_only_parameter(mesh, "instance_shader_parameters/first"));
	CHECK(has_storage_only_parameter(mesh, "instance_shader_parameters/second"));
	CHECK(mesh->get("instance_shader_parameters/first") == Variant(17));
	CHECK(mesh->get("instance_shader_parameters/second") == Variant(Color(0, 1, 0)));
	memdelete(mesh);
}
#endif

} // namespace TestInstanceShaderParameters
