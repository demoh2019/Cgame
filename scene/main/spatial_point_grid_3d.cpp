/**************************************************************************/
/*  spatial_point_grid_3d.cpp                                             */
/**************************************************************************/

#include "spatial_point_grid_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

#include <cstdint>

Vector3i SpatialPointGrid3D::_cell_of(const Vector3 &p_point, real_t p_size) {
	return Vector3i(int32_t(Math::floor(p_point.x / p_size)),
			int32_t(Math::floor(p_point.y / p_size)),
			int32_t(Math::floor(p_point.z / p_size)));
}

bool SpatialPointGrid3D::_safe_cell(const Vector3 &p_point) const {
	const double bound = (double(INT32_MAX) - 1024.0) * double(cell_size);
	return p_point.is_finite() &&
			Math::abs(double(p_point.x)) + 512.0 < bound &&
			Math::abs(double(p_point.y)) + 512.0 < bound &&
			Math::abs(double(p_point.z)) + 512.0 < bound;
}

void SpatialPointGrid3D::_reindex() {
	cells.clear();
	indexed_mode = positions.size() > 12;
	if (!indexed_mode) {
		return;
	}
	for (const Vector3 &position : positions) {
		if (!_safe_cell(position)) {
			indexed_mode = false;
			return; // Unindexable outliers still participate in direct queries.
		}
	}
	for (const Vector3 &position : positions) {
		const Vector3i key = _cell_of(position, cell_size);
		Vector<Vector3> *bucket = cells.getptr(key);
		if (bucket == nullptr) {
			cells.insert(key, Vector<Vector3>());
			bucket = cells.getptr(key);
		}
		bucket->push_back(position);
	}
}

bool SpatialPointGrid3D::set_cell_size(real_t p_size) {
	if (!Math::is_finite(p_size) || p_size < real_t(1.0) || p_size > real_t(4096.0)) {
		return false;
	}
	if (cell_size != p_size) {
		cell_size = p_size;
		_reindex();
	}
	return true;
}

bool SpatialPointGrid3D::rebuild(const TypedArray<Vector3> &p_positions) {
	if (p_positions.size() > MAX_POINTS) {
		return false; // Atomic refusal: preserve the existing snapshot.
	}
	Vector<Vector3> next;
	for (int i = 0; i < p_positions.size(); i++) {
		const Vector3 point = p_positions[i];
		if (point.is_finite()) {
			next.push_back(point);
		}
	}
	positions = next;
	queries = 0;
	batch_calls = 0;
	candidate_checks = 0;
	bucket_lookups = 0;
	_reindex();
	return true;
}

void SpatialPointGrid3D::clear() {
	positions.clear();
	cells.clear();
	indexed_mode = false;
	queries = 0;
	batch_calls = 0;
	candidate_checks = 0;
	bucket_lookups = 0;
}

int SpatialPointGrid3D::_direct_count(const Vector3 &p_center, real_t p_squared_radius, int p_limit) {
	int result = 0;
	for (const Vector3 &point : positions) {
		candidate_checks++;
		if (p_center.distance_squared_to(point) <= p_squared_radius && ++result >= p_limit) {
			break;
		}
	}
	return result;
}

int SpatialPointGrid3D::count_within(const Vector3 &p_center, real_t p_radius, int p_limit) {
	if (!p_center.is_finite() || !Math::is_finite(p_radius) ||
			p_radius < real_t(0.0) || p_radius > real_t(1000000.0) ||
			p_limit < 1 || p_limit > MAX_POINTS) {
		return -1;
	}
	queries++;
	const real_t squared_radius = p_radius * p_radius;
	if (!indexed_mode || p_radius > real_t(256.0) || !_safe_cell(p_center)) {
		return _direct_count(p_center, squared_radius, p_limit);
	}
	const Vector3 extent(p_radius, p_radius, p_radius);
	const Vector3i lo = _cell_of(p_center - extent, cell_size);
	const Vector3i hi = _cell_of(p_center + extent, cell_size);
	const int64_t nx = int64_t(hi.x) - lo.x + 1;
	const int64_t ny = int64_t(hi.y) - lo.y + 1;
	const int64_t nz = int64_t(hi.z) - lo.z + 1;
	if (nx <= 0 || ny <= 0 || nz <= 0 || nx * ny * nz > MAX_BUCKET_VISITS) {
		return _direct_count(p_center, squared_radius, p_limit);
	}
	int matches = 0;
	for (int64_t x = lo.x; x <= hi.x; x++) {
		for (int64_t y = lo.y; y <= hi.y; y++) {
			for (int64_t z = lo.z; z <= hi.z; z++) {
				bucket_lookups++;
				const Vector<Vector3> *bucket = cells.getptr(Vector3i(int32_t(x), int32_t(y), int32_t(z)));
				if (bucket == nullptr) {
					continue;
				}
				for (const Vector3 &point : *bucket) {
					candidate_checks++;
					if (p_center.distance_squared_to(point) <= squared_radius && ++matches >= p_limit) {
						return matches;
					}
				}
			}
		}
	}
	return matches;
}

PackedInt32Array SpatialPointGrid3D::count_within_batch(const PackedVector3Array &p_centers, real_t p_radius, int p_limit) {
	PackedInt32Array result;
	if (p_centers.size() > MAX_PROBES || !Math::is_finite(p_radius) ||
			p_radius < 0.0 || p_radius > 1000000.0 ||
			p_limit < 1 || p_limit > MAX_POINTS) {
		return result;
	}
	batch_calls++;
	result.resize(p_centers.size());
	for (int i = 0; i < p_centers.size(); i++) {
		const int count = count_within(p_centers[i], p_radius, p_limit);
		result.set(i, MAX(0, count));
	}
	return result;
}

Dictionary SpatialPointGrid3D::get_stats() const {
	Dictionary result;
	result["points"] = positions.size();
	result["occupied_cells"] = cells.size();
	result["indexed_mode"] = indexed_mode;
	result["queries"] = int64_t(queries);
	result["batch_calls"] = int64_t(batch_calls);
	result["candidate_checks"] = int64_t(candidate_checks);
	result["bucket_lookups"] = int64_t(bucket_lookups);
	return result;
}

void SpatialPointGrid3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &SpatialPointGrid3D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &SpatialPointGrid3D::get_cell_size);
	ClassDB::bind_method(D_METHOD("rebuild", "positions"), &SpatialPointGrid3D::rebuild);
	ClassDB::bind_method(D_METHOD("clear"), &SpatialPointGrid3D::clear);
	ClassDB::bind_method(D_METHOD("count_within", "center", "radius", "limit"), &SpatialPointGrid3D::count_within, DEFVAL(20));
	ClassDB::bind_method(D_METHOD("count_within_batch", "centers", "radius", "limit"), &SpatialPointGrid3D::count_within_batch, DEFVAL(20));
	ClassDB::bind_method(D_METHOD("get_point_count"), &SpatialPointGrid3D::get_point_count);
	ClassDB::bind_method(D_METHOD("get_stats"), &SpatialPointGrid3D::get_stats);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,4096,1"), "set_cell_size", "get_cell_size");
}
