/**************************************************************************/
/*  pcg_graph_editor_plugin.h                                             */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// Bottom-panel editor for PCGGraph resources (Unreal "PCG Graph Editor"), with live
// preview, debug point visualisation, profiling and an inspector Generate/Clear bar
// for PCGComponent3D.

#include "../pcg_component_3d.h"
#include "../pcg_graph.h"
#include "../pcg_graph_executor.h"
#include "pcg_editor_logic.h"

#include "core/templates/hash_map.h"
#include "editor/inspector/editor_inspector.h"
#include "editor/plugins/editor_plugin.h"
#include "scene/gui/box_container.h"

class Button;
class CheckButton;
class GraphEdit;
class GraphNode;
class Label;
class MenuButton;
class MeshInstance3D;
class PopupMenu;
class Timer;

class PCGGraphEditor : public VBoxContainer {
	GDCLASS(PCGGraphEditor, VBoxContainer);

	struct Snapshot {
		TypedArray<PCGNode> nodes;
		Array connections;
		int output_node_id = -1;
	};

	Ref<PCGGraph> graph;
	ObjectID component_id;
	ObjectID debug_mesh_id;
	Ref<PCGGraphExecutor> executor;
	Dictionary last_result;
	String last_signature;
	int selected_id = -1;
	bool rebuild_pending = false;
	bool inspecting = false;
	Vector2 pending_add_position;
	HashMap<int, Vector2> move_start_positions;
	Vector<PCGEditorLogic::NodeEntry> entries;
	HashMap<int, Label *> info_labels;

	GraphEdit *graph_edit = nullptr;
	MenuButton *add_button = nullptr;
	PopupMenu *context_menu = nullptr;
	Button *new_graph_button = nullptr;
	CheckButton *live_toggle = nullptr;
	CheckButton *debug_toggle = nullptr;
	Button *refresh_button = nullptr;
	Button *clear_cache_button = nullptr;
	Label *status_label = nullptr;
	Label *profile_label = nullptr;
	Timer *refresh_timer = nullptr;

	static String _node_name(int p_id);
	static int _node_id(const StringName &p_name);

	PCGComponent3D *_get_component() const;
	void _collect_node_classes();
	void _populate_menu(PopupMenu *p_menu);
	Ref<PCGNode> _instantiate_class(const String &p_class) const;
	String _structure_signature() const;
	Snapshot _snapshot() const;
	void _commit(const String &p_name, const Snapshot &p_before);
	Vector<int> _selected_ids() const;

	void _rebuild();
	void _queue_rebuild();
	void _graph_changed();
	void _refresh_info();
	void _run();
	Ref<PCGContext> _make_preview_context(bool p_debug) const;
	void _update_debug_mesh();
	void _clear_debug_mesh();

	void _add_node_pressed(int p_index);
	void _popup_request(const Vector2 &p_position);
	void _connection_request(const StringName &p_from, int p_from_port, const StringName &p_to, int p_to_port);
	void _disconnection_request(const StringName &p_from, int p_from_port, const StringName &p_to, int p_to_port);
	void _delete_nodes_request(const Array &p_names);
	void _duplicate_nodes_request();
	void _node_selected(Node *p_node);
	void _node_deselected(Node *p_node);
	void _begin_node_move();
	void _end_node_move();
	void _new_graph_pressed();
	void _toggle_changed(bool p_pressed);
	void _clear_cache_pressed();
	void _add_node_at(const String &p_class, const Vector2 &p_position);


public:
	void edit_graph(const Ref<PCGGraph> &p_graph, PCGComponent3D *p_component);
	Ref<PCGGraph> get_graph() const { return graph; }
	bool has_node_resource(const Object *p_node) const;
	void on_hidden();

	PCGGraphEditor();
	~PCGGraphEditor();
};

class PCGComponentInspectorPlugin : public EditorInspectorPlugin {
	GDCLASS(PCGComponentInspectorPlugin, EditorInspectorPlugin);

	void _on_generate(uint64_t p_object_id);
	void _on_clear(uint64_t p_object_id);

public:
	virtual bool can_handle(Object *p_object) override;
	virtual void parse_begin(Object *p_object) override;
};

class PCGGraphEditorPlugin : public EditorPlugin {
	GDCLASS(PCGGraphEditorPlugin, EditorPlugin);

	PCGGraphEditor *graph_editor = nullptr;
	Button *bottom_button = nullptr;
	Ref<PCGComponentInspectorPlugin> inspector_plugin;

public:
	virtual String get_plugin_name() const override { return "PCGGraph"; }
	virtual bool handles(Object *p_object) const override;
	virtual void edit(Object *p_object) override;
	virtual void make_visible(bool p_visible) override;

	PCGGraphEditorPlugin();
	~PCGGraphEditorPlugin();
};
