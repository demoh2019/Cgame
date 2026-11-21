/**************************************************************************/
/*  pcg_data.cpp                                                          */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_data.h"

#include "core/object/class_db.h"

void PCGData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_data_type"), &PCGData::get_data_type);
	ClassDB::bind_method(D_METHOD("get_content_hash"), &PCGData::get_content_hash);
}

// --- Points ------------------------------------------------------------------------------------------------------

uint64_t PCGPointData::compute_content_hash() const {
	uint64_t h = pcg_mix64(0x5043475054ULL, (uint64_t)positions.size());
	for (int i = 0; i < positions.size(); i++) {
		const Vector3 p = positions[i];
		h = pcg_hash_double(h, p.x);
		h = pcg_hash_double(h, p.y);
		h = pcg_hash_double(h, p.z);
		h = pcg_hash_double(h, density[i]);
		h = pcg_hash_double(h, yaw[i]);
		h = pcg_hash_double(h, scale[i]);
		h = pcg_mix64(h, (uint64_t)seeds[i]);
	}
	Array keys = attributes.keys();
	keys.sort();
	for (int k = 0; k < keys.size(); k++) {
		h = pcg_mix64(h, (uint64_t)String(keys[k]).hash());
		PackedFloat32Array values = attributes[keys[k]];
		for (int i = 0; i < values.size(); i++) {
			h = pcg_hash_double(h, values[i]);
		}
	}
	return h;
}

void PCGPointData::add_point(const Vector3 &p_position, const Vector3 &p_normal, float p_density, float p_yaw, float p_scale, int64_t p_seed) {
	positions.push_back(p_position);
	normals.push_back(p_normal);
	density.push_back(p_density);
	yaw.push_back(p_yaw);
	scale.push_back(p_scale);
	seeds.push_back(p_seed);
	Array keys = attributes.keys();
	for (int k = 0; k < keys.size(); k++) {
		PackedFloat32Array values = attributes[keys[k]];
		values.push_back(0.0);
		attributes[keys[k]] = values;
	}
}

void PCGPointData::clear() {
	positions.clear();
	normals.clear();
	density.clear();
	yaw.clear();
	scale.clear();
	seeds.clear();
	attributes.clear();
}

Vector3 PCGPointData::get_position(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, positions.size(), Vector3());
	return positions[p_index];
}

Vector3 PCGPointData::get_normal(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, normals.size(), Vector3(0, 1, 0));
	return normals[p_index];
}

float PCGPointData::get_density(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, density.size(), 0.0);
	return density[p_index];
}

float PCGPointData::get_yaw(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, yaw.size(), 0.0);
	return yaw[p_index];
}

float PCGPointData::get_scale(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, scale.size(), 1.0);
	return scale[p_index];
}

int64_t PCGPointData::get_seed(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, seeds.size(), 0);
	return seeds[p_index];
}

void PCGPointData::set_position(int p_index, const Vector3 &p_position) {
	ERR_FAIL_INDEX(p_index, positions.size());
	positions.set(p_index, p_position);
}

void PCGPointData::set_density(int p_index, float p_density) {
	ERR_FAIL_INDEX(p_index, density.size());
	density.set(p_index, p_density);
}

void PCGPointData::set_yaw(int p_index, float p_yaw) {
	ERR_FAIL_INDEX(p_index, yaw.size());
	yaw.set(p_index, p_yaw);
}

void PCGPointData::set_scale(int p_index, float p_scale) {
	ERR_FAIL_INDEX(p_index, scale.size());
	scale.set(p_index, p_scale);
}

bool PCGPointData::has_attribute(const StringName &p_name) const {
	return attributes.has(p_name);
}

PackedStringArray PCGPointData::get_attribute_names() const {
	PackedStringArray names;
	Array keys = attributes.keys();
	for (int i = 0; i < keys.size(); i++) {
		names.push_back(String(keys[i]));
	}
	names.sort();
	return names;
}

PackedFloat32Array PCGPointData::get_attribute(const StringName &p_name) const {
	if (attributes.has(p_name)) {
		return attributes[p_name];
	}
	PackedFloat32Array zeros;
	zeros.resize(positions.size());
	zeros.fill(0.0);
	return zeros;
}

float PCGPointData::get_attribute_value(const StringName &p_name, int p_index, float p_default) const {
	if (!attributes.has(p_name)) {
		return p_default;
	}
	PackedFloat32Array values = attributes[p_name];
	ERR_FAIL_INDEX_V(p_index, values.size(), p_default);
	return values[p_index];
}

void PCGPointData::set_attribute(const StringName &p_name, const PackedFloat32Array &p_values) {
	ERR_FAIL_COND_MSG(p_values.size() != positions.size(), "PCG attribute needs one value per point.");
	attributes[p_name] = p_values;
}

void PCGPointData::set_attribute_value(const StringName &p_name, int p_index, float p_value) {
	ERR_FAIL_INDEX(p_index, positions.size());
	PackedFloat32Array values = get_attribute(p_name);
	values.set(p_index, p_value);
	attributes[p_name] = values;
}

Ref<PCGPointData> PCGPointData::select(const PackedInt32Array &p_indices) const {
	Ref<PCGPointData> out;
	out.instantiate();
	Array keys = attributes.keys();
	Vector<PackedFloat32Array> sources;
	Vector<PackedFloat32Array> targets;
	for (int k = 0; k < keys.size(); k++) {
		sources.push_back(attributes[keys[k]]);
		targets.push_back(PackedFloat32Array());
	}
	for (int n = 0; n < p_indices.size(); n++) {
		const int i = p_indices[n];
		ERR_CONTINUE(i < 0 || i >= positions.size());
		out->positions.push_back(positions[i]);
		out->normals.push_back(normals[i]);
		out->density.push_back(density[i]);
		out->yaw.push_back(yaw[i]);
		out->scale.push_back(scale[i]);
		out->seeds.push_back(seeds[i]);
		for (int k = 0; k < sources.size(); k++) {
			targets.write[k].push_back(sources[k][i]);
		}
	}
	for (int k = 0; k < keys.size(); k++) {
		out->attributes[keys[k]] = targets[k];
	}
	return out;
}

void PCGPointData::append(const Ref<PCGPointData> &p_other) {
	ERR_FAIL_COND(p_other.is_null());
	const int before = positions.size();
	const int added = p_other->positions.size();
	positions.append_array(p_other->positions);
	normals.append_array(p_other->normals);
	density.append_array(p_other->density);
	yaw.append_array(p_other->yaw);
	scale.append_array(p_other->scale);
	seeds.append_array(p_other->seeds);
	// Union of attribute names; missing values are zero.
	Array keys = attributes.keys();
	Array other_keys = p_other->attributes.keys();
	for (int k = 0; k < other_keys.size(); k++) {
		if (!keys.has(other_keys[k])) {
			keys.push_back(other_keys[k]);
		}
	}
	for (int k = 0; k < keys.size(); k++) {
		PackedFloat32Array mine;
		if (attributes.has(keys[k])) {
			mine = attributes[keys[k]];
		} else {
			mine.resize(before);
			mine.fill(0.0);
		}
		if (p_other->attributes.has(keys[k])) {
			PackedFloat32Array theirs = p_other->attributes[keys[k]];
			mine.append_array(theirs);
		} else {
			const int start = mine.size();
			mine.resize(start + added);
			for (int i = start; i < mine.size(); i++) {
				mine.set(i, 0.0);
			}
		}
		attributes[keys[k]] = mine;
	}
}

Ref<PCGPointData> PCGPointData::duplicate_points() const {
	Ref<PCGPointData> out;
	out.instantiate();
	out->positions = positions;
	out->normals = normals;
	out->density = density;
	out->yaw = yaw;
	out->scale = scale;
	out->seeds = seeds;
	out->attributes = attributes.duplicate(true);
	return out;
}

Transform3D PCGPointData::get_point_transform(int p_index, bool p_align_to_normal) const {
	ERR_FAIL_INDEX_V(p_index, positions.size(), Transform3D());
	Basis basis(Vector3(0, 1, 0), yaw[p_index]);
	if (p_align_to_normal) {
		const Vector3 n = normals[p_index].normalized();
		if (n.length_squared() > 0.5 && n.dot(Vector3(0, 1, 0)) < 0.9999) {
			const Vector3 axis = Vector3(0, 1, 0).cross(n).normalized();
			const float angle = Math::acos(CLAMP(n.dot(Vector3(0, 1, 0)), -1.0f, 1.0f));
			basis = Basis(axis, angle) * basis;
		}
	}
	basis.scale(Vector3(scale[p_index], scale[p_index], scale[p_index]));
	return Transform3D(basis, positions[p_index]);
}

AABB PCGPointData::get_bounds() const {
	if (positions.is_empty()) {
		return AABB();
	}
	AABB box(positions[0], Vector3());
	for (int i = 1; i < positions.size(); i++) {
		box.expand_to(positions[i]);
	}
	return box;
}

void PCGPointData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_point_count"), &PCGPointData::get_point_count);
	ClassDB::bind_method(D_METHOD("add_point", "position", "normal", "density", "yaw", "scale", "seed"), &PCGPointData::add_point, DEFVAL(Vector3(0, 1, 0)), DEFVAL(1.0), DEFVAL(0.0), DEFVAL(1.0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("clear"), &PCGPointData::clear);
	ClassDB::bind_method(D_METHOD("get_position", "index"), &PCGPointData::get_position);
	ClassDB::bind_method(D_METHOD("get_normal", "index"), &PCGPointData::get_normal);
	ClassDB::bind_method(D_METHOD("get_density", "index"), &PCGPointData::get_density);
	ClassDB::bind_method(D_METHOD("get_yaw", "index"), &PCGPointData::get_yaw);
	ClassDB::bind_method(D_METHOD("get_scale", "index"), &PCGPointData::get_scale);
	ClassDB::bind_method(D_METHOD("get_seed", "index"), &PCGPointData::get_seed);
	ClassDB::bind_method(D_METHOD("set_position", "index", "position"), &PCGPointData::set_position);
	ClassDB::bind_method(D_METHOD("set_density", "index", "density"), &PCGPointData::set_density);
	ClassDB::bind_method(D_METHOD("set_yaw", "index", "yaw"), &PCGPointData::set_yaw);
	ClassDB::bind_method(D_METHOD("set_scale", "index", "scale"), &PCGPointData::set_scale);
	ClassDB::bind_method(D_METHOD("get_positions"), &PCGPointData::get_positions);
	ClassDB::bind_method(D_METHOD("get_normals"), &PCGPointData::get_normals);
	ClassDB::bind_method(D_METHOD("get_densities"), &PCGPointData::get_densities);
	ClassDB::bind_method(D_METHOD("get_yaws"), &PCGPointData::get_yaws);
	ClassDB::bind_method(D_METHOD("get_scales"), &PCGPointData::get_scales);
	ClassDB::bind_method(D_METHOD("get_seeds"), &PCGPointData::get_seeds);
	ClassDB::bind_method(D_METHOD("has_attribute", "name"), &PCGPointData::has_attribute);
	ClassDB::bind_method(D_METHOD("get_attribute_names"), &PCGPointData::get_attribute_names);
	ClassDB::bind_method(D_METHOD("get_attribute", "name"), &PCGPointData::get_attribute);
	ClassDB::bind_method(D_METHOD("get_attribute_value", "name", "index", "default"), &PCGPointData::get_attribute_value, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_attribute", "name", "values"), &PCGPointData::set_attribute);
	ClassDB::bind_method(D_METHOD("set_attribute_value", "name", "index", "value"), &PCGPointData::set_attribute_value);
	ClassDB::bind_method(D_METHOD("select", "indices"), &PCGPointData::select);
	ClassDB::bind_method(D_METHOD("append", "other"), &PCGPointData::append);
	ClassDB::bind_method(D_METHOD("duplicate_points"), &PCGPointData::duplicate_points);
	ClassDB::bind_method(D_METHOD("get_point_transform", "index", "align_to_normal"), &PCGPointData::get_point_transform, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_bounds"), &PCGPointData::get_bounds);
	ClassDB::bind_method(D_METHOD("to_dictionary"), &PCGPointData::to_dictionary);
	ClassDB::bind_static_method("PCGPointData", D_METHOD("from_dictionary", "data"), &PCGPointData::from_dictionary);
}

// --- Splines -----------------------------------------------------------------------------------------------------

uint64_t PCGSplineData::compute_content_hash() const {
	uint64_t h = pcg_mix64(0x5043475350ULL, (uint64_t)polylines.size());
	for (int i = 0; i < polylines.size(); i++) {
		PackedVector3Array points = polylines[i];
		h = pcg_mix64(h, (uint64_t)points.size());
		for (int j = 0; j < points.size(); j++) {
			h = pcg_hash_double(h, points[j].x);
			h = pcg_hash_double(h, points[j].y);
			h = pcg_hash_double(h, points[j].z);
		}
		h = pcg_hash_double(h, get_width(i));
	}
	return h;
}

void PCGSplineData::add_polyline(const PackedVector3Array &p_points, float p_width) {
	polylines.push_back(p_points);
	widths.push_back(p_width);
}

PackedVector3Array PCGSplineData::get_polyline(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, polylines.size(), PackedVector3Array());
	return polylines[p_index];
}

float PCGSplineData::get_width(int p_index) const {
	if (p_index < 0 || p_index >= widths.size()) {
		return 0.0;
	}
	return widths[p_index];
}

void PCGSplineData::set_polylines(const TypedArray<PackedVector3Array> &p_polylines) {
	polylines = p_polylines;
	widths.resize(polylines.size());
	widths.fill(0.0);
}

float PCGSplineData::polyline_length(const PackedVector3Array &p_points) {
	float length = 0.0;
	for (int i = 1; i < p_points.size(); i++) {
		length += p_points[i - 1].distance_to(p_points[i]);
	}
	return length;
}

float PCGSplineData::distance_xz(const Vector3 &p_point) const {
	float best = Math::INF;
	const Vector2 p(p_point.x, p_point.z);
	for (int i = 0; i < polylines.size(); i++) {
		PackedVector3Array points = polylines[i];
		for (int j = 1; j < points.size(); j++) {
			const Vector2 a(points[j - 1].x, points[j - 1].z);
			const Vector2 b(points[j].x, points[j].z);
			const Vector2 ab = b - a;
			const float len2 = ab.length_squared();
			const float t = len2 > 0.0 ? CLAMP((p - a).dot(ab) / len2, 0.0f, 1.0f) : 0.0f;
			best = MIN(best, p.distance_to(a + ab * t));
		}
		if (points.size() == 1) {
			best = MIN(best, p.distance_to(Vector2(points[0].x, points[0].z)));
		}
	}
	return best;
}

void PCGSplineData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_polyline", "points", "width"), &PCGSplineData::add_polyline, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("get_polyline_count"), &PCGSplineData::get_polyline_count);
	ClassDB::bind_method(D_METHOD("get_polyline", "index"), &PCGSplineData::get_polyline);
	ClassDB::bind_method(D_METHOD("get_width", "index"), &PCGSplineData::get_width);
	ClassDB::bind_method(D_METHOD("get_polylines"), &PCGSplineData::get_polylines);
	ClassDB::bind_method(D_METHOD("set_polylines", "polylines"), &PCGSplineData::set_polylines);
	ClassDB::bind_method(D_METHOD("distance_xz", "point"), &PCGSplineData::distance_xz);
	ClassDB::bind_static_method("PCGSplineData", D_METHOD("polyline_length", "points"), &PCGSplineData::polyline_length);
}

// --- Params ------------------------------------------------------------------------------------------------------

uint64_t PCGParamData::compute_content_hash() const {
	uint64_t h = pcg_mix64(0x5043475041ULL, (uint64_t)values.size());
	Array keys = values.keys();
	keys.sort();
	for (int i = 0; i < keys.size(); i++) {
		h = pcg_mix64(h, (uint64_t)String(keys[i]).hash());
		h = pcg_mix64(h, (uint64_t)values[keys[i]].hash());
	}
	return h;
}

void PCGParamData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_values", "values"), &PCGParamData::set_values);
	ClassDB::bind_method(D_METHOD("get_values"), &PCGParamData::get_values);
	ClassDB::bind_method(D_METHOD("set_value", "key", "value"), &PCGParamData::set_value);
	ClassDB::bind_method(D_METHOD("get_value", "key", "default"), &PCGParamData::get_value, DEFVAL(Variant()));
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "values"), "set_values", "get_values");
}

Dictionary PCGPointData::to_dictionary() const {
	Dictionary data;
	data["format"] = 1;
	data["positions"] = positions;
	data["normals"] = normals;
	data["density"] = density;
	data["yaw"] = yaw;
	data["scale"] = scale;
	data["seeds"] = seeds;
	data["attributes"] = attributes;
	return data;
}

Ref<PCGPointData> PCGPointData::from_dictionary(const Dictionary &p_data) {
	if (int(p_data.get("format", 0)) != 1) {
		return Ref<PCGPointData>();
	}
	Ref<PCGPointData> out;
	out.instantiate();
	out->positions = p_data.get("positions", PackedVector3Array());
	out->normals = p_data.get("normals", PackedVector3Array());
	out->density = p_data.get("density", PackedFloat32Array());
	out->yaw = p_data.get("yaw", PackedFloat32Array());
	out->scale = p_data.get("scale", PackedFloat32Array());
	out->seeds = p_data.get("seeds", PackedInt64Array());
	out->attributes = p_data.get("attributes", Dictionary());
	const int n = out->positions.size();
	if (out->normals.size() != n || out->density.size() != n || out->yaw.size() != n || out->scale.size() != n || out->seeds.size() != n) {
		return Ref<PCGPointData>();
	}
	Array keys = out->attributes.keys();
	for (int k = 0; k < keys.size(); k++) {
		if (out->attributes[keys[k]].get_type() != Variant::PACKED_FLOAT32_ARRAY || PackedFloat32Array(out->attributes[keys[k]]).size() != n) {
			return Ref<PCGPointData>();
		}
	}
	return out;
}
