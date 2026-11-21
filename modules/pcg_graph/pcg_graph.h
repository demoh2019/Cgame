/**************************************************************************/
/*  pcg_graph.h                                                           */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// A node-based procedural generation graph (Unreal "PCG Graph"). Nodes are
// PCGNode resources; connections feed one node's output into another node's
// input port. Exposed parameters are named defaults that PCGComponent3D and the
// executor can override per instance (PCG overrides).

#include "pcg_node.h"

#include "core/variant/typed_array.h"

class PCGGraph : public Resource {
	GDCLASS(PCGGraph, Resource);

	TypedArray<PCGNode> nodes;
	Array connections; // {"from": int, "to": int, "to_port": int}
	Dictionary parameters; // Exposed parameter name -> default value.
	int output_node_id = -1; // -1: the last node in evaluation order.
	int next_id = 1;

	bool _would_cycle(int p_from, int p_to) const;
	void _on_node_changed();

protected:
	static void _bind_methods();

public:
	void set_nodes(const TypedArray<PCGNode> &p_nodes);
	TypedArray<PCGNode> get_nodes() const { return nodes; }
	void set_connections(const Array &p_connections);
	Array get_connections() const { return connections; }
	void set_parameters(const Dictionary &p_parameters);
	Dictionary get_parameters() const { return parameters; }
	void set_output_node_id(int p_id);
	int get_output_node_id() const { return output_node_id; }

	int add_node(const Ref<PCGNode> &p_node);
	void remove_node(int p_id);
	Ref<PCGNode> get_node_by_id(int p_id) const;
	int get_node_count() const { return nodes.size(); }
	PackedInt32Array get_node_ids() const;

	Error connect_nodes(int p_from, int p_to, int p_to_port = 0);
	void disconnect_nodes(int p_from, int p_to, int p_to_port = 0);
	bool is_connected_to(int p_from, int p_to, int p_to_port = 0) const;
	// Source node id feeding each input port of p_id; -1 where nothing is connected.
	PackedInt32Array get_input_sources(int p_id) const;
	PackedInt32Array get_downstream(int p_id) const;

	// Dependency order (Kahn's algorithm, ties by id for determinism); empty when the graph has a cycle.
	PackedInt32Array compute_order() const;
	bool has_cycle() const;
	int resolve_output_node_id() const;

	void set_parameter(const StringName &p_name, const Variant &p_default);
	void remove_parameter(const StringName &p_name);
	// Overrides merged on top of the parameter defaults.
	Dictionary resolve_parameters(const Dictionary &p_overrides) const;
	PackedStringArray validate() const; // Human-readable problems (cycles, dangling links, bad bindings).
	// Stable across runs: node classes, parameters (defaults, no overrides), ids and connections.
	int64_t compute_fingerprint() const;
};
