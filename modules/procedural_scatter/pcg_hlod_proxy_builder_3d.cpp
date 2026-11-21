/**************************************************************************/
/*  pcg_hlod_proxy_builder_3d.cpp                                           */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_hlod_proxy_builder_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "scene/resources/surface_tool.h"

void PCGHLODProxyBuilder3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_octahedral_proxy", "transforms", "local_centers",
					"local_half_extents", "max_proxy_instances"),
			&PCGHLODProxyBuilder3D::build_octahedral_proxy, DEFVAL(MAX_PROXY_INSTANCES));
}

Ref<ArrayMesh> PCGHLODProxyBuilder3D::build_octahedral_proxy(
		const Array &p_transforms, const PackedVector3Array &p_local_centers,
		const PackedVector3Array &p_local_half_extents, int p_max_proxy_instances) const {
	Ref<ArrayMesh> invalid;
	const int count = p_transforms.size();
	if (count == 0 || count > MAX_INPUT_INSTANCES ||
			count != p_local_centers.size() || count != p_local_half_extents.size() ||
			p_max_proxy_instances < 1 || p_max_proxy_instances > MAX_PROXY_INSTANCES) {
		return invalid;
	}
	// Complete atomic preflight. A malformed late entry must not emit a
	// partially constructed distant mesh that would replace correct sources.
	for (int i = 0; i < count; ++i) {
		if (p_transforms[i].get_type() != Variant::TRANSFORM3D) {
			return invalid;
		}
		const Transform3D transform = p_transforms[i];
		const Vector3 local_center = p_local_centers[i];
		const Vector3 half = p_local_half_extents[i];
		if (!transform.is_finite() || !local_center.is_finite() || !half.is_finite() ||
				Math::abs(double(transform.origin.x)) > MAX_COORDINATE ||
				Math::abs(double(transform.origin.y)) > MAX_COORDINATE ||
				Math::abs(double(transform.origin.z)) > MAX_COORDINATE ||
				Math::abs(double(local_center.x)) > MAX_HALF_EXTENT ||
				Math::abs(double(local_center.y)) > MAX_HALF_EXTENT ||
				Math::abs(double(local_center.z)) > MAX_HALF_EXTENT ||
				half.x <= 0.0 || half.y <= 0.0 || half.z <= 0.0 ||
				double(half.x) > MAX_HALF_EXTENT ||
				double(half.y) > MAX_HALF_EXTENT ||
				double(half.z) > MAX_HALF_EXTENT ||
				transform.basis.get_column(0).length() < 0.0001 ||
				transform.basis.get_column(1).length() < 0.0001 ||
				transform.basis.get_column(2).length() < 0.0001 ||
				transform.basis.get_column(0).length() > MAX_BASIS_AXIS ||
				transform.basis.get_column(1).length() > MAX_BASIS_AXIS ||
				transform.basis.get_column(2).length() > MAX_BASIS_AXIS) {
			return invalid;
		}
	}

	const int sampled = MIN(count, p_max_proxy_instances);
	Ref<SurfaceTool> surface;
	surface.instantiate();
	surface->begin(Mesh::PRIMITIVE_TRIANGLES);
	static const int triangles[8][3] = {
		{ 0, 1, 2 }, { 0, 2, 3 }, { 0, 3, 4 }, { 0, 4, 1 },
		{ 5, 2, 1 }, { 5, 3, 2 }, { 5, 4, 3 }, { 5, 1, 4 }
	};
	// Evenly sample at most 512 authored objects; fixed input order and no
	// global RNG, with at most 4096 triangles and one output mesh surface.
	for (int s = 0; s < sampled; ++s) {
		const int source = int((int64_t(s) * count) / sampled);
		const Transform3D transform = p_transforms[source];
		const Vector3 center = p_local_centers[source];
		const Vector3 half = p_local_half_extents[source];
		const Vector3 points[6] = {
			transform.xform(center + Vector3(0, half.y, 0)),
			transform.xform(center + Vector3(half.x, 0, 0)),
			transform.xform(center + Vector3(0, 0, -half.z)),
			transform.xform(center + Vector3(-half.x, 0, 0)),
			transform.xform(center + Vector3(0, 0, half.z)),
			transform.xform(center + Vector3(0, -half.y, 0))
		};
		for (int t = 0; t < 8; ++t) {
			const Vector3 a = points[triangles[t][0]];
			const Vector3 b = points[triangles[t][1]];
			const Vector3 c = points[triangles[t][2]];
			if (!a.is_finite() || !b.is_finite() || !c.is_finite()) {
				return invalid;
			}
			const Vector3 normal = (b - a).cross(c - a).normalized();
			if (!normal.is_finite() || normal.length_squared() < 0.5) {
				return invalid;
			}
			surface->set_normal(normal);
			surface->add_vertex(a);
			surface->set_normal(normal);
			surface->add_vertex(b);
			surface->set_normal(normal);
			surface->add_vertex(c);
		}
	}
	return surface->commit();
}
