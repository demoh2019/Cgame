/**************************************************************************/
/*  test_gltf_document.cpp                                                */
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

TEST_FORCE_LINK(test_gltf_document)

#ifndef _3D_DISABLED

#include "modules/modules_enabled.gen.h" // For gltf.

#ifdef MODULE_GLTF_ENABLED

#include "tests/test_utils.h"

#include "core/io/json.h"
#include "modules/gltf/structures/gltf_buffer_view.h"
#ifndef PHYSICS_3D_DISABLED
#include "modules/gltf/extensions/physics/gltf_physics_shape.h"
#endif // PHYSICS_3D_DISABLED


#include "modules/gltf/extensions/gltf_document_extension_convert_importer_mesh.h"
#include "modules/gltf/gltf_document.h"
#include "modules/gltf/extensions/gltf_light.h"
#include "modules/gltf/structures/gltf_accessor.h"
#include "scene/3d/light_3d.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/resources/mesh.h"

namespace TestGLTFDocument {

struct GLTFArraySize {
	String key;
	int val;
};

struct GLTFKeyValue {
	String key;
	Variant val;
};

struct GLTFTestCase {
	String filename;
	String copyright;
	String generator;
	String version;
	Vector<GLTFArraySize> array_sizes;
	Vector<GLTFArraySize> json_array_sizes;
	Vector<GLTFKeyValue> keyvalues;
};

const GLTFTestCase glTF_test_cases[] = {
	{ "models/cube.gltf",
			"",
			"Khronos glTF Blender I/O v4.3.47",
			"2.0",
			// Here are the array sizes.
			{
					{ "nodes", 1 },
					{ "buffers", 1 },
					{ "buffer_views", 13 },
					{ "accessors", 13 },
					{ "meshes", 1 },
					{ "materials", 2 },
					{ "root_nodes", 1 },
					{ "textures", 0 },
					{ "texture_samplers", 0 },
					{ "images", 0 },
					{ "skins", 0 },
					{ "cameras", 0 },
					{ "lights", 0 },
					{ "skeletons", 0 },
					{ "animations", 1 },
			},
			// Here are the json array sizes.
			{
					{ "scenes", 1 },
					{ "nodes", 1 },
					{ "animations", 1 },
					{ "meshes", 1 },
					{ "accessors", 13 },
					{ "bufferViews", 13 },
					{ "buffers", 1 },
			},
			// Here are the key-value pairs.
			{
					{ "major_version", 2 },
					{ "minor_version", 0 },
					{ "scene_name", "cube" },
					{ "filename", "cube" } } },
	{ "models/suzanne.glb",
			"this is example text",
			"Khronos glTF Blender I/O v4.3.47",
			"2.0",
			// Here are the array sizes.
			{
					{ "glb_data", 68908 },
					{ "nodes", 2 },
					{ "buffers", 1 },
					{ "buffer_views", 5 },
					{ "accessors", 4 },
					{ "meshes", 1 },
					{ "materials", 1 },
					{ "root_nodes", 2 },
					{ "textures", 1 },
					{ "texture_samplers", 1 },
					{ "images", 1 },
					{ "skins", 0 },
					{ "cameras", 1 },
					{ "lights", 0 },
					{ "unique_names", 4 },
					{ "skeletons", 0 },
					{ "animations", 0 },
			},
			// Here are the json array sizes.
			{
					{ "scenes", 1 },
					{ "nodes", 2 },
					{ "cameras", 1 },
					{ "materials", 1 },
					{ "meshes", 1 },
					{ "textures", 1 },
					{ "images", 1 },
					{ "accessors", 4 },
					{ "bufferViews", 5 },
					{ "buffers", 1 },
			},
			// Here are the key-value pairs.
			{
					{ "major_version", 2 },
					{ "minor_version", 0 },
					{ "scene_name", "suzanne" },
					{ "filename", "suzanne" } } },
};

void register_gltf_extension() {
	GLTFDocument::unregister_all_gltf_document_extensions();

	// Ensures meshes become a MeshInstance3D and not an ImporterMeshInstance3D.
	Ref<GLTFDocumentExtensionConvertImporterMesh> extension_GLTFDocumentExtensionConvertImporterMesh;
	extension_GLTFDocumentExtensionConvertImporterMesh.instantiate();
	GLTFDocument::register_gltf_document_extension(extension_GLTFDocumentExtensionConvertImporterMesh);
}

void test_gltf_document_values(Ref<GLTFDocument> &p_gltf_document, Ref<GLTFState> &p_gltf_state, const GLTFTestCase &p_test_case) {
	const Error err = p_gltf_document->append_from_file(TestUtils::get_data_path(p_test_case.filename), p_gltf_state);
	REQUIRE(err == OK);

	for (GLTFArraySize array_size : p_test_case.array_sizes) {
		CHECK_MESSAGE(((Array)(p_gltf_state->getvar(array_size.key))).size() == array_size.val, "Expected \"", array_size.key, "\" to have ", array_size.val, " elements.");
	}

	for (GLTFArraySize array_size : p_test_case.json_array_sizes) {
		CHECK(p_gltf_state->get_json().has(array_size.key));
		CHECK_MESSAGE(((Array)(p_gltf_state->get_json()[array_size.key])).size() == array_size.val, "Expected \"", array_size.key, "\" to have ", array_size.val, " elements.");
	}

	for (GLTFKeyValue key_value : p_test_case.keyvalues) {
		CHECK_MESSAGE(p_gltf_state->getvar(key_value.key) == key_value.val, "Expected \"", key_value.key, "\" to be \"", key_value.val, "\".");
	}

	CHECK(p_gltf_state->get_copyright() == p_test_case.copyright);
	CHECK(((Dictionary)p_gltf_state->get_json()["asset"])["generator"] == p_test_case.generator);
	CHECK(((Dictionary)p_gltf_state->get_json()["asset"])["version"] == p_test_case.version);
}

void test_gltf_save(Node *p_node) {
	Ref<GLTFDocument> gltf_document_save;
	gltf_document_save.instantiate();
	Ref<GLTFState> gltf_state_save;
	gltf_state_save.instantiate();

	gltf_document_save->append_from_scene(p_node, gltf_state_save);

	// Check saving the scene to gltf and glb.
	const Error err_save_gltf = gltf_document_save->write_to_filesystem(gltf_state_save, TestUtils::get_temp_path("cube.gltf"));
	const Error err_save_glb = gltf_document_save->write_to_filesystem(gltf_state_save, TestUtils::get_temp_path("cube.glb"));
	CHECK(err_save_gltf == OK);
	CHECK(err_save_glb == OK);
}

TEST_CASE("[SceneTree][GLTFDocument] Load cube.gltf") {
	register_gltf_extension();

	Ref<GLTFDocument> gltf_document;
	gltf_document.instantiate();
	Ref<GLTFState> gltf_state;
	gltf_state.instantiate();

	test_gltf_document_values(gltf_document, gltf_state, glTF_test_cases[0]);

	Node *node = gltf_document->generate_scene(gltf_state);

	// Check the loaded scene.
	CHECK(node->is_class("Node3D"));
	CHECK(node->get_name() == "cube");

	CHECK(node->get_child(0)->is_class("MeshInstance3D"));
	CHECK(node->get_child(0)->get_name() == "Cube");

	CHECK(node->get_child(1)->is_class("AnimationPlayer"));
	CHECK(node->get_child(1)->get_name() == "AnimationPlayer");

	test_gltf_save(node);

	// Clean up the node.
	memdelete(node);
}

TEST_CASE("[SceneTree][GLTFDocument] Load suzanne.glb") {
	register_gltf_extension();

	Ref<GLTFDocument> gltf_document;
	gltf_document.instantiate();
	Ref<GLTFState> gltf_state;
	gltf_state.instantiate();

	test_gltf_document_values(gltf_document, gltf_state, glTF_test_cases[1]);

	Node *node = gltf_document->generate_scene(gltf_state);

	// Check the loaded scene.
	CHECK(node->is_class("Node3D"));
	CHECK(node->get_name() == "suzanne");

	CHECK(node->get_child(0)->is_class("MeshInstance3D"));
	CHECK(node->get_child(0)->get_name() == "Suzanne");

	CHECK(node->get_child(1)->is_class("Camera3D"));
	CHECK(node->get_child(1)->get_name() == "Camera");

	test_gltf_save(node);

	// Clean up the node.
	memdelete(node);
}




static Dictionary make_minimal_gltf_json() {
	Dictionary asset;
	asset["version"] = "2.0";
	Dictionary scene;
	scene["nodes"] = Array();
	Array scenes;
	scenes.push_back(scene);
	Dictionary root;
	root["asset"] = asset;
	root["scene"] = 0;
	root["scenes"] = scenes;
	root["nodes"] = Array();
	return root;
}

static Error parse_gltf_json(const Dictionary &p_json) {
	Ref<GLTFDocument> document;
	document.instantiate();
	Ref<GLTFState> state;
	state.instantiate();
	return document->append_from_buffer(JSON::stringify(p_json).to_utf8_buffer(), "res://gltf_parse_regression.gltf", state);
}

TEST_CASE("[GLTFDocument] Accessor rejects missing required fields") {
	Dictionary accessor;
	accessor["componentType"] = 5126;
	accessor["count"] = 1;
	accessor["type"] = "SCALAR";
	CHECK(GLTFAccessor::from_dictionary(accessor).is_valid());

	const String required_fields[] = { "componentType", "count", "type" };
	ERR_PRINT_OFF
	for (const String &field : required_fields) {
		Dictionary invalid = accessor.duplicate();
		invalid.erase(field);
		CHECK_MESSAGE(GLTFAccessor::from_dictionary(invalid).is_null(), (String("Missing accessor field: ") + field).utf8().get_data());
	}
	ERR_PRINT_ON
}

TEST_CASE("[GLTFDocument] Accessor requires a positive element count") {
	Dictionary accessor;
	accessor["componentType"] = 5126;
	accessor["type"] = "VEC3";
	const int64_t invalid_counts[] = { -10, -1, 0 };
	ERR_PRINT_OFF
	for (int64_t count : invalid_counts) {
		accessor["count"] = count;
		CHECK(GLTFAccessor::from_dictionary(accessor).is_null());
	}
	ERR_PRINT_ON
	const int64_t valid_counts[] = { 1, 2, 128 };
	for (int64_t count : valid_counts) {
		accessor["count"] = count;
		Ref<GLTFAccessor> parsed = GLTFAccessor::from_dictionary(accessor);
		REQUIRE(parsed.is_valid());
		CHECK(parsed->get_count() == count);
	}
}

TEST_CASE("[GLTFDocument] Incomplete sparse accessors fail rather than return partial objects") {
	Dictionary indices;
	indices["bufferView"] = 0;
	indices["componentType"] = 5123;
	Dictionary values;
	values["bufferView"] = 1;
	Dictionary sparse;
	sparse["count"] = 1;
	sparse["indices"] = indices;
	sparse["values"] = values;
	Dictionary accessor;
	accessor["componentType"] = 5126;
	accessor["count"] = 3;
	accessor["type"] = "SCALAR";
	accessor["sparse"] = sparse;
	CHECK(GLTFAccessor::from_dictionary(accessor).is_valid());

	ERR_PRINT_OFF
	for (const String &field : { String("count"), String("indices"), String("values") }) {
		Dictionary invalid_sparse = sparse.duplicate(true);
		invalid_sparse.erase(field);
		Dictionary invalid_accessor = accessor.duplicate();
		invalid_accessor["sparse"] = invalid_sparse;
		CHECK(GLTFAccessor::from_dictionary(invalid_accessor).is_null());
	}
	for (const String &field : { String("bufferView"), String("componentType") }) {
		Dictionary invalid_indices = indices.duplicate();
		invalid_indices.erase(field);
		Dictionary invalid_sparse = sparse.duplicate();
		invalid_sparse["indices"] = invalid_indices;
		Dictionary invalid_accessor = accessor.duplicate();
		invalid_accessor["sparse"] = invalid_sparse;
		CHECK(GLTFAccessor::from_dictionary(invalid_accessor).is_null());
	}
	Dictionary invalid_values = values.duplicate();
	invalid_values.erase("bufferView");
	Dictionary invalid_sparse = sparse.duplicate();
	invalid_sparse["values"] = invalid_values;
	Dictionary invalid_accessor = accessor.duplicate();
	invalid_accessor["sparse"] = invalid_sparse;
	CHECK(GLTFAccessor::from_dictionary(invalid_accessor).is_null());
	ERR_PRINT_ON
}

TEST_CASE("[GLTFDocument] BufferView requires buffer and byteLength") {
	Dictionary view;
	view["buffer"] = 0;
	view["byteLength"] = 16;
	CHECK(GLTFBufferView::from_dictionary(view).is_valid());
	ERR_PRINT_OFF
	for (const String &field : { String("buffer"), String("byteLength") }) {
		Dictionary invalid = view.duplicate();
		invalid.erase(field);
		CHECK(GLTFBufferView::from_dictionary(invalid).is_null());
	}
	ERR_PRINT_ON
}

TEST_CASE("[GLTFDocument] BufferView rejects out-of-range and misaligned strides") {
	Dictionary view;
	view["buffer"] = 0;
	view["byteLength"] = 512;
	CHECK(GLTFBufferView::from_dictionary(view).is_valid());
	const int64_t invalid_strides[] = { -4, 0, 1, 3, 5, 250, 253, 256 };
	ERR_PRINT_OFF
	for (int64_t stride : invalid_strides) {
		view["byteStride"] = stride;
		CHECK(GLTFBufferView::from_dictionary(view).is_null());
	}
	ERR_PRINT_ON
	const int64_t valid_strides[] = { 4, 8, 16, 252 };
	for (int64_t stride : valid_strides) {
		view["byteStride"] = stride;
		Ref<GLTFBufferView> parsed = GLTFBufferView::from_dictionary(view);
		REQUIRE(parsed.is_valid());
		CHECK(parsed->get_byte_stride() == stride);
	}
}

TEST_CASE("[GLTFDocument] Spot lights accept omitted optional cone fields") {
	Dictionary light;
	light["type"] = "spot";
	Ref<GLTFLight> default_spot = GLTFLight::from_dictionary(light);
	REQUIRE(default_spot.is_valid());
	CHECK(default_spot->get_inner_cone_angle() == 0.0f);
	CHECK(default_spot->get_outer_cone_angle() > 0.0f);

	Dictionary spot;
	spot["outerConeAngle"] = 0.6f;
	light["spot"] = spot;
	Ref<GLTFLight> only_outer = GLTFLight::from_dictionary(light);
	REQUIRE(only_outer.is_valid());
	CHECK(only_outer->get_inner_cone_angle() == 0.0f);
	CHECK(only_outer->get_outer_cone_angle() == 0.6f);

	spot.clear();
	spot["innerConeAngle"] = 0.2f;
	light["spot"] = spot;
	Ref<GLTFLight> only_inner = GLTFLight::from_dictionary(light);
	REQUIRE(only_inner.is_valid());
	CHECK(only_inner->get_inner_cone_angle() == 0.2f);
	CHECK(only_inner->get_outer_cone_angle() > only_inner->get_inner_cone_angle());

	spot["outerConeAngle"] = 0.6f;
	light["spot"] = spot;
	Ref<GLTFLight> explicit_cones = GLTFLight::from_dictionary(light);
	REQUIRE(explicit_cones.is_valid());
	CHECK(explicit_cones->get_inner_cone_angle() == 0.2f);
	CHECK(explicit_cones->get_outer_cone_angle() == 0.6f);
}

#ifndef PHYSICS_3D_DISABLED
TEST_CASE("[GLTFDocument] Physics mesh shape aliases preserve nested mesh indices") {
	const char *declared_types[] = { "hull", "convexMesh", "mesh", "convex", "trimesh" };
	const char *normalized_types[] = { "convex", "convex", "trimesh", "convex", "trimesh" };
	for (int i = 0; i < 5; i++) {
		Dictionary properties;
		properties["mesh"] = i + 1;
		Dictionary source;
		source["type"] = declared_types[i];
		source[declared_types[i]] = properties;
		Ref<GLTFPhysicsShape> parsed = GLTFPhysicsShape::from_dictionary(source);
		REQUIRE(parsed.is_valid());
		CHECK(parsed->get_shape_type() == normalized_types[i]);
		CHECK(parsed->get_mesh_index() == i + 1);
	}
	ERR_PRINT_OFF
	CHECK(GLTFPhysicsShape::from_dictionary(Dictionary()).is_null());
	ERR_PRINT_ON
}
#endif // PHYSICS_3D_DISABLED

TEST_CASE("[GLTFDocument] In-memory import rejects invalid accessor counts and sparse accessors") {
	Dictionary root = make_minimal_gltf_json();
	CHECK(parse_gltf_json(root) == OK);

	Dictionary accessor;
	accessor["componentType"] = 5126;
	accessor["count"] = 1;
	accessor["type"] = "SCALAR";
	Array accessors;
	accessors.push_back(accessor);
	root["accessors"] = accessors;
	CHECK(parse_gltf_json(root) == OK);

	ERR_PRINT_OFF
	for (int64_t count : { int64_t(0), int64_t(-1) }) {
		accessor["count"] = count;
		accessors[0] = accessor;
		root["accessors"] = accessors;
		CHECK(parse_gltf_json(root) == ERR_PARSE_ERROR);
	}
	accessor["count"] = 1;
	Dictionary sparse;
	sparse["count"] = 1;
	accessor["sparse"] = sparse;
	accessors[0] = accessor;
	root["accessors"] = accessors;
	CHECK(parse_gltf_json(root) == ERR_PARSE_ERROR);
	ERR_PRINT_ON
}

TEST_CASE("[GLTFDocument] In-memory import rejects invalid buffer view strides") {
	Dictionary root = make_minimal_gltf_json();
	Dictionary view;
	view["buffer"] = 0;
	view["byteLength"] = 32;
	Array views;
	views.push_back(view);
	root["bufferViews"] = views;

	ERR_PRINT_OFF
	for (int64_t stride : { int64_t(3), int64_t(5), int64_t(256) }) {
		view["byteStride"] = stride;
		views[0] = view;
		root["bufferViews"] = views;
		CHECK(parse_gltf_json(root) == ERR_PARSE_ERROR);
	}
	ERR_PRINT_ON
}


TEST_CASE("[GLTFDocument] In-memory import rejects camera dictionaries without a type") {
	Dictionary root = make_minimal_gltf_json();
	Array cameras;
	cameras.push_back(Dictionary());
	root["cameras"] = cameras;

	ERR_PRINT_OFF
	CHECK(parse_gltf_json(root) == ERR_PARSE_ERROR);
	ERR_PRINT_ON

	Dictionary perspective;
	perspective["yfov"] = 0.9f;
	perspective["znear"] = 0.1f;
	Dictionary camera;
	camera["type"] = "perspective";
	camera["perspective"] = perspective;
	cameras[0] = camera;
	root["cameras"] = cameras;
	CHECK(parse_gltf_json(root) == OK);
}

TEST_CASE("[GLTFDocument] In-memory import accepts a spotlight with no spot properties") {
	Dictionary root = make_minimal_gltf_json();
	Dictionary light;
	light["type"] = "spot";
	Array lights;
	lights.push_back(light);
	Dictionary punctual;
	punctual["lights"] = lights;
	Dictionary extensions;
	extensions["KHR_lights_punctual"] = punctual;
	root["extensions"] = extensions;
	Array used_extensions;
	used_extensions.push_back("KHR_lights_punctual");
	root["extensionsUsed"] = used_extensions;

	Ref<GLTFDocument> document;
	document.instantiate();
	Ref<GLTFState> state;
	state.instantiate();
	CHECK(document->append_from_buffer(JSON::stringify(root).to_utf8_buffer(), "res://valid_optional_spot.gltf", state) == OK);
	REQUIRE(state->get_lights().size() == 1);
	Ref<GLTFLight> parsed = state->get_lights()[0];
	REQUIRE(parsed.is_valid());
	CHECK(parsed->get_light_type() == "spot");
	CHECK(parsed->get_inner_cone_angle() == 0.0f);
	CHECK(parsed->get_outer_cone_angle() > 0.0f);
}

TEST_CASE("[SceneTree][GLTFDocument] Packed numeric glTF accessors preserve element values") {
	Ref<GLTFState> state;
	state.instantiate();
	Ref<GLTFAccessor> accessor;
	accessor.instantiate();
	accessor->set_accessor_type(GLTFAccessor::TYPE_VEC3);
	accessor->set_component_type(GLTFAccessor::COMPONENT_TYPE_SINGLE_FLOAT);

	PackedFloat64Array input;
	for (int i = 1; i <= 6; i++) {
		input.push_back(i);
	}
	const PackedByteArray encoded = accessor->encode_floats_as_bytes(input);
	REQUIRE(encoded.size() == 6 * sizeof(float));
	const GLTFAccessorIndex index = accessor->store_accessor_data_into_state(state, encoded);
	REQUIRE(index >= 0);

	for (Variant::Type type : { Variant::PACKED_BYTE_ARRAY, Variant::PACKED_INT32_ARRAY, Variant::PACKED_INT64_ARRAY,
				Variant::PACKED_FLOAT32_ARRAY, Variant::PACKED_FLOAT64_ARRAY }) {
		const Array rows = accessor->decode_as_variants(state, type);
		REQUIRE(rows.size() == 2);
		CHECK(rows[0].get_type() == type);
		CHECK(rows[1].get_type() == type);
		switch (type) {
			case Variant::PACKED_BYTE_ARRAY: {
				const PackedByteArray first = rows[0];
				const PackedByteArray second = rows[1];
				REQUIRE(first.size() == 3);
				REQUIRE(second.size() == 3);
				CHECK(first[0] == 1);
				CHECK(first[2] == 3);
				CHECK(second[0] == 4);
				CHECK(second[2] == 6);
			} break;
			case Variant::PACKED_INT32_ARRAY: {
				const PackedInt32Array first = rows[0];
				const PackedInt32Array second = rows[1];
				REQUIRE(first.size() == 3);
				REQUIRE(second.size() == 3);
				CHECK(first[0] == 1);
				CHECK(first[2] == 3);
				CHECK(second[0] == 4);
				CHECK(second[2] == 6);
			} break;
			case Variant::PACKED_INT64_ARRAY: {
				const PackedInt64Array first = rows[0];
				const PackedInt64Array second = rows[1];
				REQUIRE(first.size() == 3);
				REQUIRE(second.size() == 3);
				CHECK(first[0] == 1);
				CHECK(first[2] == 3);
				CHECK(second[0] == 4);
				CHECK(second[2] == 6);
			} break;
			case Variant::PACKED_FLOAT32_ARRAY: {
				const PackedFloat32Array first = rows[0];
				const PackedFloat32Array second = rows[1];
				REQUIRE(first.size() == 3);
				REQUIRE(second.size() == 3);
				CHECK(first[0] == 1.0f);
				CHECK(first[2] == 3.0f);
				CHECK(second[0] == 4.0f);
				CHECK(second[2] == 6.0f);
			} break;
			case Variant::PACKED_FLOAT64_ARRAY: {
				const PackedFloat64Array first = rows[0];
				const PackedFloat64Array second = rows[1];
				REQUIRE(first.size() == 3);
				REQUIRE(second.size() == 3);
				CHECK(first[0] == 1.0);
				CHECK(first[2] == 3.0);
				CHECK(second[0] == 4.0);
				CHECK(second[2] == 6.0);
			} break;
			default:
				FAIL("Unexpected accessor variant type.");
		}
	}
}

TEST_CASE("[SceneTree][GLTFDocument] Spotlight attenuation conversion roundtrips") {
	SpotLight3D *original = memnew(SpotLight3D);
	original->set_param(SpotLight3D::PARAM_SPOT_ANGLE, 50.0f);
	original->set_param(SpotLight3D::PARAM_SPOT_ATTENUATION, 1.2f);
	Ref<GLTFLight> exported = GLTFLight::from_node(original);
	REQUIRE(exported.is_valid());
	CHECK(exported->get_inner_cone_angle() < exported->get_outer_cone_angle());
	CHECK(Math::is_equal_approx(exported->get_outer_cone_angle(), Math::deg_to_rad(50.0f)));

	Light3D *imported_light = exported->to_node();
	REQUIRE(imported_light != nullptr);
	SpotLight3D *imported = Object::cast_to<SpotLight3D>(imported_light);
	REQUIRE(imported != nullptr);
	CHECK(Math::is_equal_approx(imported->get_param(SpotLight3D::PARAM_SPOT_ANGLE), 50.0f));
	CHECK(Math::is_equal_approx(imported->get_param(SpotLight3D::PARAM_SPOT_ATTENUATION), 1.2f));
	memdelete(imported_light);
	memdelete(original);
}

TEST_CASE("[SceneTree][GLTFDocument] Equal glTF spotlight cone angles avoid division by zero") {
	Ref<GLTFLight> light;
	light.instantiate();
	light->set_light_type("spot");
	light->set_outer_cone_angle(0.5f);
	light->set_inner_cone_angle(0.5f);
	Light3D *node = light->to_node();
	REQUIRE(node != nullptr);
	SpotLight3D *spot = Object::cast_to<SpotLight3D>(node);
	REQUIRE(spot != nullptr);
	CHECK(spot->get_param(SpotLight3D::PARAM_SPOT_ATTENUATION) == 0.0f);
	memdelete(node);
}


TEST_CASE("[GLTFAttributeFastPath] mesh tangent and normal buffers preserve geometry across export") {
	register_gltf_extension();
	Node3D *root = memnew(Node3D);
	root->set_name("GLTFAttributeRoot");
	MeshInstance3D *mesh_node = memnew(MeshInstance3D);
	root->add_child(mesh_node);
	mesh_node->set_owner(root);
	mesh_node->set_name("AttributeTriangle");

	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	const PackedVector3Array vertices = { Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0) };
	const PackedVector3Array normals = { Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1) };
	PackedFloat32Array tangents;
	for (int i = 0; i < 3; ++i) {
		tangents.push_back(1.0f);
		tangents.push_back(0.0f);
		tangents.push_back(0.0f);
		tangents.push_back(1.0f);
	}
	const PackedInt32Array indices = { 0, 1, 2 };
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_TANGENT] = tangents;
	arrays[Mesh::ARRAY_INDEX] = indices;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	mesh_node->set_mesh(mesh);

	Ref<GLTFDocument> exporter;
	exporter.instantiate();
	Ref<GLTFState> state;
	state.instantiate();
	const String path = TestUtils::get_temp_path("mesh_attribute_fastpath.glb");
	REQUIRE_EQ(exporter->append_from_scene(root, state), OK);
	REQUIRE_EQ(exporter->write_to_filesystem(state, path), OK);

	Ref<GLTFDocument> importer;
	importer.instantiate();
	Ref<GLTFState> loaded;
	loaded.instantiate();
	REQUIRE_EQ(importer->append_from_file(path, loaded), OK);
	Node *loaded_scene = importer->generate_scene(loaded);
	REQUIRE(loaded_scene != nullptr);
	CHECK(loaded_scene->get_child_count() > 0);
	MeshInstance3D *imported_node = loaded_scene->get_child_count() > 0 ? Object::cast_to<MeshInstance3D>(loaded_scene->get_child(0)) : nullptr;
	REQUIRE(imported_node != nullptr);
	Ref<Mesh> imported_mesh = imported_node->get_mesh();
	REQUIRE(imported_mesh.is_valid());
	const Array imported_arrays = imported_mesh->surface_get_arrays(0);
	const PackedVector3Array imported_normals = imported_arrays[Mesh::ARRAY_NORMAL];
	const PackedFloat32Array imported_tangents = imported_arrays[Mesh::ARRAY_TANGENT];
	REQUIRE_EQ(imported_normals.size(), 3);
	REQUIRE_EQ(imported_tangents.size(), 12);
	for (int i = 0; i < 3; ++i) {
		CHECK(imported_normals[i].is_equal_approx(Vector3(0, 0, 1)));
		CHECK(Math::is_equal_approx(imported_tangents[i * 4 + 0], 1.0f));
		CHECK(Math::is_zero_approx(imported_tangents[i * 4 + 1]));
		CHECK(Math::is_zero_approx(imported_tangents[i * 4 + 2]));
		CHECK(Math::is_equal_approx(imported_tangents[i * 4 + 3], 1.0f));
	}
	memdelete(loaded_scene);
	memdelete(root);
}

} // namespace TestGLTFDocument

#endif // MODULE_GLTF_ENABLED

#endif // _3D_DISABLED
