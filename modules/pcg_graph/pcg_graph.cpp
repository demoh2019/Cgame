/**************************************************************************/
/*  pcg_graph.cpp                                                         */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_graph.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"

void PCGGraph::_on_node_changed() {
	emit_changed();
}

void PCGGraph::set_nodes(const TypedArray<PCGNode> &p_nodes) {
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_valid() && node->is_connected(CoreStringName(changed), callable_mp(this, &PCGGraph::_on_node_changed))) {
			node->disconnect(CoreStringName(changed), callable_mp(this, &PCGGraph::_on_node_changed));
		}
	}
	nodes = p_nodes;
	next_id = 1;
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_null()) {
			continue;
		}
		next_id = MAX(next_id, node->get_node_id() + 1);
		node->connect(CoreStringName(changed), callable_mp(this, &PCGGraph::_on_node_changed));
	}
	emit_changed();
}

void PCGGraph::set_connections(const Array &p_connections) {
	connections = p_connections;
	emit_changed();
}

void PCGGraph::set_parameters(const Dictionary &p_parameters) {
	parameters = p_parameters;
	emit_changed();
}

void PCGGraph::set_output_node_id(int p_id) {
	output_node_id = p_id;
	emit_changed();
}

int PCGGraph::add_node(const Ref<PCGNode> &p_node) {
	ERR_FAIL_COND_V(p_node.is_null(), -1);
	int id = p_node->get_node_id();
	if (id <= 0 || get_node_by_id(id).is_valid()) {
		id = next_id;
	}
	next_id = MAX(next_id, id + 1);
	p_node->set_node_id(id);
	nodes.push_back(p_node);
	p_node->connect(CoreStringName(changed), callable_mp(this, &PCGGraph::_on_node_changed));
	emit_changed();
	return id;
}

void PCGGraph::remove_node(int p_id) {
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_valid() && node->get_node_id() == p_id) {
			if (node->is_connected(CoreStringName(changed), callable_mp(this, &PCGGraph::_on_node_changed))) {
				node->disconnect(CoreStringName(changed), callable_mp(this, &PCGGraph::_on_node_changed));
			}
			nodes.remove_at(i);
			break;
		}
	}
	for (int i = connections.size() - 1; i >= 0; i--) {
		Dictionary c = connections[i];
		if (int(c.get("from", -1)) == p_id || int(c.get("to", -1)) == p_id) {
			connections.remove_at(i);
		}
	}
	if (output_node_id == p_id) {
		output_node_id = -1;
	}
	emit_changed();
}

Ref<PCGNode> PCGGraph::get_node_by_id(int p_id) const {
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_valid() && node->get_node_id() == p_id) {
			return node;
		}
	}
	return Ref<PCGNode>();
}

PackedInt32Array PCGGraph::get_node_ids() const {
	PackedInt32Array ids;
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_valid()) {
			ids.push_back(node->get_node_id());
		}
	}
	ids.sort();
	return ids;
}

bool PCGGraph::_would_cycle(int p_from, int p_to) const {
	// A new edge from -> to closes a cycle if `from` is already reachable from `to`.
	if (p_from == p_to) {
		return true;
	}
	HashSet<int> seen;
	Vector<int> stack;
	stack.push_back(p_to);
	while (!stack.is_empty()) {
		const int current = stack[stack.size() - 1];
		stack.remove_at(stack.size() - 1);
		if (current == p_from) {
			return true;
		}
		if (seen.has(current)) {
			continue;
		}
		seen.insert(current);
		PackedInt32Array next = get_downstream(current);
		for (int i = 0; i < next.size(); i++) {
			stack.push_back(next[i]);
		}
	}
	return false;
}

Error PCGGraph::connect_nodes(int p_from, int p_to, int p_to_port) {
	Ref<PCGNode> from = get_node_by_id(p_from);
	Ref<PCGNode> to = get_node_by_id(p_to);
	ERR_FAIL_COND_V_MSG(from.is_null() || to.is_null(), ERR_DOES_NOT_EXIST, "PCG connection names a missing node.");
	ERR_FAIL_COND_V_MSG(p_to_port < 0 || p_to_port >= MAX(1, to->get_input_count()), ERR_PARAMETER_RANGE_ERROR, "PCG input port out of range.");
	ERR_FAIL_COND_V_MSG(_would_cycle(p_from, p_to), ERR_CYCLIC_LINK, "PCG connection would create a cycle.");
	// One source per input port: replace an existing link on that port.
	for (int i = connections.size() - 1; i >= 0; i--) {
		Dictionary c = connections[i];
		if (int(c.get("to", -1)) == p_to && int(c.get("to_port", 0)) == p_to_port) {
			connections.remove_at(i);
		}
	}
	Dictionary link;
	link["from"] = p_from;
	link["to"] = p_to;
	link["to_port"] = p_to_port;
	connections.push_back(link);
	emit_changed();
	return OK;
}

void PCGGraph::disconnect_nodes(int p_from, int p_to, int p_to_port) {
	for (int i = connections.size() - 1; i >= 0; i--) {
		Dictionary c = connections[i];
		if (int(c.get("from", -1)) == p_from && int(c.get("to", -1)) == p_to && int(c.get("to_port", 0)) == p_to_port) {
			connections.remove_at(i);
		}
	}
	emit_changed();
}

bool PCGGraph::is_connected_to(int p_from, int p_to, int p_to_port) const {
	for (int i = 0; i < connections.size(); i++) {
		Dictionary c = connections[i];
		if (int(c.get("from", -1)) == p_from && int(c.get("to", -1)) == p_to && int(c.get("to_port", 0)) == p_to_port) {
			return true;
		}
	}
	return false;
}

PackedInt32Array PCGGraph::get_input_sources(int p_id) const {
	PackedInt32Array sources;
	Ref<PCGNode> node = get_node_by_id(p_id);
	if (node.is_null()) {
		return sources;
	}
	sources.resize(MAX(0, node->get_input_count()));
	sources.fill(-1);
	for (int i = 0; i < connections.size(); i++) {
		Dictionary c = connections[i];
		const int port = c.get("to_port", 0);
		if (int(c.get("to", -1)) == p_id && port >= 0 && port < sources.size()) {
			sources.set(port, c.get("from", -1));
		}
	}
	return sources;
}

PackedInt32Array PCGGraph::get_downstream(int p_id) const {
	PackedInt32Array out;
	for (int i = 0; i < connections.size(); i++) {
		Dictionary c = connections[i];
		if (int(c.get("from", -1)) == p_id) {
			const int to = c.get("to", -1);
			if (!out.has(to)) {
				out.push_back(to);
			}
		}
	}
	out.sort();
	return out;
}

PackedInt32Array PCGGraph::compute_order() const {
	PackedInt32Array ids = get_node_ids();
	HashMap<int, int> indegree;
	for (int i = 0; i < ids.size(); i++) {
		indegree[ids[i]] = 0;
	}
	for (int i = 0; i < connections.size(); i++) {
		Dictionary c = connections[i];
		const int from = c.get("from", -1);
		const int to = c.get("to", -1);
		if (indegree.has(from) && indegree.has(to)) {
			indegree[to] += 1;
		}
	}
	PackedInt32Array ready;
	for (int i = 0; i < ids.size(); i++) {
		if (indegree[ids[i]] == 0) {
			ready.push_back(ids[i]);
		}
	}
	PackedInt32Array order;
	while (!ready.is_empty()) {
		ready.sort();
		const int current = ready[0];
		ready.remove_at(0);
		order.push_back(current);
		PackedInt32Array next = get_downstream(current);
		for (int i = 0; i < next.size(); i++) {
			if (!indegree.has(next[i])) {
				continue;
			}
			// Count each connection, not each neighbour, so multi-port links resolve.
			for (int c_index = 0; c_index < connections.size(); c_index++) {
				Dictionary c = connections[c_index];
				if (int(c.get("from", -1)) == current && int(c.get("to", -1)) == next[i]) {
					indegree[next[i]] -= 1;
				}
			}
			if (indegree[next[i]] == 0) {
				ready.push_back(next[i]);
			}
		}
	}
	if (order.size() != ids.size()) {
		return PackedInt32Array();
	}
	return order;
}

bool PCGGraph::has_cycle() const {
	return !nodes.is_empty() && compute_order().is_empty();
}

int PCGGraph::resolve_output_node_id() const {
	if (output_node_id > 0 && get_node_by_id(output_node_id).is_valid()) {
		return output_node_id;
	}
	PackedInt32Array order = compute_order();
	return order.is_empty() ? -1 : order[order.size() - 1];
}

void PCGGraph::set_parameter(const StringName &p_name, const Variant &p_default) {
	parameters[p_name] = p_default;
	emit_changed();
}

void PCGGraph::remove_parameter(const StringName &p_name) {
	parameters.erase(p_name);
	emit_changed();
}

Dictionary PCGGraph::resolve_parameters(const Dictionary &p_overrides) const {
	Dictionary resolved = parameters.duplicate();
	Array keys = p_overrides.keys();
	for (int i = 0; i < keys.size(); i++) {
		resolved[keys[i]] = p_overrides[keys[i]];
	}
	return resolved;
}

PackedStringArray PCGGraph::validate() const {
	PackedStringArray problems;
	if (has_cycle()) {
		problems.push_back("Graph has a cycle.");
	}
	for (int i = 0; i < connections.size(); i++) {
		Dictionary c = connections[i];
		if (get_node_by_id(c.get("from", -1)).is_null() || get_node_by_id(c.get("to", -1)).is_null()) {
			problems.push_back(vformat("Connection %d references a missing node.", i));
		}
	}
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_null()) {
			problems.push_back(vformat("Node slot %d is empty.", i));
			continue;
		}
		Dictionary bindings = node->get_parameter_bindings();
		Array keys = bindings.keys();
		for (int k = 0; k < keys.size(); k++) {
			if (!parameters.has(bindings[keys[k]])) {
				problems.push_back(vformat("%s binds '%s' to unknown parameter '%s'.", node->get_title(), keys[k], bindings[keys[k]]));
			}
		}
	}
	return problems;
}

void PCGGraph::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_nodes", "nodes"), &PCGGraph::set_nodes);
	ClassDB::bind_method(D_METHOD("get_nodes"), &PCGGraph::get_nodes);
	ClassDB::bind_method(D_METHOD("set_connections", "connections"), &PCGGraph::set_connections);
	ClassDB::bind_method(D_METHOD("get_connections"), &PCGGraph::get_connections);
	ClassDB::bind_method(D_METHOD("set_parameters", "parameters"), &PCGGraph::set_parameters);
	ClassDB::bind_method(D_METHOD("get_parameters"), &PCGGraph::get_parameters);
	ClassDB::bind_method(D_METHOD("set_output_node_id", "id"), &PCGGraph::set_output_node_id);
	ClassDB::bind_method(D_METHOD("get_output_node_id"), &PCGGraph::get_output_node_id);
	ClassDB::bind_method(D_METHOD("add_node", "node"), &PCGGraph::add_node);
	ClassDB::bind_method(D_METHOD("remove_node", "id"), &PCGGraph::remove_node);
	ClassDB::bind_method(D_METHOD("get_node_by_id", "id"), &PCGGraph::get_node_by_id);
	ClassDB::bind_method(D_METHOD("get_node_count"), &PCGGraph::get_node_count);
	ClassDB::bind_method(D_METHOD("get_node_ids"), &PCGGraph::get_node_ids);
	ClassDB::bind_method(D_METHOD("connect_nodes", "from", "to", "to_port"), &PCGGraph::connect_nodes, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("disconnect_nodes", "from", "to", "to_port"), &PCGGraph::disconnect_nodes, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("is_connected_to", "from", "to", "to_port"), &PCGGraph::is_connected_to, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_input_sources", "id"), &PCGGraph::get_input_sources);
	ClassDB::bind_method(D_METHOD("get_downstream", "id"), &PCGGraph::get_downstream);
	ClassDB::bind_method(D_METHOD("compute_order"), &PCGGraph::compute_order);
	ClassDB::bind_method(D_METHOD("has_cycle"), &PCGGraph::has_cycle);
	ClassDB::bind_method(D_METHOD("resolve_output_node_id"), &PCGGraph::resolve_output_node_id);
	ClassDB::bind_method(D_METHOD("set_parameter", "name", "default"), &PCGGraph::set_parameter);
	ClassDB::bind_method(D_METHOD("remove_parameter", "name"), &PCGGraph::remove_parameter);
	ClassDB::bind_method(D_METHOD("resolve_parameters", "overrides"), &PCGGraph::resolve_parameters);
	ClassDB::bind_method(D_METHOD("validate"), &PCGGraph::validate);
	ClassDB::bind_method(D_METHOD("compute_fingerprint"), &PCGGraph::compute_fingerprint);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "nodes", PROPERTY_HINT_ARRAY_TYPE, "PCGNode"), "set_nodes", "get_nodes");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "connections"), "set_connections", "get_connections");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "parameters"), "set_parameters", "get_parameters");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "output_node_id"), "set_output_node_id", "get_output_node_id");
}

int64_t PCGGraph::compute_fingerprint() const {
	uint64_t h = pcg_mix64(0x504347475246ULL, (uint64_t)nodes.size());
	const PackedInt32Array ids = get_node_ids();
	Ref<PCGContext> none;
	for (int i = 0; i < ids.size(); i++) {
		Ref<PCGNode> node = get_node_by_id(ids[i]);
		h = pcg_mix64(h, (uint64_t)ids[i]);
		h = pcg_mix64(h, node->compute_param_hash(none));
	}
	for (int i = 0; i < connections.size(); i++) {
		Dictionary c = connections[i];
		h = pcg_mix64(h, (uint64_t)int(c.get("from", -1)));
		h = pcg_mix64(h, (uint64_t)int(c.get("to", -1)));
		h = pcg_mix64(h, (uint64_t)int(c.get("to_port", 0)));
	}
	Array keys = parameters.keys();
	keys.sort();
	for (int i = 0; i < keys.size(); i++) {
		h = pcg_mix64(h, (uint64_t)String(keys[i]).hash());
		h = pcg_mix64(h, (uint64_t)parameters[keys[i]].hash());
	}
	return (int64_t)pcg_mix64(h, (uint64_t)output_node_id);
}
