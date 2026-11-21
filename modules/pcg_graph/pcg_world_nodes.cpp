/**************************************************************************/
/*  pcg_world_nodes.cpp                                                   */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_world_nodes.h"

#include "pcg_core_nodes.h"

#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/templates/sort_array.h"

#define PCGW_SETTER(m_class, m_type, m_name, m_expr) \
	void m_class::set_##m_name(m_type p_value) {     \
		m_name = m_expr;                             \
		emit_changed();                              \
	}

#define PCGW_BIND(m_class, m_name)                                                      \
	ClassDB::bind_method(D_METHOD("set_" #m_name, "value"), &m_class::set_##m_name); \
	ClassDB::bind_method(D_METHOD("get_" #m_name), &m_class::get_##m_name);

#define PCGW_PROP(m_type, m_name, m_hint, m_hint_string) \
	ADD_PROPERTY(PropertyInfo(m_type, #m_name, m_hint, m_hint_string), "set_" #m_name, "get_" #m_name);

namespace {

float rnd(uint64_t p_seed, uint64_t p_salt) {
	return float(pcg_rand01(pcg_mix64(p_seed, p_salt)));
}

// Order-independent per-point key: node seed + point seed + world position.
uint64_t point_key(const Ref<PCGPointData> &p_in, int p_index, uint64_t p_seed) {
	const Vector3 p = p_in->get_position(p_index);
	uint64_t h = pcg_mix64(p_seed, (uint64_t)p_in->get_seed(p_index));
	h = pcg_hash_double(h, p.x);
	return pcg_hash_double(h, p.z);
}

float slope_deg(const Ref<PCGContext> &p_context, float p_x, float p_z) {
	return Math::rad_to_deg(Math::acos(CLAMP(p_context->sample_normal(p_x, p_z).normalized().y, -1.0f, 1.0f)));
}

bool in_bounds_xz(const AABB &p_bounds, float p_x, float p_z) {
	return p_x >= p_bounds.position.x && p_x < p_bounds.position.x + p_bounds.size.x && p_z >= p_bounds.position.z && p_z < p_bounds.position.z + p_bounds.size.z;
}

float dist_xz(const Vector3 &p_a, const Vector3 &p_b) {
	const float dx = p_a.x - p_b.x;
	const float dz = p_a.z - p_b.z;
	return Math::sqrt(dx * dx + dz * dz);
}

int count_bands(const PackedFloat32Array &p_bands, float p_value) {
	int n = 0;
	for (int i = 0; i < p_bands.size(); i++) {
		if (p_value >= p_bands[i]) {
			n++;
		}
	}
	return n;
}

// Uniform grid of discs on XZ. find_overlap() returns the nearest disc closer than r + disc radius + gap.
struct PWHash {
	float cell = 1.0f;
	HashMap<Vector2i, LocalVector<int>> buckets;
	LocalVector<Vector3> pos;
	LocalVector<float> rad;
	float max_r = 0.0f;

	explicit PWHash(float p_cell) {
		cell = MAX(0.5f, p_cell);
	}
	Vector2i key(const Vector3 &p_position) const {
		return Vector2i((int)Math::floor(p_position.x / cell), (int)Math::floor(p_position.z / cell));
	}
	int insert(const Vector3 &p_position, float p_radius) {
		const int index = (int)pos.size();
		pos.push_back(p_position);
		rad.push_back(p_radius);
		max_r = MAX(max_r, p_radius);
		buckets[key(p_position)].push_back(index);
		return index;
	}
	int find_overlap(const Vector3 &p_position, float p_radius, float p_gap) const {
		const int reach = (int)Math::ceil((p_radius + max_r + p_gap) / cell);
		const Vector2i k = key(p_position);
		int best = -1;
		float best_d = Math::INF;
		for (int dz = -reach; dz <= reach; dz++) {
			for (int dx = -reach; dx <= reach; dx++) {
				const HashMap<Vector2i, LocalVector<int>>::ConstIterator E = buckets.find(Vector2i(k.x + dx, k.y + dz));
				if (!E) {
					continue;
				}
				for (uint32_t n = 0; n < E->value.size(); n++) {
					const int index = E->value[n];
					const float d = dist_xz(pos[index], p_position);
					if (d < p_radius + rad[index] + p_gap && d < best_d) {
						best = index;
						best_d = d;
					}
				}
			}
		}
		return best;
	}
	bool overlaps(const Vector3 &p_position, float p_radius, float p_gap) const {
		return find_overlap(p_position, p_radius, p_gap) >= 0;
	}
};

// Output builder: points plus attribute columns that are padded to one value per point.
struct PWOut {
	Ref<PCGPointData> data;
	HashMap<StringName, PackedFloat32Array> cols;
	int n = 0;

	PWOut() {
		data.instantiate();
	}
	void add(const Vector3 &p_position, const Vector3 &p_normal, float p_density, float p_yaw, float p_scale, int64_t p_seed) {
		data->add_point(p_position, p_normal, p_density, p_yaw, p_scale, p_seed);
		n++;
	}
	void set(const StringName &p_name, float p_value) {
		PackedFloat32Array &column = cols[p_name];
		while (column.size() < n) {
			column.push_back(0.0f);
		}
		column.set(n - 1, p_value);
	}
	Ref<PCGPointData> finish() {
		for (KeyValue<StringName, PackedFloat32Array> &E : cols) {
			while (E.value.size() < n) {
				E.value.push_back(0.0f);
			}
			data->set_attribute(E.key, E.value);
		}
		return data;
	}
};

// Points from input p_index, else from context.user_data[p_key] (Vector3 / {"position"} / PackedVector3Array).
PackedVector3Array source_positions(const Vector<Ref<PCGData>> &p_inputs, int p_index, const Ref<PCGContext> &p_context, const String &p_key) {
	PackedVector3Array out;
	if (p_index < p_inputs.size()) {
		Ref<PCGPointData> points = p_inputs[p_index];
		if (points.is_valid() && points->get_point_count() > 0) {
			return points->get_positions();
		}
	}
	const Variant value = p_context->get_user_data().get(p_key, Variant());
	if (value.get_type() == Variant::PACKED_VECTOR3_ARRAY) {
		return value;
	}
	if (value.get_type() == Variant::ARRAY) {
		const Array list = value;
		for (int i = 0; i < list.size(); i++) {
			if (list[i].get_type() == Variant::VECTOR3) {
				out.push_back(list[i]);
			} else if (list[i].get_type() == Variant::DICTIONARY) {
				const Dictionary entry = list[i];
				out.push_back(entry.get("position", Vector3()));
			}
		}
	}
	return out;
}

struct PWHeapEntry {
	float f;
	int node;
};

struct PWHeap {
	LocalVector<PWHeapEntry> v;

	static bool less(const PWHeapEntry &p_a, const PWHeapEntry &p_b) {
		if (p_a.f != p_b.f) {
			return p_a.f < p_b.f;
		}
		return p_a.node < p_b.node;
	}
	bool is_empty() const { return v.is_empty(); }
	void push(const PWHeapEntry &p_entry) {
		v.push_back(p_entry);
		int i = (int)v.size() - 1;
		while (i > 0) {
			const int parent = (i - 1) / 2;
			if (less(v[i], v[parent])) {
				SWAP(v[i], v[parent]);
				i = parent;
			} else {
				break;
			}
		}
	}
	PWHeapEntry pop() {
		const PWHeapEntry top = v[0];
		const PWHeapEntry last = v[v.size() - 1];
		v.resize(v.size() - 1);
		if (!v.is_empty()) {
			v[0] = last;
			int i = 0;
			const int size = (int)v.size();
			while (true) {
				const int l = i * 2 + 1;
				const int r = l + 1;
				int m = i;
				if (l < size && less(v[l], v[m])) {
					m = l;
				}
				if (r < size && less(v[r], v[m])) {
					m = r;
				}
				if (m == i) {
					break;
				}
				SWAP(v[i], v[m]);
				i = m;
			}
		}
		return top;
	}
};

} // namespace

// --- Roads -------------------------------------------------------------------------------------------------------

PackedVector3Array PCGRoadNetworkNode::route(int64_t p_seed, const Vector3 &p_from, const Vector3 &p_to, const Ref<PCGContext> &p_context, float p_grid_step, float p_slope_weight, float p_water_penalty) {
	PackedVector3Array out;
	ERR_FAIL_COND_V(p_context.is_null(), out);
	float s = MAX(0.5f, p_grid_step);
	const float distance = dist_xz(p_from, p_to);
	if (distance < 0.001f) {
		out.push_back(p_from);
		out.push_back(p_to);
		return out;
	}
	const float margin = MAX(s * 4.0f, distance * 0.4f);
	const float min_x = MIN(p_from.x, p_to.x) - margin;
	const float max_x = MAX(p_from.x, p_to.x) + margin;
	const float min_z = MIN(p_from.z, p_to.z) - margin;
	const float max_z = MAX(p_from.z, p_to.z) + margin;
	int nx = 0;
	int nz = 0;
	float ox = 0.0f;
	float oz = 0.0f;
	while (true) {
		ox = Math::floor(min_x / s) * s;
		oz = Math::floor(min_z / s) * s;
		nx = (int)Math::ceil((max_x - ox) / s) + 1;
		nz = (int)Math::ceil((max_z - oz) / s) + 1;
		if (int64_t(nx) * int64_t(nz) <= 160000) {
			break;
		}
		s *= 1.5f;
	}
	const int total = nx * nz;
	LocalVector<float> height;
	LocalVector<uint8_t> water;
	LocalVector<float> g_cost;
	LocalVector<int> parent;
	LocalVector<uint8_t> closed;
	height.resize(total);
	water.resize(total);
	g_cost.resize(total);
	parent.resize(total);
	closed.resize(total);
	for (int iz = 0; iz < nz; iz++) {
		for (int ix = 0; ix < nx; ix++) {
			const int n = iz * nx + ix;
			const float x = ox + ix * s;
			const float z = oz + iz * s;
			height[n] = p_context->sample_height(x, z);
			water[n] = p_context->sample_water(x, z) ? 1 : 0;
			g_cost[n] = Math::INF;
			parent[n] = -1;
			closed[n] = 0;
		}
	}
	const int start = CLAMP((int)Math::round((p_from.z - oz) / s), 0, nz - 1) * nx + CLAMP((int)Math::round((p_from.x - ox) / s), 0, nx - 1);
	const int goal = CLAMP((int)Math::round((p_to.z - oz) / s), 0, nz - 1) * nx + CLAMP((int)Math::round((p_to.x - ox) / s), 0, nx - 1);
	const int goal_x = goal % nx;
	const int goal_z = goal / nx;
	auto heuristic = [&](int p_node) {
		const float dx = float(p_node % nx - goal_x) * s;
		const float dz = float(p_node / nx - goal_z) * s;
		return Math::sqrt(dx * dx + dz * dz);
	};
	PWHeap heap;
	g_cost[start] = 0.0f;
	heap.push({ heuristic(start), start });
	bool reached = false;
	while (!heap.is_empty()) {
		const PWHeapEntry entry = heap.pop();
		const int node = entry.node;
		if (closed[node]) {
			continue;
		}
		closed[node] = 1;
		if (node == goal) {
			reached = true;
			break;
		}
		const int ix = node % nx;
		const int iz = node / nx;
		for (int dz = -1; dz <= 1; dz++) {
			for (int dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dz == 0) {
					continue;
				}
				const int jx = ix + dx;
				const int jz = iz + dz;
				if (jx < 0 || jz < 0 || jx >= nx || jz >= nz) {
					continue;
				}
				const int m = jz * nx + jx;
				if (closed[m]) {
					continue;
				}
				const float run = (dx != 0 && dz != 0) ? s * 1.41421356f : s;
				const float grade = Math::abs(height[m] - height[node]) / run;
				float cost = run * (1.0f + p_slope_weight * grade * grade);
				if (water[m]) {
					cost += run * p_water_penalty;
				}
				// Tiny seeded tie-breaker so equal-cost routes are stable but not axis-biased.
				cost += s * 0.02f * rnd(pcg_mix64((uint64_t)p_seed, (uint64_t)m), 7);
				const float candidate = g_cost[node] + cost;
				if (candidate < g_cost[m]) {
					g_cost[m] = candidate;
					parent[m] = node;
					heap.push({ candidate + heuristic(m), m });
				}
			}
		}
	}
	if (!reached) {
		out.push_back(p_from);
		out.push_back(p_to);
		return out;
	}
	LocalVector<int> path;
	for (int node = goal; node != -1; node = parent[node]) {
		path.push_back(node);
	}
	out.push_back(p_from);
	for (int k = (int)path.size() - 2; k >= 1; k--) {
		const int node = path[k];
		const float x = ox + (node % nx) * s;
		const float z = oz + (node / nx) * s;
		out.push_back(Vector3(x, height[node], z));
	}
	out.push_back(p_to);
	return out;
}

Ref<PCGData> PCGRoadNetworkNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGSplineData> out;
	out.instantiate();
	const PackedVector3Array sites = source_positions(p_inputs, 0, p_context, String(resolve("source_key", p_context)));
	const int n = sites.size();
	if (n < 2) {
		return out;
	}
	const float step = MAX(0.5f, float(resolve("grid_step", p_context)));
	const float slope_w = MAX(0.0f, float(resolve("slope_weight", p_context)));
	const float water_w = MAX(0.0f, float(resolve("water_penalty", p_context)));
	const float detour = float(resolve("loop_detour_ratio", p_context));
	const int extra_cap = MAX(0, int(resolve("max_extra_edges", p_context)));
	const float width = MAX(0.0f, float(resolve("road_width", p_context)));

	// Prim's minimum spanning tree (ties resolved by index, so deterministic).
	LocalVector<float> best;
	LocalVector<int> best_from;
	LocalVector<uint8_t> in_tree;
	for (int i = 0; i < n; i++) {
		best.push_back(Math::INF);
		best_from.push_back(-1);
		in_tree.push_back(0);
	}
	LocalVector<Vector2i> edges;
	LocalVector<uint8_t> adjacent;
	for (int i = 0; i < n * n; i++) {
		adjacent.push_back(0);
	}
	best[0] = 0.0f;
	for (int it = 0; it < n; it++) {
		int pick = -1;
		for (int i = 0; i < n; i++) {
			if (!in_tree[i] && (pick < 0 || best[i] < best[pick])) {
				pick = i;
			}
		}
		in_tree[pick] = 1;
		if (best_from[pick] >= 0) {
			edges.push_back(Vector2i(best_from[pick], pick));
			adjacent[best_from[pick] * n + pick] = 1;
			adjacent[pick * n + best_from[pick]] = 1;
		}
		for (int i = 0; i < n; i++) {
			if (!in_tree[i]) {
				const float d = dist_xz(sites[pick], sites[i]);
				if (d < best[i]) {
					best[i] = d;
					best_from[i] = pick;
				}
			}
		}
	}

	// Optional loop edges: short non-tree pairs whose current graph detour is long.
	if (detour > 1.0f && extra_cap > 0) {
		struct Pair {
			float d;
			int i;
			int j;
		};
		struct PairOrder {
			bool operator()(const Pair &p_a, const Pair &p_b) const {
				if (p_a.d != p_b.d) {
					return p_a.d < p_b.d;
				}
				if (p_a.i != p_b.i) {
					return p_a.i < p_b.i;
				}
				return p_a.j < p_b.j;
			}
		};
		LocalVector<Pair> pairs;
		for (int i = 0; i < n; i++) {
			for (int j = i + 1; j < n; j++) {
				if (!adjacent[i * n + j]) {
					pairs.push_back({ dist_xz(sites[i], sites[j]), i, j });
				}
			}
		}
		SortArray<Pair, PairOrder> pair_sort;
		pair_sort.sort(pairs.ptr(), pairs.size());
		int added = 0;
		const uint32_t limit = MIN(pairs.size(), (uint32_t)64);
		for (uint32_t k = 0; k < limit && added < extra_cap; k++) {
			const Pair pr = pairs[k];
			LocalVector<float> graph_d;
			for (int i = 0; i < n; i++) {
				graph_d.push_back(i == pr.i ? 0.0f : Math::INF);
			}
			for (int pass = 0; pass < n; pass++) {
				bool changed = false;
				for (uint32_t e = 0; e < edges.size(); e++) {
					const float w = dist_xz(sites[edges[e].x], sites[edges[e].y]);
					if (graph_d[edges[e].x] + w < graph_d[edges[e].y]) {
						graph_d[edges[e].y] = graph_d[edges[e].x] + w;
						changed = true;
					}
					if (graph_d[edges[e].y] + w < graph_d[edges[e].x]) {
						graph_d[edges[e].x] = graph_d[edges[e].y] + w;
						changed = true;
					}
				}
				if (!changed) {
					break;
				}
			}
			if (graph_d[pr.j] > detour * pr.d) {
				edges.push_back(Vector2i(pr.i, pr.j));
				adjacent[pr.i * n + pr.j] = 1;
				adjacent[pr.j * n + pr.i] = 1;
				added++;
			}
		}
	}

	for (uint32_t e = 0; e < edges.size(); e++) {
		const int a = edges[e].x;
		const int b = edges[e].y;
		const uint64_t edge_seed = pcg_mix64(pcg_mix64(p_seed, (uint64_t)a), (uint64_t)b);
		out->add_polyline(route((int64_t)edge_seed, sites[a], sites[b], p_context, step, slope_w, water_w), width);
	}
	return out;
}

PCGW_SETTER(PCGRoadNetworkNode, String, source_key, p_value)
PCGW_SETTER(PCGRoadNetworkNode, float, grid_step, MAX(0.5f, p_value))
PCGW_SETTER(PCGRoadNetworkNode, float, slope_weight, MAX(0.0f, p_value))
PCGW_SETTER(PCGRoadNetworkNode, float, water_penalty, MAX(0.0f, p_value))
PCGW_SETTER(PCGRoadNetworkNode, float, loop_detour_ratio, MAX(0.0f, p_value))
PCGW_SETTER(PCGRoadNetworkNode, int, max_extra_edges, MAX(0, p_value))
PCGW_SETTER(PCGRoadNetworkNode, float, road_width, MAX(0.0f, p_value))

void PCGRoadNetworkNode::_bind_methods() {
	PCGW_BIND(PCGRoadNetworkNode, source_key)
	PCGW_BIND(PCGRoadNetworkNode, grid_step)
	PCGW_BIND(PCGRoadNetworkNode, slope_weight)
	PCGW_BIND(PCGRoadNetworkNode, water_penalty)
	PCGW_BIND(PCGRoadNetworkNode, loop_detour_ratio)
	PCGW_BIND(PCGRoadNetworkNode, max_extra_edges)
	PCGW_BIND(PCGRoadNetworkNode, road_width)
	ClassDB::bind_static_method("PCGRoadNetworkNode", D_METHOD("route", "seed", "from", "to", "context", "grid_step", "slope_weight", "water_penalty"), &PCGRoadNetworkNode::route, DEFVAL(10.0), DEFVAL(20.0));
	PCGW_PROP(Variant::STRING, source_key, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::FLOAT, grid_step, PROPERTY_HINT_RANGE, "0.5,64,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, slope_weight, PROPERTY_HINT_RANGE, "0,100,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, water_penalty, PROPERTY_HINT_RANGE, "0,100,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, loop_detour_ratio, PROPERTY_HINT_RANGE, "0,10,0.05,or_greater")
	PCGW_PROP(Variant::INT, max_extra_edges, PROPERTY_HINT_RANGE, "0,64,1,or_greater")
	PCGW_PROP(Variant::FLOAT, road_width, PROPERTY_HINT_RANGE, "0,64,0.1,or_greater")
}

// --- Rivers ------------------------------------------------------------------------------------------------------

Ref<PCGData> PCGRiverNetworkNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGSplineData> out;
	out.instantiate();
	const float sp = MAX(2.0f, float(resolve("source_spacing", p_context)));
	const float h_min = resolve("min_source_height", p_context);
	const int source_cap = MAX(0, int(resolve("max_sources", p_context)));
	const float step = MAX(0.5f, float(resolve("step_length", p_context)));
	const float length_cap = MAX(step * 2.0f, float(resolve("max_length", p_context)));
	const float mom = CLAMP(float(resolve("momentum", p_context)), 0.0f, 0.9f);
	const float merge_r = MAX(0.0f, float(resolve("merge_radius", p_context)));
	const float fill_depth = MAX(0.0f, float(resolve("max_fill_depth", p_context)));
	const float w_base = MAX(0.0f, float(resolve("base_width", p_context)));
	const float w_grow = MAX(0.0f, float(resolve("width_growth", p_context)));
	const AABB bounds = p_context->get_bounds();
	const int x0 = (int)Math::floor(bounds.position.x / sp) - 1;
	const int x1 = (int)Math::ceil((bounds.position.x + bounds.size.x) / sp) + 1;
	const int z0 = (int)Math::floor(bounds.position.z / sp) - 1;
	const int z1 = (int)Math::ceil((bounds.position.z + bounds.size.z) / sp) + 1;
	ERR_FAIL_COND_V_MSG(int64_t(x1 - x0) * int64_t(z1 - z0) > 1000000, out, "PCG river network: source_spacing too small for the bounds.");

	struct Source {
		float h;
		int ix;
		int iz;
	};
	struct SourceOrder {
		bool operator()(const Source &p_a, const Source &p_b) const {
			if (p_a.h != p_b.h) {
				return p_a.h > p_b.h;
			}
			if (p_a.iz != p_b.iz) {
				return p_a.iz < p_b.iz;
			}
			return p_a.ix < p_b.ix;
		}
	};
	LocalVector<Source> sources;
	for (int iz = z0; iz <= z1; iz++) {
		for (int ix = x0; ix <= x1; ix++) {
			const float x = (ix + 0.5f) * sp;
			const float z = (iz + 0.5f) * sp;
			if (!in_bounds_xz(bounds, x, z)) {
				continue;
			}
			const float h = p_context->sample_height(x, z);
			if (h < h_min || p_context->sample_water(x, z)) {
				continue;
			}
			bool is_max = true;
			for (int dz = -1; dz <= 1 && is_max; dz++) {
				for (int dx = -1; dx <= 1; dx++) {
					if (dx == 0 && dz == 0) {
						continue;
					}
					const float nh = p_context->sample_height(x + dx * sp, z + dz * sp);
					if (nh > h || (nh == h && (dz < 0 || (dz == 0 && dx < 0)))) {
						is_max = false;
						break;
					}
				}
			}
			if (is_max) {
				sources.push_back({ h, ix, iz });
			}
		}
	}
	SortArray<Source, SourceOrder> source_sort;
	source_sort.sort(sources.ptr(), sources.size());

	Vector<PackedVector3Array> river_pts;
	Vector<int> river_parent;
	Vector<int> river_parent_vertex;
	PWHash grid(MAX(1.0f, merge_r));
	LocalVector<Vector2i> grid_info;
	const int max_steps = (int)(length_cap / step);
	auto hf = [&](float p_x, float p_z) { return p_context->sample_height(p_x, p_z); };

	for (uint32_t si = 0; si < sources.size() && (int)si < source_cap; si++) {
		Vector2 pos((sources[si].ix + 0.5f) * sp, (sources[si].iz + 0.5f) * sp);
		Vector2 dir;
		float level = hf(pos.x, pos.y);
		PackedVector3Array line;
		line.push_back(Vector3(pos.x, level, pos.y));
		int parent_river = -1;
		int parent_vertex = -1;
		for (int s = 0; s < max_steps; s++) {
			const float e = step * 0.5f;
			const Vector2 grad((hf(pos.x + e, pos.y) - hf(pos.x - e, pos.y)) / (2.0f * e), (hf(pos.x, pos.y + e) - hf(pos.x, pos.y - e)) / (2.0f * e));
			Vector2 want = -grad;
			if (want.length_squared() < 1e-8f) {
				if (dir.length_squared() < 1e-8f) {
					break;
				}
				want = dir;
			} else {
				want = want.normalized();
			}
			Vector2 heading = dir * mom + want * (1.0f - mom);
			heading = heading.length_squared() < 1e-8f ? want : heading.normalized();
			const Vector2 next = pos + heading * step;
			const float next_h = hf(next.x, next.y);
			if (next_h > level + 0.001f) {
				// Pit: look along 16 rays for the lowest rim that leads to ground below the pond level.
				int best_k = 0;
				float best_rim = Math::INF;
				Vector2 best_dir;
				for (int d = 0; d < 16; d++) {
					const float angle = d * float(Math::TAU) / 16.0f;
					const Vector2 dv(Math::sin(angle), Math::cos(angle));
					float rim = -Math::INF;
					int found = 0;
					for (int k = 1; k <= 12; k++) {
						const float hq = hf(pos.x + dv.x * step * k, pos.y + dv.y * step * k);
						rim = MAX(rim, hq);
						if (rim > level + fill_depth) {
							break;
						}
						if (hq < level - 0.01f) {
							found = k;
							break;
						}
					}
					if (found > 0 && rim < best_rim) {
						best_rim = rim;
						best_k = found;
						best_dir = dv;
					}
				}
				if (best_k == 0) {
					break;
				}
				for (int k = 1; k <= best_k; k++) {
					const Vector2 q = pos + best_dir * step * float(k);
					const float y = k == best_k ? MIN(level, hf(q.x, q.y)) : level;
					line.push_back(Vector3(q.x, y, q.y));
					if (k == best_k) {
						pos = q;
						level = y;
					}
				}
				dir = best_dir;
			} else {
				const float y = MIN(level, next_h);
				line.push_back(Vector3(next.x, y, next.y));
				pos = next;
				level = y;
				dir = heading;
			}
			if (p_context->sample_water(pos.x, pos.y) || !in_bounds_xz(bounds, pos.x, pos.y)) {
				break;
			}
			if (merge_r > 0.0f && line.size() >= 4) {
				const int hit = grid.find_overlap(Vector3(pos.x, 0, pos.y), 0.0f, merge_r);
				if (hit >= 0) {
					parent_river = grid_info[hit].x;
					parent_vertex = grid_info[hit].y;
					const Vector3 pv = river_pts[parent_river][parent_vertex];
					line.push_back(Vector3(pv.x, MIN(level, pv.y), pv.z));
					break;
				}
			}
		}
		if (line.size() < 2) {
			continue;
		}
		const int river_index = river_pts.size();
		for (int v = 0; v < line.size(); v++) {
			grid.insert(Vector3(line[v].x, 0, line[v].z), 0.0f);
			grid_info.push_back(Vector2i(river_index, v));
		}
		river_pts.push_back(line);
		river_parent.push_back(parent_river);
		river_parent_vertex.push_back(parent_vertex);
	}

	// Drainage accumulates downstream: children are traced after their parent, so walk in reverse.
	const int river_count = river_pts.size();
	Vector<PackedFloat32Array> inject;
	Vector<PackedFloat32Array> flows;
	for (int r = 0; r < river_count; r++) {
		PackedFloat32Array zeros;
		for (int v = 0; v < river_pts[r].size(); v++) {
			zeros.push_back(0.0f);
		}
		inject.push_back(zeros);
		flows.push_back(PackedFloat32Array());
	}
	for (int r = river_count - 1; r >= 0; r--) {
		PackedFloat32Array flow;
		float acc = 0.0f;
		for (int v = 0; v < river_pts[r].size(); v++) {
			acc += 1.0f + inject[r][v];
			flow.push_back(acc);
		}
		flows.set(r, flow);
		if (river_parent[r] >= 0) {
			PackedFloat32Array up = inject[river_parent[r]];
			up.set(river_parent_vertex[r], up[river_parent_vertex[r]] + acc);
			inject.set(river_parent[r], up);
		}
	}
	for (int r = 0; r < river_count; r++) {
		const PackedVector3Array line = river_pts[r];
		const PackedFloat32Array flow = flows[r];
		auto quantized = [&](int p_vertex) {
			return Math::round((w_base + w_grow * Math::sqrt(flow[p_vertex])) * 2.0f) * 0.5f;
		};
		int a = 0;
		float q = quantized(0);
		for (int v = 1; v < line.size(); v++) {
			const float qv = quantized(v);
			if (qv != q || v == line.size() - 1) {
				PackedVector3Array chunk;
				for (int k = a; k <= v; k++) {
					chunk.push_back(line[k]);
				}
				out->add_polyline(chunk, q);
				a = v;
				q = qv;
			}
		}
	}
	return out;
}

PCGW_SETTER(PCGRiverNetworkNode, float, source_spacing, MAX(2.0f, p_value))
PCGW_SETTER(PCGRiverNetworkNode, float, min_source_height, p_value)
PCGW_SETTER(PCGRiverNetworkNode, int, max_sources, MAX(0, p_value))
PCGW_SETTER(PCGRiverNetworkNode, float, step_length, MAX(0.5f, p_value))
PCGW_SETTER(PCGRiverNetworkNode, float, max_length, MAX(1.0f, p_value))
PCGW_SETTER(PCGRiverNetworkNode, float, momentum, CLAMP(p_value, 0.0f, 0.9f))
PCGW_SETTER(PCGRiverNetworkNode, float, merge_radius, MAX(0.0f, p_value))
PCGW_SETTER(PCGRiverNetworkNode, float, max_fill_depth, MAX(0.0f, p_value))
PCGW_SETTER(PCGRiverNetworkNode, float, base_width, MAX(0.0f, p_value))
PCGW_SETTER(PCGRiverNetworkNode, float, width_growth, MAX(0.0f, p_value))

void PCGRiverNetworkNode::_bind_methods() {
	PCGW_BIND(PCGRiverNetworkNode, source_spacing)
	PCGW_BIND(PCGRiverNetworkNode, min_source_height)
	PCGW_BIND(PCGRiverNetworkNode, max_sources)
	PCGW_BIND(PCGRiverNetworkNode, step_length)
	PCGW_BIND(PCGRiverNetworkNode, max_length)
	PCGW_BIND(PCGRiverNetworkNode, momentum)
	PCGW_BIND(PCGRiverNetworkNode, merge_radius)
	PCGW_BIND(PCGRiverNetworkNode, max_fill_depth)
	PCGW_BIND(PCGRiverNetworkNode, base_width)
	PCGW_BIND(PCGRiverNetworkNode, width_growth)
	PCGW_PROP(Variant::FLOAT, source_spacing, PROPERTY_HINT_RANGE, "2,512,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, min_source_height, PROPERTY_HINT_RANGE, "-1000,10000,0.5,or_greater,or_less")
	PCGW_PROP(Variant::INT, max_sources, PROPERTY_HINT_RANGE, "0,256,1,or_greater")
	PCGW_PROP(Variant::FLOAT, step_length, PROPERTY_HINT_RANGE, "0.5,32,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, max_length, PROPERTY_HINT_RANGE, "1,10000,1,or_greater")
	PCGW_PROP(Variant::FLOAT, momentum, PROPERTY_HINT_RANGE, "0,0.9,0.01")
	PCGW_PROP(Variant::FLOAT, merge_radius, PROPERTY_HINT_RANGE, "0,64,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, max_fill_depth, PROPERTY_HINT_RANGE, "0,64,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, base_width, PROPERTY_HINT_RANGE, "0,64,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, width_growth, PROPERTY_HINT_RANGE, "0,16,0.01,or_greater")
}

// --- Settlements -------------------------------------------------------------------------------------------------

Ref<PCGData> PCGSettlementNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	PWOut out;
	const PackedVector3Array centers = source_positions(p_inputs, 0, p_context, String(resolve("source_key", p_context)));
	Ref<PCGSplineData> roads;
	if (p_inputs.size() > 1) {
		roads = p_inputs[1];
	}
	const bool has_roads = roads.is_valid() && roads->get_polyline_count() > 0;
	const int lot_cap = MAX(0, int(resolve("max_lots", p_context)));
	const float area = MAX(4.0f, float(resolve("radius", p_context)));
	const float slope_cap = resolve("max_slope", p_context);
	const float margin = MAX(0.0f, float(resolve("road_margin", p_context)));
	const float fp_min = MAX(2.0f, float(resolve("min_footprint", p_context)));
	const float fp_max = MAX(fp_min, float(resolve("max_footprint", p_context)));
	const float workshop_p = CLAMP(float(resolve("workshop_chance", p_context)), 0.0f, 1.0f);
	const float wall_r = MAX(0.0f, float(resolve("wall_radius", p_context)));
	const float post_gap = MAX(2.0f, float(resolve("wall_post_spacing", p_context)));
	const AABB bounds = p_context->get_bounds();
	float max_half = 0.0f;
	if (has_roads) {
		for (int l = 0; l < roads->get_polyline_count(); l++) {
			max_half = MAX(max_half, roads->get_width(l) * 0.5f);
		}
	}
	PWHash lots(fp_max * 1.5f);

	for (int c = 0; c < centers.size(); c++) {
		const Vector3 center = centers[c];
		const uint64_t cseed = pcg_hash_double(pcg_hash_double(pcg_mix64(p_seed, (uint64_t)c), center.x), center.z);
		uint64_t cand = 0;
		int accepted = 0;
		auto place = [&](float p_x, float p_z, float p_yaw, int p_kind, float p_fx, float p_fz, bool p_road_check, bool p_solid) -> bool {
			cand++;
			const float r = 0.5f * Math::sqrt(p_fx * p_fx + p_fz * p_fz);
			if (!in_bounds_xz(bounds, p_x, p_z) || p_context->sample_water(p_x, p_z)) {
				return false;
			}
			if (slope_deg(p_context, p_x, p_z) > slope_cap) {
				return false;
			}
			if (p_road_check && has_roads && roads->distance_xz(Vector3(p_x, 0, p_z)) < max_half + margin + 0.5f * MIN(p_fx, p_fz)) {
				return false;
			}
			if (p_solid) {
				if (lots.overlaps(Vector3(p_x, 0, p_z), r, 1.0f)) {
					return false;
				}
				lots.insert(Vector3(p_x, 0, p_z), r);
			}
			out.add(Vector3(p_x, p_context->sample_height(p_x, p_z), p_z), p_context->sample_normal(p_x, p_z), 1.0f, p_yaw, 1.0f, (int64_t)pcg_mix64(cseed, cand));
			out.set("footprint_x", p_fx);
			out.set("footprint_z", p_fz);
			out.set("kind", (float)p_kind);
			out.set("settlement", (float)c);
			return true;
		};
		auto roll_lot = [&](uint64_t p_salt, int *r_kind, float *r_fx, float *r_fz) {
			const uint64_t k = pcg_mix64(cseed, p_salt);
			*r_kind = rnd(k, 1) < workshop_p ? KIND_WORKSHOP : KIND_HOUSE;
			const float scale = *r_kind == KIND_WORKSHOP ? 1.4f : 1.0f;
			*r_fx = Math::lerp(fp_min, fp_max, rnd(k, 2)) * scale;
			*r_fz = Math::lerp(fp_min, fp_max, rnd(k, 3)) * scale;
		};

		place(center.x, center.z, 0.0f, KIND_WELL, 2.5f, 2.5f, false, true);

		// Road-front lots first.
		if (has_roads) {
			const float road_step = fp_max + 3.0f;
			for (int l = 0; l < roads->get_polyline_count() && accepted < lot_cap; l++) {
				const PackedVector3Array line = roads->get_polyline(l);
				const float half = roads->get_width(l) * 0.5f;
				float travelled = 0.0f;
				float next = road_step * 0.5f;
				for (int s = 1; s < line.size() && accepted < lot_cap; s++) {
					const Vector3 a = line[s - 1];
					const Vector3 b = line[s];
					const float len = dist_xz(a, b);
					if (len <= 0.0001f) {
						continue;
					}
					const Vector3 dir = (b - a) / len;
					const Vector3 side(-dir.z, 0, dir.x);
					while (next <= travelled + len && accepted < lot_cap) {
						const Vector3 base = a + dir * (next - travelled);
						next += road_step;
						if (dist_xz(base, center) > area) {
							continue;
						}
						for (int sign = 1; sign >= -1 && accepted < lot_cap; sign -= 2) {
							int kind;
							float fx;
							float fz;
							roll_lot(cand + 1, &kind, &fx, &fz);
							const float off = half + margin + 0.5f * MIN(fx, fz) + 0.6f;
							const Vector3 p = base + side * float(sign) * off;
							const float yaw = Math::atan2(-side.x * sign, -side.z * sign);
							if (place(p.x, p.z, yaw, kind, fx, fz, true, true)) {
								accepted++;
							}
						}
					}
					travelled += len;
				}
			}
		}

		// Rings of lots facing the center.
		const float ring_gap = fp_max + 4.0f;
		for (int k = 1; k * ring_gap <= area && accepted < lot_cap; k++) {
			const float R = k * ring_gap;
			const int count = MAX(3, (int)Math::floor(float(Math::TAU) * R / (fp_max + 2.0f)));
			const float phase = rnd(pcg_mix64(cseed, 1000 + k), 5) * float(Math::TAU);
			for (int q = 0; q < count && accepted < lot_cap; q++) {
				const uint64_t kk = pcg_mix64(cseed, 5000 + (uint64_t)k * 1000 + q);
				const float angle = phase + q * float(Math::TAU) / count;
				const float rr = R * (1.0f + (rnd(kk, 9) - 0.5f) * 0.1f);
				int kind;
				float fx;
				float fz;
				roll_lot(kk, &kind, &fx, &fz);
				const float x = center.x + Math::sin(angle) * rr;
				const float z = center.z + Math::cos(angle) * rr;
				if (place(x, z, angle + float(Math::PI), kind, fx, fz, true, true)) {
					accepted++;
				}
			}
		}

		// Optional palisade: wall posts on a ring, leaving gaps where roads pass.
		if (wall_r > 0.0f) {
			const int count = MAX(6, (int)Math::floor(float(Math::TAU) * wall_r / post_gap));
			for (int q = 0; q < count; q++) {
				const float angle = q * float(Math::TAU) / count;
				const float x = center.x + Math::sin(angle) * wall_r;
				const float z = center.z + Math::cos(angle) * wall_r;
				if (has_roads && roads->distance_xz(Vector3(x, 0, z)) < max_half + 1.5f) {
					continue;
				}
				place(x, z, angle, KIND_WALL_POST, 1.0f, 1.0f, false, false);
			}
		}
	}
	return out.finish();
}

PCGW_SETTER(PCGSettlementNode, String, source_key, p_value)
PCGW_SETTER(PCGSettlementNode, int, max_lots, MAX(0, p_value))
PCGW_SETTER(PCGSettlementNode, float, radius, MAX(4.0f, p_value))
PCGW_SETTER(PCGSettlementNode, float, max_slope, CLAMP(p_value, 0.0f, 90.0f))
PCGW_SETTER(PCGSettlementNode, float, road_margin, MAX(0.0f, p_value))
PCGW_SETTER(PCGSettlementNode, float, min_footprint, MAX(2.0f, p_value))
PCGW_SETTER(PCGSettlementNode, float, max_footprint, MAX(2.0f, p_value))
PCGW_SETTER(PCGSettlementNode, float, workshop_chance, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGSettlementNode, float, wall_radius, MAX(0.0f, p_value))
PCGW_SETTER(PCGSettlementNode, float, wall_post_spacing, MAX(2.0f, p_value))

void PCGSettlementNode::_bind_methods() {
	PCGW_BIND(PCGSettlementNode, source_key)
	PCGW_BIND(PCGSettlementNode, max_lots)
	PCGW_BIND(PCGSettlementNode, radius)
	PCGW_BIND(PCGSettlementNode, max_slope)
	PCGW_BIND(PCGSettlementNode, road_margin)
	PCGW_BIND(PCGSettlementNode, min_footprint)
	PCGW_BIND(PCGSettlementNode, max_footprint)
	PCGW_BIND(PCGSettlementNode, workshop_chance)
	PCGW_BIND(PCGSettlementNode, wall_radius)
	PCGW_BIND(PCGSettlementNode, wall_post_spacing)
	PCGW_PROP(Variant::STRING, source_key, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::INT, max_lots, PROPERTY_HINT_RANGE, "0,256,1,or_greater")
	PCGW_PROP(Variant::FLOAT, radius, PROPERTY_HINT_RANGE, "4,512,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, max_slope, PROPERTY_HINT_RANGE, "0,90,0.5")
	PCGW_PROP(Variant::FLOAT, road_margin, PROPERTY_HINT_RANGE, "0,32,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, min_footprint, PROPERTY_HINT_RANGE, "2,64,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, max_footprint, PROPERTY_HINT_RANGE, "2,64,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, workshop_chance, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::FLOAT, wall_radius, PROPERTY_HINT_RANGE, "0,512,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, wall_post_spacing, PROPERTY_HINT_RANGE, "2,64,0.5,or_greater")
}

// --- City --------------------------------------------------------------------------------------------------------

Array PCGCityNode::layout_blocks(int64_t p_seed, const Rect2 &p_rect, float p_block_size, float p_street_width) {
	Array blocks;
	const float size = MAX(2.0f, p_block_size);
	const float half_street = MAX(0.0f, p_street_width) * 0.5f;
	const int cols = MAX(1, (int)Math::floor(p_rect.size.x / size));
	const int rows = MAX(1, (int)Math::floor(p_rect.size.y / size));
	LocalVector<float> xs;
	LocalVector<float> zs;
	for (int i = 0; i <= cols; i++) {
		float x = p_rect.position.x + p_rect.size.x * float(i) / float(cols);
		if (i > 0 && i < cols) {
			x += (rnd((uint64_t)p_seed, 0x5800 + i) - 0.5f) * 0.3f * (p_rect.size.x / cols);
		}
		xs.push_back(x);
	}
	for (int j = 0; j <= rows; j++) {
		float z = p_rect.position.y + p_rect.size.y * float(j) / float(rows);
		if (j > 0 && j < rows) {
			z += (rnd((uint64_t)p_seed, 0x5A00 + j) - 0.5f) * 0.3f * (p_rect.size.y / rows);
		}
		zs.push_back(z);
	}
	for (int j = 0; j < rows; j++) {
		for (int i = 0; i < cols; i++) {
			const Vector2 pos(xs[i] + half_street, zs[j] + half_street);
			const Vector2 sz(xs[i + 1] - xs[i] - half_street * 2.0f, zs[j + 1] - zs[j] - half_street * 2.0f);
			if (sz.x >= 1.0f && sz.y >= 1.0f) {
				blocks.push_back(Rect2(pos, sz));
			}
		}
	}
	return blocks;
}

Ref<PCGData> PCGCityNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	PWOut out;
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const AABB bounds = p_context->get_bounds();
	PackedVector3Array centers = in->get_positions();
	if (centers.is_empty()) {
		centers.push_back(bounds.get_center());
	}
	const int mode = resolve("layout", p_context);
	const float half = MAX(8.0f, float(resolve("half_extent", p_context)));
	const float block = MAX(4.0f, float(resolve("block_size", p_context)));
	const float street = MAX(0.0f, float(resolve("street_width", p_context)));
	const float lot = MAX(3.0f, float(resolve("lot_size", p_context)));
	const float core_r = float(resolve("core_radius", p_context));
	const float res_r = float(resolve("residential_radius", p_context));
	const float slope_cap = resolve("max_slope", p_context);

	for (int c = 0; c < centers.size(); c++) {
		const Vector3 center = centers[c];
		const uint64_t cseed = pcg_hash_double(pcg_hash_double(pcg_mix64(p_seed, (uint64_t)c), center.x), center.z);
		uint64_t counter = 0;
		auto emit = [&](float p_x, float p_z, float p_yaw, float p_fx, float p_fz, int p_block) {
			counter++;
			if (!in_bounds_xz(bounds, p_x, p_z) || p_context->sample_water(p_x, p_z) || slope_deg(p_context, p_x, p_z) > slope_cap) {
				return;
			}
			const float d = dist_xz(Vector3(p_x, 0, p_z), center);
			const int district = d < core_r ? 0 : (d < res_r ? 1 : 2);
			out.add(Vector3(p_x, p_context->sample_height(p_x, p_z), p_z), p_context->sample_normal(p_x, p_z), 1.0f, p_yaw, 1.0f, (int64_t)pcg_mix64(cseed, counter));
			out.set("footprint_x", p_fx);
			out.set("footprint_z", p_fz);
			out.set("district", (float)district);
			out.set("block", (float)p_block);
		};
		if (mode == 1) {
			// Radial: concentric streets, lots on every ring, facing outward.
			const int rings = (int)Math::floor(half / block);
			for (int k = 1; k <= rings; k++) {
				const float R = k * block;
				const int count = MAX(6, (int)Math::floor(float(Math::TAU) * R / lot));
				const float arc = float(Math::TAU) * R / count;
				const float depth = CLAMP(block - street, 3.0f, lot * 1.5f);
				for (int q = 0; q < count; q++) {
					const float angle = q * float(Math::TAU) / count;
					emit(center.x + Math::sin(angle) * R, center.z + Math::cos(angle) * R, angle, MAX(2.0f, arc * 0.85f), depth, k);
				}
			}
		} else {
			const Rect2 rect(Vector2(center.x - half, center.z - half), Vector2(half * 2.0f, half * 2.0f));
			const Array blocks = layout_blocks((int64_t)cseed, rect, block, street);
			for (int b = 0; b < blocks.size(); b++) {
				const Rect2 br = blocks[b];
				const Vector2 mid = br.get_center();
				const float bd = dist_xz(Vector3(mid.x, 0, mid.y), center);
				const float scale = bd < core_r ? 0.75f : (bd < res_r ? 1.0f : 1.6f);
				const float gap = bd < core_r ? 0.8f : 1.5f;
				const float cell = lot * scale;
				const int nx = MAX(1, (int)Math::floor(br.size.x / cell));
				const int nz = MAX(1, (int)Math::floor(br.size.y / cell));
				const float cw = br.size.x / nx;
				const float ch = br.size.y / nz;
				for (int j = 0; j < nz; j++) {
					for (int i = 0; i < nx; i++) {
						const float x = br.position.x + (i + 0.5f) * cw;
						const float z = br.position.y + (j + 0.5f) * ch;
						// Face the nearest street (outward from the block center).
						const float dx = x - mid.x;
						const float dz = z - mid.y;
						float yaw;
						if (Math::abs(dx) * br.size.y > Math::abs(dz) * br.size.x) {
							yaw = dx > 0.0f ? float(Math::PI) * 0.5f : -float(Math::PI) * 0.5f;
						} else {
							yaw = dz > 0.0f ? 0.0f : float(Math::PI);
						}
						emit(x, z, yaw, MAX(1.0f, cw - gap), MAX(1.0f, ch - gap), b);
					}
				}
			}
		}
	}
	return out.finish();
}

PCGW_SETTER(PCGCityNode, int, layout, CLAMP(p_value, 0, 1))
PCGW_SETTER(PCGCityNode, float, half_extent, MAX(8.0f, p_value))
PCGW_SETTER(PCGCityNode, float, block_size, MAX(4.0f, p_value))
PCGW_SETTER(PCGCityNode, float, street_width, MAX(0.0f, p_value))
PCGW_SETTER(PCGCityNode, float, lot_size, MAX(3.0f, p_value))
PCGW_SETTER(PCGCityNode, float, core_radius, MAX(0.0f, p_value))
PCGW_SETTER(PCGCityNode, float, residential_radius, MAX(0.0f, p_value))
PCGW_SETTER(PCGCityNode, float, max_slope, CLAMP(p_value, 0.0f, 90.0f))

void PCGCityNode::_bind_methods() {
	PCGW_BIND(PCGCityNode, layout)
	PCGW_BIND(PCGCityNode, half_extent)
	PCGW_BIND(PCGCityNode, block_size)
	PCGW_BIND(PCGCityNode, street_width)
	PCGW_BIND(PCGCityNode, lot_size)
	PCGW_BIND(PCGCityNode, core_radius)
	PCGW_BIND(PCGCityNode, residential_radius)
	PCGW_BIND(PCGCityNode, max_slope)
	ClassDB::bind_static_method("PCGCityNode", D_METHOD("layout_blocks", "seed", "rect", "block_size", "street_width"), &PCGCityNode::layout_blocks);
	PCGW_PROP(Variant::INT, layout, PROPERTY_HINT_ENUM, "Grid,Radial")
	PCGW_PROP(Variant::FLOAT, half_extent, PROPERTY_HINT_RANGE, "8,2048,1,or_greater")
	PCGW_PROP(Variant::FLOAT, block_size, PROPERTY_HINT_RANGE, "4,256,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, street_width, PROPERTY_HINT_RANGE, "0,64,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, lot_size, PROPERTY_HINT_RANGE, "3,64,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, core_radius, PROPERTY_HINT_RANGE, "0,2048,1,or_greater")
	PCGW_PROP(Variant::FLOAT, residential_radius, PROPERTY_HINT_RANGE, "0,2048,1,or_greater")
	PCGW_PROP(Variant::FLOAT, max_slope, PROPERTY_HINT_RANGE, "0,90,0.5")
}

// --- Buildings ---------------------------------------------------------------------------------------------------

Ref<PCGData> PCGBuildingNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	PWOut out;
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const int floor_cap = MAX(1, int(resolve("max_floors", p_context)));
	const float module = MAX(0.5f, float(resolve("module_size", p_context)));
	const float fh = MAX(0.5f, float(resolve("floor_height", p_context)));
	const float window_p = CLAMP(float(resolve("window_chance", p_context)), 0.0f, 1.0f);
	const float default_fp = MAX(module, float(resolve("default_footprint", p_context)));

	for (int i = 0; i < in->get_point_count(); i++) {
		const uint64_t key = point_key(in, i, p_seed);
		float fx = in->get_attribute_value("footprint_x", i, default_fp);
		float fz = in->get_attribute_value("footprint_z", i, default_fp);
		fx = fx > 0.0f ? fx : default_fp;
		fz = fz > 0.0f ? fz : default_fp;
		const Vector3 base = in->get_position(i);
		const float yaw = in->get_yaw(i);
		const Basis basis(Vector3(0, 1, 0), yaw);
		const int floors = CLAMP(1 + (int)Math::floor(rnd(key, 1) * floor_cap), 1, floor_cap);
		const int nx = MAX(1, (int)Math::round(fx / module));
		const int nz = MAX(1, (int)Math::round(fz / module));
		const float mx = fx / nx;
		const float mz = fz / nz;
		// Sides: 0 +z, 1 +x, 2 -z, 3 -x. Even sides run along x (nx slots), odd sides along z (nz slots).
		const int door_side = (int)Math::floor(rnd(key, 2) * 4.0f) % 4;
		const int door_slots = (door_side % 2 == 0) ? nx : nz;
		const int door_slot = (int)Math::floor(rnd(key, 3) * door_slots) % door_slots;
		uint64_t counter = 0;
		auto place = [&](const Vector3 &p_local, float p_local_yaw, int p_piece, int p_floor) {
			counter++;
			const Vector3 p = base + basis.xform(p_local) + Vector3(0, p_floor * fh, 0);
			out.add(p, Vector3(0, 1, 0), 1.0f, yaw + p_local_yaw, 1.0f, (int64_t)pcg_mix64(key, 100 + counter));
			out.set("piece", (float)p_piece);
			out.set("floor", (float)p_floor);
			out.set("floors", (float)floors);
			out.set("building", (float)i);
		};
		for (int f = 0; f < floors; f++) {
			for (int j = 0; j < nz; j++) {
				for (int k = 0; k < nx; k++) {
					place(Vector3(-fx * 0.5f + (k + 0.5f) * mx, 0, -fz * 0.5f + (j + 0.5f) * mz), 0.0f, PIECE_FLOOR, f);
				}
			}
			for (int side = 0; side < 4; side++) {
				const int slots = (side % 2 == 0) ? nx : nz;
				const float out_yaw = side == 0 ? 0.0f : (side == 1 ? float(Math::PI) * 0.5f : (side == 2 ? float(Math::PI) : -float(Math::PI) * 0.5f));
				for (int slot = 0; slot < slots; slot++) {
					Vector3 local;
					switch (side) {
						case 0:
							local = Vector3(-fx * 0.5f + (slot + 0.5f) * mx, 0, fz * 0.5f);
							break;
						case 1:
							local = Vector3(fx * 0.5f, 0, -fz * 0.5f + (slot + 0.5f) * mz);
							break;
						case 2:
							local = Vector3(-fx * 0.5f + (slot + 0.5f) * mx, 0, -fz * 0.5f);
							break;
						default:
							local = Vector3(-fx * 0.5f, 0, -fz * 0.5f + (slot + 0.5f) * mz);
							break;
					}
					int piece = PIECE_WALL;
					if (f == 0 && side == door_side && slot == door_slot) {
						piece = PIECE_DOOR;
					} else if (rnd(key, 1000 + (uint64_t)f * 100 + side * 20 + slot) < window_p) {
						piece = PIECE_WINDOW;
					}
					place(local, out_yaw, piece, f);
				}
			}
			for (int sx = -1; sx <= 1; sx += 2) {
				for (int sz = -1; sz <= 1; sz += 2) {
					place(Vector3(sx * fx * 0.5f, 0, sz * fz * 0.5f), Math::atan2((float)sx, (float)sz), PIECE_CORNER, f);
				}
			}
		}
		for (int j = 0; j < nz; j++) {
			for (int k = 0; k < nx; k++) {
				place(Vector3(-fx * 0.5f + (k + 0.5f) * mx, 0, -fz * 0.5f + (j + 0.5f) * mz), 0.0f, PIECE_ROOF, floors);
			}
		}
	}
	return out.finish();
}

PCGW_SETTER(PCGBuildingNode, int, max_floors, MAX(1, p_value))
PCGW_SETTER(PCGBuildingNode, float, module_size, MAX(0.5f, p_value))
PCGW_SETTER(PCGBuildingNode, float, floor_height, MAX(0.5f, p_value))
PCGW_SETTER(PCGBuildingNode, float, window_chance, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGBuildingNode, float, default_footprint, MAX(0.5f, p_value))

void PCGBuildingNode::_bind_methods() {
	PCGW_BIND(PCGBuildingNode, max_floors)
	PCGW_BIND(PCGBuildingNode, module_size)
	PCGW_BIND(PCGBuildingNode, floor_height)
	PCGW_BIND(PCGBuildingNode, window_chance)
	PCGW_BIND(PCGBuildingNode, default_footprint)
	PCGW_PROP(Variant::INT, max_floors, PROPERTY_HINT_RANGE, "1,32,1,or_greater")
	PCGW_PROP(Variant::FLOAT, module_size, PROPERTY_HINT_RANGE, "0.5,16,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, floor_height, PROPERTY_HINT_RANGE, "0.5,16,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, window_chance, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::FLOAT, default_footprint, PROPERTY_HINT_RANGE, "0.5,64,0.1,or_greater")
}

// --- Ruins -------------------------------------------------------------------------------------------------------

Ref<PCGData> PCGRuinNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	PWOut out;
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const float base = float(resolve("base_decay", p_context));
	const float high = float(resolve("height_decay", p_context));
	const float noise_w = float(resolve("noise_strength", p_context));
	const float freq = MAX(0.0001f, float(resolve("noise_frequency", p_context)));
	const float fh = MAX(0.5f, float(resolve("floor_height", p_context)));
	const float rubble_p = CLAMP(float(resolve("rubble_chance", p_context)), 0.0f, 1.0f);
	const float spread = MAX(0.0f, float(resolve("rubble_spread", p_context)));
	const int rubble_n = MAX(0, int(resolve("rubble_per_piece", p_context)));
	const PackedStringArray names = in->get_attribute_names();

	for (int i = 0; i < in->get_point_count(); i++) {
		const Vector3 p = in->get_position(i);
		const int piece = (int)in->get_attribute_value("piece", i, float(PCGBuildingNode::PIECE_WALL));
		const float floor_index = in->get_attribute_value("floor", i, 0.0f);
		const float floors = MAX(1.0f, in->get_attribute_value("floors", i, 1.0f));
		const uint64_t key = point_key(in, i, p_seed);
		const float noise = PCGDensityNoiseNode::value_noise(p_seed, p.x, p.z, freq, 2);
		float decay = base + high * CLAMP(floor_index / floors, 0.0f, 1.0f) + noise_w * (noise - 0.5f) * 2.0f;
		if (piece == PCGBuildingNode::PIECE_FLOOR) {
			decay *= 0.3f;
		}
		decay = CLAMP(decay, 0.0f, 1.0f);
		if (piece == PCGBuildingNode::PIECE_RUBBLE || rnd(key, 11) >= decay) {
			out.add(p, in->get_normal(i), in->get_density(i), in->get_yaw(i), in->get_scale(i), in->get_seed(i));
			for (int k = 0; k < names.size(); k++) {
				out.set(StringName(names[k]), in->get_attribute_value(StringName(names[k]), i));
			}
			continue;
		}
		if (piece == PCGBuildingNode::PIECE_FLOOR || rnd(key, 12) >= rubble_p) {
			continue;
		}
		for (int r = 0; r < rubble_n; r++) {
			const uint64_t rk = pcg_mix64(key, 20 + r);
			const float angle = rnd(rk, 1) * float(Math::TAU);
			const float dist = rnd(rk, 2) * spread;
			out.add(Vector3(p.x + Math::sin(angle) * dist, p.y - floor_index * fh, p.z + Math::cos(angle) * dist), Vector3(0, 1, 0), 1.0f, rnd(rk, 3) * float(Math::TAU), Math::lerp(0.5f, 1.2f, rnd(rk, 4)), (int64_t)rk);
			out.set("piece", float(PCGBuildingNode::PIECE_RUBBLE));
			out.set("floor", 0.0f);
			out.set("floors", floors);
			out.set("building", in->get_attribute_value("building", i, 0.0f));
		}
	}
	return out.finish();
}

PCGW_SETTER(PCGRuinNode, float, base_decay, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGRuinNode, float, height_decay, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGRuinNode, float, noise_strength, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGRuinNode, float, noise_frequency, MAX(0.0001f, p_value))
PCGW_SETTER(PCGRuinNode, float, floor_height, MAX(0.5f, p_value))
PCGW_SETTER(PCGRuinNode, float, rubble_chance, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGRuinNode, float, rubble_spread, MAX(0.0f, p_value))
PCGW_SETTER(PCGRuinNode, int, rubble_per_piece, MAX(0, p_value))

void PCGRuinNode::_bind_methods() {
	PCGW_BIND(PCGRuinNode, base_decay)
	PCGW_BIND(PCGRuinNode, height_decay)
	PCGW_BIND(PCGRuinNode, noise_strength)
	PCGW_BIND(PCGRuinNode, noise_frequency)
	PCGW_BIND(PCGRuinNode, floor_height)
	PCGW_BIND(PCGRuinNode, rubble_chance)
	PCGW_BIND(PCGRuinNode, rubble_spread)
	PCGW_BIND(PCGRuinNode, rubble_per_piece)
	PCGW_PROP(Variant::FLOAT, base_decay, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::FLOAT, height_decay, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::FLOAT, noise_strength, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::FLOAT, noise_frequency, PROPERTY_HINT_RANGE, "0.0001,1,0.0001,or_greater")
	PCGW_PROP(Variant::FLOAT, floor_height, PROPERTY_HINT_RANGE, "0.5,16,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, rubble_chance, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::FLOAT, rubble_spread, PROPERTY_HINT_RANGE, "0,32,0.1,or_greater")
	PCGW_PROP(Variant::INT, rubble_per_piece, PROPERTY_HINT_RANGE, "0,16,1,or_greater")
}

// --- Structures --------------------------------------------------------------------------------------------------

Ref<PCGData> PCGStructureNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const Array table = resolve("rules", p_context);
	const float gap = MAX(0.0f, float(resolve("min_gap", p_context)));
	const int n = in->get_point_count();
	float max_radius = 1.0f;
	for (int r = 0; r < table.size(); r++) {
		const Dictionary rule = table[r];
		max_radius = MAX(max_radius, float(rule.get("radius", 4.0)));
	}
	struct Order {
		const LocalVector<float> *prio;
		bool operator()(int p_a, int p_b) const {
			if ((*prio)[p_a] != (*prio)[p_b]) {
				return (*prio)[p_a] < (*prio)[p_b];
			}
			return p_a < p_b;
		}
	};
	LocalVector<float> prio;
	LocalVector<int> order;
	for (int i = 0; i < n; i++) {
		prio.push_back(rnd(point_key(in, i, p_seed), 1));
		order.push_back(i);
	}
	SortArray<int, Order> sorter;
	sorter.compare = Order{ &prio };
	sorter.sort(order.ptr(), order.size());

	PWHash placed(max_radius * 2.0f + gap);
	LocalVector<int> chosen_rule;
	LocalVector<float> chosen_radius;
	for (int i = 0; i < n; i++) {
		chosen_rule.push_back(-1);
		chosen_radius.push_back(0.0f);
	}
	for (uint32_t o = 0; o < order.size(); o++) {
		const int i = order[o];
		const Vector3 p = in->get_position(i);
		const uint64_t key = point_key(in, i, p_seed);
		const float slope = slope_deg(p_context, p.x, p.z);
		String biome;
		bool biome_sampled = false;
		LocalVector<int> candidates;
		float total = 0.0f;
		for (int r = 0; r < table.size(); r++) {
			const Dictionary rule = table[r];
			const float weight = rule.get("weight", 1.0);
			if (weight <= 0.0f || slope < float(rule.get("min_slope", 0.0)) || slope > float(rule.get("max_slope", 90.0))) {
				continue;
			}
			const PackedStringArray rule_biomes = rule.get("biomes", PackedStringArray());
			if (!rule_biomes.is_empty()) {
				if (!biome_sampled) {
					biome = p_context->sample_biome(p.x, p.z);
					biome_sampled = true;
				}
				if (!rule_biomes.has(biome)) {
					continue;
				}
			}
			candidates.push_back(r);
			total += weight;
		}
		if (candidates.is_empty()) {
			continue;
		}
		float pick = rnd(key, 2) * total;
		int rule_index = candidates[candidates.size() - 1];
		for (uint32_t c = 0; c < candidates.size(); c++) {
			const Dictionary cand_rule = table[candidates[c]];
			pick -= float(cand_rule.get("weight", 1.0));
			if (pick <= 0.0f) {
				rule_index = candidates[c];
				break;
			}
		}
		const Dictionary picked_rule = table[rule_index];
		const float radius_v = MAX(0.1f, float(picked_rule.get("radius", 4.0)));
		if (placed.overlaps(p, radius_v, gap)) {
			continue;
		}
		placed.insert(p, radius_v);
		chosen_rule[i] = rule_index;
		chosen_radius[i] = radius_v;
	}
	PWOut out;
	for (int i = 0; i < n; i++) {
		if (chosen_rule[i] < 0) {
			continue;
		}
		const uint64_t key = point_key(in, i, p_seed);
		out.add(in->get_position(i), in->get_normal(i), in->get_density(i), rnd(key, 3) * float(Math::TAU), 1.0f, (int64_t)pcg_mix64(key, 4));
		const Dictionary final_rule = table[chosen_rule[i]];
		out.set("structure", float(int(final_rule.get("id", chosen_rule[i]))));
		out.set("footprint_radius", chosen_radius[i]);
	}
	return out.finish();
}

PCGW_SETTER(PCGStructureNode, Array, rules, p_value)
PCGW_SETTER(PCGStructureNode, float, min_gap, MAX(0.0f, p_value))

void PCGStructureNode::_bind_methods() {
	PCGW_BIND(PCGStructureNode, rules)
	PCGW_BIND(PCGStructureNode, min_gap)
	PCGW_PROP(Variant::ARRAY, rules, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::FLOAT, min_gap, PROPERTY_HINT_RANGE, "0,64,0.1,or_greater")
}

// --- Loot --------------------------------------------------------------------------------------------------------

Ref<PCGData> PCGLootPlacementNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	Ref<PCGPointData> structures = points_input(p_inputs, 1);
	const Array table = resolve("rarity_rules", p_context);
	const PackedFloat32Array bands = resolve("tier_bands", p_context);
	const StringName tier_attr = StringName(String(resolve("tier_attribute", p_context)));
	const Vector3 center = resolve("origin", p_context);
	const int per_group = MAX(0, int(resolve("max_per_structure", p_context)));
	const float spacing = MAX(0.0f, float(resolve("min_spacing", p_context)));
	const float chance_v = CLAMP(float(resolve("chance", p_context)), 0.0f, 1.0f);
	const float cell = MAX(1.0f, float(resolve("group_cell", p_context)));
	const int n = in->get_point_count();
	const bool use_attr_tier = in->has_attribute(tier_attr);

	LocalVector<float> prio;
	LocalVector<int> order;
	for (int i = 0; i < n; i++) {
		prio.push_back(rnd(point_key(in, i, p_seed), 1));
		order.push_back(i);
	}
	struct Order {
		const LocalVector<float> *prio;
		bool operator()(int p_a, int p_b) const {
			if ((*prio)[p_a] != (*prio)[p_b]) {
				return (*prio)[p_a] < (*prio)[p_b];
			}
			return p_a < p_b;
		}
	};
	SortArray<int, Order> sorter;
	sorter.compare = Order{ &prio };
	sorter.sort(order.ptr(), order.size());

	PWHash placed(MAX(1.0f, spacing));
	HashMap<int64_t, int> group_counts;
	LocalVector<int> tier_of;
	LocalVector<int> table_of;
	LocalVector<uint8_t> accepted;
	for (int i = 0; i < n; i++) {
		tier_of.push_back(0);
		table_of.push_back(0);
		accepted.push_back(0);
	}
	for (uint32_t o = 0; o < order.size(); o++) {
		const int i = order[o];
		const Vector3 p = in->get_position(i);
		const uint64_t key = point_key(in, i, p_seed);
		if (rnd(key, 2) >= chance_v) {
			continue;
		}
		int64_t group = 0;
		if (structures->get_point_count() > 0) {
			float best_d = Math::INF;
			for (int s = 0; s < structures->get_point_count(); s++) {
				const float d = dist_xz(p, structures->get_position(s));
				if (d < best_d) {
					best_d = d;
					group = s;
				}
			}
		} else {
			const uint64_t gx = (uint32_t)(int32_t)Math::floor(p.x / cell);
			const uint64_t gz = (uint32_t)(int32_t)Math::floor(p.z / cell);
			group = (int64_t)((gx << 32) | gz);
		}
		const int used = group_counts.has(group) ? group_counts[group] : 0;
		if (used >= per_group) {
			continue;
		}
		if (spacing > 0.0f && placed.overlaps(p, spacing * 0.5f, 0.0f)) {
			continue;
		}
		const int tier = use_attr_tier ? (int)in->get_attribute_value(tier_attr, i) : count_bands(bands, dist_xz(p, center));
		int table_id = 0;
		float total = 0.0f;
		LocalVector<int> candidates;
		for (int r = 0; r < table.size(); r++) {
			const Dictionary rule = table[r];
			if (float(rule.get("weight", 1.0)) <= 0.0f || tier < int(rule.get("min_tier", 0)) || tier > int(rule.get("max_tier", 99))) {
				continue;
			}
			candidates.push_back(r);
			total += float(rule.get("weight", 1.0));
		}
		if (!candidates.is_empty()) {
			float pick = rnd(key, 3) * total;
			const int last_rule = candidates[candidates.size() - 1];
			const Dictionary fallback_rule = table[last_rule];
			table_id = int(fallback_rule.get("table", last_rule));
			for (uint32_t c = 0; c < candidates.size(); c++) {
				const Dictionary rule = table[candidates[c]];
				pick -= float(rule.get("weight", 1.0));
				if (pick <= 0.0f) {
					table_id = int(rule.get("table", candidates[c]));
					break;
				}
			}
		}
		group_counts[group] = used + 1;
		placed.insert(p, spacing * 0.5f);
		accepted[i] = 1;
		tier_of[i] = tier;
		table_of[i] = table_id;
	}
	PackedInt32Array keep;
	PackedFloat32Array tiers;
	PackedFloat32Array tables;
	for (int i = 0; i < n; i++) {
		if (accepted[i]) {
			keep.push_back(i);
			tiers.push_back((float)tier_of[i]);
			tables.push_back((float)table_of[i]);
		}
	}
	Ref<PCGPointData> out = in->select(keep);
	out->set_attribute("loot_tier", tiers);
	out->set_attribute("loot_table", tables);
	return out;
}

PCGW_SETTER(PCGLootPlacementNode, Array, rarity_rules, p_value)
PCGW_SETTER(PCGLootPlacementNode, PackedFloat32Array, tier_bands, p_value)
PCGW_SETTER(PCGLootPlacementNode, String, tier_attribute, p_value)
PCGW_SETTER(PCGLootPlacementNode, Vector3, origin, p_value)
PCGW_SETTER(PCGLootPlacementNode, int, max_per_structure, MAX(0, p_value))
PCGW_SETTER(PCGLootPlacementNode, float, min_spacing, MAX(0.0f, p_value))
PCGW_SETTER(PCGLootPlacementNode, float, chance, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGLootPlacementNode, float, group_cell, MAX(1.0f, p_value))

void PCGLootPlacementNode::_bind_methods() {
	PCGW_BIND(PCGLootPlacementNode, rarity_rules)
	PCGW_BIND(PCGLootPlacementNode, tier_bands)
	PCGW_BIND(PCGLootPlacementNode, tier_attribute)
	PCGW_BIND(PCGLootPlacementNode, origin)
	PCGW_BIND(PCGLootPlacementNode, max_per_structure)
	PCGW_BIND(PCGLootPlacementNode, min_spacing)
	PCGW_BIND(PCGLootPlacementNode, chance)
	PCGW_BIND(PCGLootPlacementNode, group_cell)
	PCGW_PROP(Variant::ARRAY, rarity_rules, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::PACKED_FLOAT32_ARRAY, tier_bands, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::STRING, tier_attribute, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::VECTOR3, origin, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::INT, max_per_structure, PROPERTY_HINT_RANGE, "0,256,1,or_greater")
	PCGW_PROP(Variant::FLOAT, min_spacing, PROPERTY_HINT_RANGE, "0,64,0.1,or_greater")
	PCGW_PROP(Variant::FLOAT, chance, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::FLOAT, group_cell, PROPERTY_HINT_RANGE, "1,256,0.5,or_greater")
}

// --- Encounters --------------------------------------------------------------------------------------------------

Ref<PCGData> PCGEncounterPlacementNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const float point_dist = MAX(0.0f, float(resolve("min_point_distance", p_context)));
	const float spline_dist = MAX(0.0f, float(resolve("min_spline_distance", p_context)));
	const float spacing = MAX(0.0f, float(resolve("min_spacing", p_context)));
	const PackedFloat32Array bands = resolve("difficulty_bands", p_context);
	const Vector3 center = resolve("origin", p_context);
	const int size_min = MAX(1, int(resolve("group_size_min", p_context)));
	const int size_max = MAX(size_min, int(resolve("group_size_max", p_context)));
	const float slope_cap = resolve("max_slope", p_context);
	const float chance_v = CLAMP(float(resolve("chance", p_context)), 0.0f, 1.0f);
	const int count_cap = MAX(0, int(resolve("max_count", p_context)));

	PWHash avoid_points(MAX(1.0f, point_dist));
	Vector<Ref<PCGSplineData>> avoid_splines;
	for (int k = 1; k <= 2; k++) {
		if (k >= p_inputs.size()) {
			break;
		}
		Ref<PCGPointData> points = p_inputs[k];
		Ref<PCGSplineData> spline = p_inputs[k];
		if (points.is_valid()) {
			for (int i = 0; i < points->get_point_count(); i++) {
				avoid_points.insert(points->get_position(i), 0.0f);
			}
		} else if (spline.is_valid()) {
			avoid_splines.push_back(spline);
		}
	}

	const int n = in->get_point_count();
	LocalVector<float> prio;
	LocalVector<int> order;
	for (int i = 0; i < n; i++) {
		prio.push_back(rnd(point_key(in, i, p_seed), 1));
		order.push_back(i);
	}
	struct Order {
		const LocalVector<float> *prio;
		bool operator()(int p_a, int p_b) const {
			if ((*prio)[p_a] != (*prio)[p_b]) {
				return (*prio)[p_a] < (*prio)[p_b];
			}
			return p_a < p_b;
		}
	};
	SortArray<int, Order> sorter;
	sorter.compare = Order{ &prio };
	sorter.sort(order.ptr(), order.size());

	PWHash placed(MAX(1.0f, spacing));
	LocalVector<uint8_t> accepted;
	for (int i = 0; i < n; i++) {
		accepted.push_back(0);
	}
	int total = 0;
	for (uint32_t o = 0; o < order.size() && total < count_cap; o++) {
		const int i = order[o];
		const Vector3 p = in->get_position(i);
		const uint64_t key = point_key(in, i, p_seed);
		if (rnd(key, 2) >= chance_v || p_context->sample_water(p.x, p.z) || slope_deg(p_context, p.x, p.z) > slope_cap) {
			continue;
		}
		if (point_dist > 0.0f && avoid_points.overlaps(p, 0.0f, point_dist)) {
			continue;
		}
		bool near_spline = false;
		for (int s = 0; s < avoid_splines.size(); s++) {
			if (avoid_splines[s]->distance_xz(p) < spline_dist) {
				near_spline = true;
				break;
			}
		}
		if (near_spline) {
			continue;
		}
		if (spacing > 0.0f && placed.overlaps(p, spacing * 0.5f, 0.0f)) {
			continue;
		}
		placed.insert(p, spacing * 0.5f);
		accepted[i] = 1;
		total++;
	}
	PackedInt32Array keep;
	PackedFloat32Array sizes;
	PackedFloat32Array difficulties;
	for (int i = 0; i < n; i++) {
		if (!accepted[i]) {
			continue;
		}
		const Vector3 p = in->get_position(i);
		const int difficulty = count_bands(bands, dist_xz(p, center));
		const int group = size_min + (int)Math::floor(rnd(point_key(in, i, p_seed), 3) * (size_max - size_min + 1)) + difficulty / 2;
		keep.push_back(i);
		sizes.push_back((float)group);
		difficulties.push_back((float)difficulty);
	}
	Ref<PCGPointData> out = in->select(keep);
	out->set_attribute("group_size", sizes);
	out->set_attribute("difficulty", difficulties);
	return out;
}

PCGW_SETTER(PCGEncounterPlacementNode, float, min_point_distance, MAX(0.0f, p_value))
PCGW_SETTER(PCGEncounterPlacementNode, float, min_spline_distance, MAX(0.0f, p_value))
PCGW_SETTER(PCGEncounterPlacementNode, float, min_spacing, MAX(0.0f, p_value))
PCGW_SETTER(PCGEncounterPlacementNode, PackedFloat32Array, difficulty_bands, p_value)
PCGW_SETTER(PCGEncounterPlacementNode, Vector3, origin, p_value)
PCGW_SETTER(PCGEncounterPlacementNode, int, group_size_min, MAX(1, p_value))
PCGW_SETTER(PCGEncounterPlacementNode, int, group_size_max, MAX(1, p_value))
PCGW_SETTER(PCGEncounterPlacementNode, float, max_slope, CLAMP(p_value, 0.0f, 90.0f))
PCGW_SETTER(PCGEncounterPlacementNode, float, chance, CLAMP(p_value, 0.0f, 1.0f))
PCGW_SETTER(PCGEncounterPlacementNode, int, max_count, MAX(0, p_value))

void PCGEncounterPlacementNode::_bind_methods() {
	PCGW_BIND(PCGEncounterPlacementNode, min_point_distance)
	PCGW_BIND(PCGEncounterPlacementNode, min_spline_distance)
	PCGW_BIND(PCGEncounterPlacementNode, min_spacing)
	PCGW_BIND(PCGEncounterPlacementNode, difficulty_bands)
	PCGW_BIND(PCGEncounterPlacementNode, origin)
	PCGW_BIND(PCGEncounterPlacementNode, group_size_min)
	PCGW_BIND(PCGEncounterPlacementNode, group_size_max)
	PCGW_BIND(PCGEncounterPlacementNode, max_slope)
	PCGW_BIND(PCGEncounterPlacementNode, chance)
	PCGW_BIND(PCGEncounterPlacementNode, max_count)
	PCGW_PROP(Variant::FLOAT, min_point_distance, PROPERTY_HINT_RANGE, "0,1024,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, min_spline_distance, PROPERTY_HINT_RANGE, "0,1024,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, min_spacing, PROPERTY_HINT_RANGE, "0,1024,0.5,or_greater")
	PCGW_PROP(Variant::PACKED_FLOAT32_ARRAY, difficulty_bands, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::VECTOR3, origin, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::INT, group_size_min, PROPERTY_HINT_RANGE, "1,64,1,or_greater")
	PCGW_PROP(Variant::INT, group_size_max, PROPERTY_HINT_RANGE, "1,64,1,or_greater")
	PCGW_PROP(Variant::FLOAT, max_slope, PROPERTY_HINT_RANGE, "0,90,0.5")
	PCGW_PROP(Variant::FLOAT, chance, PROPERTY_HINT_RANGE, "0,1,0.01")
	PCGW_PROP(Variant::INT, max_count, PROPERTY_HINT_RANGE, "0,4096,1,or_greater")
}

// --- Environment dressing ----------------------------------------------------------------------------------------

Ref<PCGData> PCGEnvironmentDressingNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	PWOut out;
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const Array table = resolve("rules", p_context);
	const int lamp_id = resolve("lamp_asset", p_context);
	const float lamp_step = MAX(0.0f, float(resolve("lamp_spacing", p_context)));
	const float lamp_off = MAX(0.0f, float(resolve("lamp_offset", p_context)));
	const int cap = MAX(0, int(resolve("max_points", p_context)));
	const bool has_ground = p_context->get_height_sampler().is_valid();
	const AABB bounds = p_context->get_bounds();

	for (int i = 0; i < in->get_point_count() && out.n < cap; i++) {
		const Vector3 src = in->get_position(i);
		const uint64_t key = point_key(in, i, p_seed);
		for (int r = 0; r < table.size(); r++) {
			const Dictionary rule = table[r];
			const String attribute = rule.get("attribute", "");
			if (!attribute.is_empty()) {
				const float v = in->get_attribute_value(StringName(attribute), i, -100000.0f);
				if (Math::abs(v - float(rule.get("value", 0.0))) > 0.5f) {
					continue;
				}
			}
			const uint64_t rk = pcg_mix64(key, 50 + r);
			if (rnd(rk, 1) >= float(rule.get("chance", 1.0))) {
				continue;
			}
			const int cmin = MAX(0, int(rule.get("count_min", 1)));
			const int cmax = MAX(cmin, int(rule.get("count_max", 2)));
			const int count = cmin + (int)Math::floor(rnd(rk, 2) * (cmax - cmin + 1));
			const float ring_min = MAX(0.0f, float(rule.get("ring_min", 0.5)));
			const float ring_max = MAX(ring_min, float(rule.get("ring_max", 2.5)));
			const float scale_min = float(rule.get("scale_min", 0.8));
			const float scale_max = MAX(scale_min, float(rule.get("scale_max", 1.2)));
			const bool outward = bool(rule.get("face_outward", false));
			for (int c = 0; c < count && out.n < cap; c++) {
				const uint64_t ck = pcg_mix64(rk, 10 + c);
				const float angle = rnd(ck, 1) * float(Math::TAU);
				const float dist = Math::lerp(ring_min, ring_max, rnd(ck, 2));
				const float x = src.x + Math::sin(angle) * dist;
				const float z = src.z + Math::cos(angle) * dist;
				if (p_context->sample_water(x, z)) {
					continue;
				}
				const float y = has_ground ? p_context->sample_height(x, z) : src.y;
				out.add(Vector3(x, y, z), has_ground ? p_context->sample_normal(x, z) : Vector3(0, 1, 0), 1.0f, outward ? angle : rnd(ck, 3) * float(Math::TAU), Math::lerp(scale_min, scale_max, rnd(ck, 4)), (int64_t)ck);
				out.set("asset", float(int(rule.get("asset", r))));
				out.set("source", (float)i);
			}
		}
	}

	if (lamp_step > 0.0f && p_inputs.size() > 1) {
		Ref<PCGSplineData> roads = p_inputs[1];
		if (roads.is_valid()) {
			for (int l = 0; l < roads->get_polyline_count() && out.n < cap; l++) {
				const PackedVector3Array line = roads->get_polyline(l);
				const float half = roads->get_width(l) * 0.5f;
				float travelled = 0.0f;
				float next = lamp_step * 0.5f;
				int lamp_index = 0;
				for (int s = 1; s < line.size(); s++) {
					const Vector3 a = line[s - 1];
					const Vector3 b = line[s];
					const float len = dist_xz(a, b);
					if (len <= 0.0001f) {
						continue;
					}
					const Vector3 dir = (b - a) / len;
					const Vector3 side(-dir.z, 0, dir.x);
					while (next <= travelled + len && out.n < cap) {
						const Vector3 base = a + dir * (next - travelled);
						const float sign = (lamp_index % 2 == 0) ? 1.0f : -1.0f;
						const Vector3 p = base + side * sign * (half + lamp_off);
						const uint64_t lk = pcg_mix64(pcg_mix64(p_seed, 0x4c414d50ULL + l), (uint64_t)lamp_index);
						next += lamp_step;
						lamp_index++;
						if (!in_bounds_xz(bounds, p.x, p.z) || p_context->sample_water(p.x, p.z)) {
							continue;
						}
						const float y = has_ground ? p_context->sample_height(p.x, p.z) : p.y;
						out.add(Vector3(p.x, y, p.z), has_ground ? p_context->sample_normal(p.x, p.z) : Vector3(0, 1, 0), 1.0f, Math::atan2(-side.x * sign, -side.z * sign), 1.0f, (int64_t)lk);
						out.set("asset", (float)lamp_id);
						out.set("source", -1.0f);
					}
					travelled += len;
				}
			}
		}
	}
	return out.finish();
}

PCGW_SETTER(PCGEnvironmentDressingNode, Array, rules, p_value)
PCGW_SETTER(PCGEnvironmentDressingNode, int, lamp_asset, p_value)
PCGW_SETTER(PCGEnvironmentDressingNode, float, lamp_spacing, MAX(0.0f, p_value))
PCGW_SETTER(PCGEnvironmentDressingNode, float, lamp_offset, MAX(0.0f, p_value))
PCGW_SETTER(PCGEnvironmentDressingNode, int, max_points, MAX(0, p_value))

void PCGEnvironmentDressingNode::_bind_methods() {
	PCGW_BIND(PCGEnvironmentDressingNode, rules)
	PCGW_BIND(PCGEnvironmentDressingNode, lamp_asset)
	PCGW_BIND(PCGEnvironmentDressingNode, lamp_spacing)
	PCGW_BIND(PCGEnvironmentDressingNode, lamp_offset)
	PCGW_BIND(PCGEnvironmentDressingNode, max_points)
	PCGW_PROP(Variant::ARRAY, rules, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::INT, lamp_asset, PROPERTY_HINT_NONE, "")
	PCGW_PROP(Variant::FLOAT, lamp_spacing, PROPERTY_HINT_RANGE, "0,256,0.5,or_greater")
	PCGW_PROP(Variant::FLOAT, lamp_offset, PROPERTY_HINT_RANGE, "0,32,0.1,or_greater")
	PCGW_PROP(Variant::INT, max_points, PROPERTY_HINT_RANGE, "0,1000000,1,or_greater")
}

// --- Registration ------------------------------------------------------------------------------------------------

void register_pcg_world_nodes() {
	GDREGISTER_CLASS(PCGRoadNetworkNode);
	GDREGISTER_CLASS(PCGRiverNetworkNode);
	GDREGISTER_CLASS(PCGSettlementNode);
	GDREGISTER_CLASS(PCGCityNode);
	GDREGISTER_CLASS(PCGBuildingNode);
	GDREGISTER_CLASS(PCGRuinNode);
	GDREGISTER_CLASS(PCGStructureNode);
	GDREGISTER_CLASS(PCGLootPlacementNode);
	GDREGISTER_CLASS(PCGEncounterPlacementNode);
	GDREGISTER_CLASS(PCGEnvironmentDressingNode);
}
