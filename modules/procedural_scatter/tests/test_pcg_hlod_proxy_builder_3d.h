/**************************************************************************/
/*  test_pcg_hlod_proxy_builder_3d.h                                        */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_hlod_proxy_builder_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGHLODProxyBuilder3D {

TEST_CASE("[PCGHLODProxyBuilder3D] merged octahedra use one surface and eight triangles per instance") {
	Ref<PCGHLODProxyBuilder3D> builder;
	builder.instantiate();
	Array transforms;
	transforms.push_back(Transform3D(Basis(), Vector3(10, 2, 20)));
	transforms.push_back(Transform3D(Basis().scaled(Vector3(2, 2, 2)), Vector3(30, 4, 40)));
	const PackedVector3Array centers = { Vector3(), Vector3(0, 1, 0) };
	const PackedVector3Array extents = { Vector3(1, 2, 3), Vector3(2, 1, 1) };
	const Array originals = transforms.duplicate();
	const Ref<ArrayMesh> mesh = builder->build_octahedral_proxy(transforms, centers, extents);
	REQUIRE(mesh.is_valid());
	REQUIRE(mesh->get_surface_count() == 1);
	CHECK(mesh->surface_get_primitive_type(0) == Mesh::PRIMITIVE_TRIANGLES);
	CHECK(mesh->surface_get_array_len(0) == 48); // 2 * 8 * 3.
	const Array arrays = mesh->surface_get_arrays(0);
	const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	REQUIRE(vertices.size() == 48);
	CHECK(vertices[0].is_equal_approx(Vector3(10, 4, 20)));
	CHECK(vertices[1].is_equal_approx(Vector3(11, 2, 20)));
	CHECK(vertices[2].is_equal_approx(Vector3(10, 2, 17)));
	CHECK(vertices[24].is_equal_approx(Vector3(30, 8, 40)));
	const PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	CHECK(normals.size() == 48);
	CHECK(Math::is_equal_approx(double(normals[0].length()), 1.0));
	CHECK(mesh->get_surface_count() == 1);
	CHECK(transforms == originals);
	const Ref<ArrayMesh> again = builder->build_octahedral_proxy(transforms, centers, extents);
	REQUIRE(again.is_valid());
	CHECK(again->surface_get_arrays(0)[Mesh::ARRAY_VERTEX] == arrays[Mesh::ARRAY_VERTEX]);
}

TEST_CASE("[PCGHLODProxyBuilder3D] deterministic source sampling and triangle budget") {
	Ref<PCGHLODProxyBuilder3D> builder;
	builder.instantiate();
	Array transforms;
	PackedVector3Array centers;
	PackedVector3Array extents;
	for (int i = 0; i < 12; ++i) {
		transforms.push_back(Transform3D(Basis(), Vector3(i * 10, 0, 0)));
		centers.push_back(Vector3());
		extents.push_back(Vector3(1, 1, 1));
	}
	const Ref<ArrayMesh> sampled = builder->build_octahedral_proxy(
			transforms, centers, extents, 3);
	REQUIRE(sampled.is_valid());
	CHECK(sampled->get_surface_count() == 1);
	CHECK(sampled->surface_get_array_len(0) == 72);
	const PackedVector3Array vertices = sampled->surface_get_arrays(0)[Mesh::ARRAY_VERTEX];
	REQUIRE(vertices.size() == 72);
	CHECK(vertices[0].is_equal_approx(Vector3(0, 1, 0)));
	CHECK(vertices[24].is_equal_approx(Vector3(40, 1, 0)));
	CHECK(vertices[48].is_equal_approx(Vector3(80, 1, 0)));
	Array big;
	PackedVector3Array big_centers;
	PackedVector3Array big_extents;
	for (int i = 0; i < 700; ++i) {
		big.push_back(Transform3D(Basis(), Vector3(i, 0, 0)));
		big_centers.push_back(Vector3());
		big_extents.push_back(Vector3(0.2, 0.2, 0.2));
	}
	const Ref<ArrayMesh> limited = builder->build_octahedral_proxy(
			big, big_centers, big_extents, 512);
	REQUIRE(limited.is_valid());
	CHECK(limited->surface_get_array_len(0) == 512 * 8 * 3);
}

TEST_CASE("[PCGHLODProxyBuilder3D] invalid late geometry rejects whole mesh") {
	Ref<PCGHLODProxyBuilder3D> builder;
	builder.instantiate();
	Array transforms;
	transforms.push_back(Transform3D());
	transforms.push_back(Transform3D(Basis(), Vector3(2, 0, 0)));
	PackedVector3Array centers;
	centers.push_back(Vector3());
	centers.push_back(Vector3());
	PackedVector3Array extents;
	extents.push_back(Vector3(1, 1, 1));
	extents.push_back(Vector3(1, 1, 1));
	CHECK(builder->build_octahedral_proxy(Array(), {}, {}).is_null());
	CHECK(builder->build_octahedral_proxy(transforms, { Vector3() }, extents).is_null());
	CHECK(builder->build_octahedral_proxy(transforms, centers, { Vector3() }).is_null());
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents, 0).is_null());
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents, 513).is_null());
	transforms[1] = 42;
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents).is_null());
	transforms[1] = Transform3D(Basis(), Vector3(Math::NaN, 0, 0));
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents).is_null());
	transforms[1] = Transform3D(Basis().scaled(Vector3(1001, 1, 1)), Vector3());
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents).is_null());
	transforms[1] = Transform3D();
	extents.set(1, Vector3(-1, 1, 1));
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents).is_null());
	extents.set(1, Vector3(0, 1, 1));
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents).is_null());
	extents.set(1, Vector3(10001, 1, 1));
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents).is_null());
	extents.set(1, Vector3(1, 1, 1));
	centers.set(1, Vector3(Math::INF, 1, 1));
	CHECK(builder->build_octahedral_proxy(transforms, centers, extents).is_null());
	PackedVector3Array huge_centers;
	PackedVector3Array huge_extents;
	Array huge_transforms;
	for (int i = 0; i < 8193; ++i) {
		huge_centers.push_back(Vector3());
		huge_extents.push_back(Vector3(1, 1, 1));
		huge_transforms.push_back(Transform3D());
	}
	CHECK(builder->build_octahedral_proxy(huge_transforms, huge_centers, huge_extents).is_null());
}

} // namespace TestPCGHLODProxyBuilder3D
