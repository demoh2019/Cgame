/**************************************************************************/
/*  pcg_graph_editor_plugin.cpp                                           */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_graph_editor_plugin.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/object/script_language.h"
#include "editor/editor_node.h"
#include "editor/editor_undo_redo_manager.h"
#include "editor/gui/editor_bottom_panel.h"
#include "editor/gui/editor_toaster.h"
#include "editor/themes/editor_scale.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/gui/button.h"
#include "scene/gui/check_button.h"
#include "scene/gui/graph_edit.h"
#include "scene/gui/graph_node.h"
#include "scene/gui/label.h"
#include "scene/gui/menu_button.h"
#include "scene/gui/popup_menu.h"
#include "scene/gui/scroll_container.h"
#include "scene/gui/split_container.h"
#include "scene/main/timer.h"
#include "scene/resources/immediate_mesh.h"
#include "scene/resources/material.h"
#include "scene/resources/style_box_flat.h"

static const char *PCG_DEBUG_MESH_NAME = "_PCGDebugPoints";

String PCGGraphEditor::_node_name(int p_id) {
	return "pcg_" + itos(p_id);
}

int PCGGraphEditor::_node_id(const StringName &p_name) {
	return String(p_name).get_slicec('_', 1).to_int();
}

PCGComponent3D *PCGGraphEditor::_get_component() const {
	if (component_id.is_null()) {
		return nullptr;
	}
	return ObjectDB::get_instance<PCGComponent3D>(component_id);
}

bool PCGGraphEditor::has_node_resource(const Object *p_node) const {
	if (graph.is_null() || p_node == nullptr) {
		return false;
	}
	TypedArray<PCGNode> nodes = graph->get_nodes();
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.ptr() == p_node) {
			return true;
		}
	}
	return false;
}

// ---------------------------------------------------------------- Node catalog

Ref<PCGNode> PCGGraphEditor::_instantiate_class(const String &p_class) const {
	Ref<PCGNode> result;
	if (ScriptServer::is_global_class(p_class)) {
		const StringName native = ScriptServer::get_global_class_native_base(p_class);
		Ref<Script> script = EditorNode::get_editor_data().script_class_load_script(p_class);
		Object *obj = ClassDB::instantiate(native);
		PCGNode *node = Object::cast_to<PCGNode>(obj);
		if (!node) {
			if (obj) {
				memdelete(obj);
			}
			return result;
		}
		result = Ref<PCGNode>(node);
		if (script.is_valid()) {
			result->set_script(script);
		}
		return result;
	}
	if (!ClassDB::can_instantiate(p_class)) {
		return result;
	}
	Object *obj = ClassDB::instantiate(p_class);
	PCGNode *node = Object::cast_to<PCGNode>(obj);
	if (!node) {
		if (obj) {
			memdelete(obj);
		}
		return result;
	}
	result = Ref<PCGNode>(node);
	return result;
}

void PCGGraphEditor::_collect_node_classes() {
	pending_add_position = Vector2(-1, -1);
	Vector<PCGEditorLogic::NodeEntry> raw;
	LocalVector<StringName> classes;
	ClassDB::get_inheriters_from_class("PCGNode", classes);
	classes.push_back("PCGNode");
	for (const StringName &cls : classes) {
		Ref<PCGNode> tmp = _instantiate_class(cls);
		if (tmp.is_null()) {
			continue;
		}
		raw.push_back({ tmp->get_category(), tmp->get_title(), String(cls) });
	}
	LocalVector<StringName> globals;
	ScriptServer::get_global_class_list(globals);
	for (const StringName &cls : globals) {
		const StringName native = ScriptServer::get_global_class_native_base(cls);
		if (!ClassDB::is_parent_class(native, "PCGNode") || ScriptServer::is_global_class_abstract(cls)) {
			continue;
		}
		Ref<PCGNode> tmp = _instantiate_class(cls);
		if (tmp.is_null()) {
			continue;
		}
		raw.push_back({ tmp->get_category(), String(cls), String(cls) });
	}
	entries = PCGEditorLogic::sort_entries(raw);
}

void PCGGraphEditor::_populate_menu(PopupMenu *p_menu) {
	p_menu->clear();
	String last_category;
	for (int i = 0; i < entries.size(); i++) {
		if (entries[i].category != last_category) {
			last_category = entries[i].category;
			p_menu->add_separator(last_category);
		}
		p_menu->add_item(entries[i].title, i);
	}
}

// ---------------------------------------------------------------- Undo / redo

PCGGraphEditor::Snapshot PCGGraphEditor::_snapshot() const {
	Snapshot snap;
	TypedArray<PCGNode> nodes = graph->get_nodes();
	for (int i = 0; i < nodes.size(); i++) {
		snap.nodes.push_back(nodes[i]);
	}
	snap.connections = graph->get_connections().duplicate(true);
	snap.output_node_id = graph->get_output_node_id();
	return snap;
}

// Records an action for a change that was already applied to the graph.
void PCGGraphEditor::_commit(const String &p_name, const Snapshot &p_before) {
	const Snapshot after = _snapshot();
	last_signature = _structure_signature();
	EditorUndoRedoManager *ur = EditorUndoRedoManager::get_singleton();
	ur->create_action(p_name, UndoRedo::MERGE_DISABLE, graph.ptr());
	ur->add_do_method(graph.ptr(), "set_nodes", after.nodes);
	ur->add_do_method(graph.ptr(), "set_connections", after.connections);
	ur->add_do_method(graph.ptr(), "set_output_node_id", after.output_node_id);
	ur->add_undo_method(graph.ptr(), "set_nodes", p_before.nodes);
	ur->add_undo_method(graph.ptr(), "set_connections", p_before.connections);
	ur->add_undo_method(graph.ptr(), "set_output_node_id", p_before.output_node_id);
	ur->commit_action(false);
	_queue_rebuild();
}

String PCGGraphEditor::_structure_signature() const {
	if (graph.is_null()) {
		return String();
	}
	String sig;
	TypedArray<PCGNode> nodes = graph->get_nodes();
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_null()) {
			continue;
		}
		const Vector2 pos = node->get_graph_position();
		sig += vformat("%d:%s:%s:%d:%d:%.1f,%.1f;", node->get_node_id(), node->get_class(), node->get_title(), node->get_input_count(), node->is_enabled() ? 1 : 0, pos.x, pos.y);
	}
	Array conns = graph->get_connections();
	for (int i = 0; i < conns.size(); i++) {
		Dictionary c = conns[i];
		sig += vformat("c%d>%d.%d;", int(c.get("from", -1)), int(c.get("to", -1)), int(c.get("to_port", 0)));
	}
	sig += vformat("o%d", graph->get_output_node_id());
	return sig;
}

Vector<int> PCGGraphEditor::_selected_ids() const {
	Vector<int> ids;
	for (int i = 0; i < graph_edit->get_child_count(); i++) {
		GraphNode *gn = Object::cast_to<GraphNode>(graph_edit->get_child(i));
		if (gn && gn->is_selected()) {
			ids.push_back(_node_id(gn->get_name()));
		}
	}
	return ids;
}

// ---------------------------------------------------------------- View

void PCGGraphEditor::_queue_rebuild() {
	if (rebuild_pending) {
		return;
	}
	rebuild_pending = true;
	callable_mp(this, &PCGGraphEditor::_rebuild).call_deferred();
}

void PCGGraphEditor::_rebuild() {
	rebuild_pending = false;
	const Vector<int> previous_selection = _selected_ids();

	graph_edit->clear_connections();
	info_labels.clear();
	for (int i = graph_edit->get_child_count() - 1; i >= 0; i--) {
		GraphNode *gn = Object::cast_to<GraphNode>(graph_edit->get_child(i));
		if (gn) {
			graph_edit->remove_child(gn);
			gn->queue_free();
		}
	}
	last_signature = _structure_signature();
	new_graph_button->set_visible(graph.is_null() && _get_component() != nullptr);
	add_button->set_disabled(graph.is_null());
	if (graph.is_null()) {
		status_label->set_text(TTR("No graph. Select a PCGGraph resource or a PCGComponent3D."));
		return;
	}

	TypedArray<PCGNode> nodes = graph->get_nodes();
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_null()) {
			continue;
		}
		const int id = node->get_node_id();
		GraphNode *gn = memnew(GraphNode);
		gn->set_name(_node_name(id));
		gn->set_title(vformat("%s  #%d", node->get_title(), id));
		gn->set_position_offset(node->get_graph_position());
		gn->set_resizable(false);
		if (!node->is_enabled()) {
			gn->set_modulate(Color(1, 1, 1, 0.5));
		}
		Ref<StyleBoxFlat> title_box;
		title_box.instantiate();
		title_box->set_bg_color(PCGEditorLogic::category_color(node->get_category()));
		title_box->set_content_margin_all(4 * EDSCALE);
		gn->add_theme_style_override("titlebar", title_box);
		gn->add_theme_style_override("titlebar_selected", title_box);

		const int inputs = node->get_input_count();
		const int rows = MAX(1, inputs);
		for (int r = 0; r < rows; r++) {
			Label *row = memnew(Label);
			if (inputs == 0) {
				row->set_text(TTR("Output"));
			} else if (r == 0) {
				row->set_text(vformat(TTR("In %d  >  Out"), r));
			} else {
				row->set_text(vformat(TTR("In %d"), r));
			}
			gn->add_child(row);
			gn->set_slot(r, r < inputs, 0, Color(0.9, 0.9, 0.9), r == 0, 0, Color(0.9, 0.9, 0.9));
		}
		Label *info = memnew(Label);
		info->add_theme_color_override("font_color", Color(0.75, 0.85, 1.0));
		gn->add_child(info);
		info_labels[id] = info;
		graph_edit->add_child(gn);
		if (previous_selection.has(id)) {
			gn->set_selected(true);
		}
	}

	Array conns = graph->get_connections();
	for (int i = 0; i < conns.size(); i++) {
		Dictionary c = conns[i];
		graph_edit->connect_node(_node_name(int(c.get("from", -1))), 0, _node_name(int(c.get("to", -1))), int(c.get("to_port", 0)));
	}
	_refresh_info();
}

void PCGGraphEditor::_refresh_info() {
	if (graph.is_null()) {
		return;
	}
	Dictionary timings = last_result.get("timings_usec", Dictionary());
	Dictionary counts = last_result.get("point_counts", Dictionary());
	const bool debug = debug_toggle->is_pressed();
	for (const KeyValue<int, Label *> &E : info_labels) {
		String text;
		if (debug && counts.has(E.key)) {
			text = PCGEditorLogic::format_point_badge(int(counts[E.key]));
		}
		if (timings.has(E.key)) {
			text += (text.is_empty() ? String() : String("   ")) + PCGEditorLogic::format_duration_us(int64_t(timings[E.key]));
		}
		E.value->set_text(text);
	}

	PackedStringArray problems = graph->validate();
	String status;
	if (problems.is_empty()) {
		status = TTR("Graph valid.");
	} else {
		status = vformat(TTR("%d problem(s): %s"), problems.size(), String(" | ").join(problems));
	}
	if (last_result.has("output")) {
		Ref<PCGPointData> out = last_result["output"];
		if (out.is_valid()) {
			status += vformat(TTR("   Output: %d points."), out->get_point_count());
		}
	}
	status_label->set_text(status);
	status_label->set_tooltip_text(status);

	if (last_result.has("total_usec")) {
		profile_label->set_text(PCGGraphExecutor::format_profile(graph, last_result));
	} else {
		profile_label->set_text(String());
	}
}

// ---------------------------------------------------------------- Preview / debug / profiling

Ref<PCGContext> PCGGraphEditor::_make_preview_context(bool p_debug) const {
	Ref<PCGContext> context;
	context.instantiate();
	context->set_debug(p_debug);
	PCGComponent3D *component = _get_component();
	if (component) {
		const Vector3 center = component->is_inside_tree() ? component->get_global_position() : Vector3();
		const Vector3 extents = component->get_extents();
		context->set_seed(component->get_generation_seed());
		context->set_bounds(AABB(center - extents, extents * 2.0));
		context->set_overrides(component->get_overrides());
		context->set_height_sampler(component->get_height_sampler());
		context->set_biome_sampler(component->get_biome_sampler());
		context->set_water_sampler(component->get_water_sampler());
		context->set_exclusions(component->get_exclusions());
		context->set_user_data(component->get_user_data());
	} else {
		// Bare graph: 64 x 64 preview area, no samplers.
		context->set_bounds(AABB(Vector3(-32, -64, -32), Vector3(64, 128, 64)));
	}
	return context;
}

void PCGGraphEditor::_run() {
	if (graph.is_null()) {
		return;
	}
	if (graph->has_cycle()) {
		last_result = Dictionary();
		_refresh_info();
		return;
	}
	PCGComponent3D *component = _get_component();
	const bool debug = debug_toggle->is_pressed();
	if (component && live_toggle->is_pressed()) {
		component->regenerate(); // Updates the 3D viewport.
	}
	if (component && !debug && live_toggle->is_pressed()) {
		last_result = component->get_last_profile();
	} else if (component || live_toggle->is_pressed() || debug) {
		// Own executor: bare-graph preview, or a debug run that keeps every node output.
		last_result = executor->execute(graph, _make_preview_context(debug));
	}
	_refresh_info();
	_update_debug_mesh();
}

void PCGGraphEditor::_clear_debug_mesh() {
	if (debug_mesh_id.is_valid()) {
		MeshInstance3D *mi = ObjectDB::get_instance<MeshInstance3D>(debug_mesh_id);
		if (mi) {
			if (mi->get_parent()) {
				mi->get_parent()->remove_child(mi);
			}
			memdelete(mi);
		}
		debug_mesh_id = ObjectID();
	}
}

void PCGGraphEditor::_update_debug_mesh() {
	PCGComponent3D *component = _get_component();
	if (!component || !debug_toggle->is_pressed() || selected_id < 0 || !last_result.has("node_outputs")) {
		_clear_debug_mesh();
		return;
	}
	Dictionary outputs = last_result["node_outputs"];
	if (!outputs.has(selected_id)) {
		_clear_debug_mesh();
		return;
	}
	Ref<PCGData> data = outputs[selected_id];

	MeshInstance3D *mi = debug_mesh_id.is_valid() ? ObjectDB::get_instance<MeshInstance3D>(debug_mesh_id) : nullptr;
	Ref<ImmediateMesh> mesh;
	if (!mi) {
		mi = memnew(MeshInstance3D);
		mi->set_name(PCG_DEBUG_MESH_NAME);
		mesh.instantiate();
		mi->set_mesh(mesh);
		mi->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		component->add_child(mi, false, Node::INTERNAL_MODE_FRONT);
		mi->set_as_top_level(true);
		mi->set_global_transform(Transform3D());
		debug_mesh_id = mi->get_instance_id();
	} else {
		mesh = mi->get_mesh();
	}
	if (mesh.is_null()) {
		return;
	}
	mesh->clear_surfaces();

	Ref<StandardMaterial3D> material;
	material.instantiate();
	material->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
	material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);

	Ref<PCGPointData> points = data;
	Ref<PCGSplineData> spline = data;
	if (points.is_valid() && points->get_point_count() > 0) {
		const int count = MIN(points->get_point_count(), 20000);
		const float s = 0.4f;
		mesh->surface_begin(Mesh::PRIMITIVE_LINES, material);
		for (int i = 0; i < count; i++) {
			const Vector3 p = points->get_position(i);
			const float d = CLAMP(points->get_density(i), 0.0f, 1.0f);
			const Color color(1.0f - d * 0.8f, 0.4f + d * 0.6f, 0.2f);
			const Vector3 axes[3] = { Vector3(s, 0, 0), Vector3(0, s, 0), Vector3(0, 0, s) };
			for (int a = 0; a < 3; a++) {
				mesh->surface_set_color(color);
				mesh->surface_add_vertex(p - axes[a]);
				mesh->surface_set_color(color);
				mesh->surface_add_vertex(p + axes[a]);
			}
		}
		mesh->surface_end();
	} else if (spline.is_valid() && spline->get_polyline_count() > 0) {
		mesh->surface_begin(Mesh::PRIMITIVE_LINES, material);
		const Color color(0.3f, 0.7f, 1.0f);
		for (int i = 0; i < spline->get_polyline_count(); i++) {
			PackedVector3Array line = spline->get_polyline(i);
			for (int j = 0; j + 1 < line.size(); j++) {
				mesh->surface_set_color(color);
				mesh->surface_add_vertex(line[j]);
				mesh->surface_set_color(color);
				mesh->surface_add_vertex(line[j + 1]);
			}
		}
		mesh->surface_end();
	}
}

// ---------------------------------------------------------------- Interaction

void PCGGraphEditor::_graph_changed() {
	if (graph.is_null()) {
		return;
	}
	if (_structure_signature() != last_signature) {
		_queue_rebuild();
	}
	refresh_timer->start(); // Debounce (0.25 s) before regenerating.
}

static Ref<PCGNode> _pcg_dup_node(const Ref<PCGNode> &p_node) {
	Ref<Resource> copy = p_node->duplicate();
	return Ref<PCGNode>(copy);
}

void PCGGraphEditor::_add_node_at(const String &p_class, const Vector2 &p_position) {
	if (graph.is_null()) {
		return;
	}
	Ref<PCGNode> node = _instantiate_class(p_class);
	if (node.is_null()) {
		EditorToaster::get_singleton()->popup_str(vformat(TTR("Cannot create PCG node '%s'."), p_class), EditorToaster::SEVERITY_ERROR);
		return;
	}
	const Snapshot before = _snapshot();
	node->set_graph_position(p_position);
	graph->add_node(node);
	_commit(TTR("Add PCG Node"), before);
}

void PCGGraphEditor::_add_node_pressed(int p_index) {
	if (p_index < 0 || p_index >= entries.size()) {
		return;
	}
	Vector2 at = pending_add_position;
	if (at == Vector2(-1, -1)) {
		at = (graph_edit->get_scroll_offset() + graph_edit->get_size() * 0.5) / graph_edit->get_zoom();
	}
	_add_node_at(entries[p_index].class_name, at);
	pending_add_position = Vector2(-1, -1);
}

void PCGGraphEditor::_popup_request(const Vector2 &p_position) {
	if (graph.is_null()) {
		return;
	}
	_collect_node_classes();
	_populate_menu(context_menu);
	pending_add_position = (graph_edit->get_scroll_offset() + p_position) / graph_edit->get_zoom();
	context_menu->set_position(graph_edit->get_screen_position() + p_position);
	context_menu->reset_size();
	context_menu->popup();
}

void PCGGraphEditor::_connection_request(const StringName &p_from, int p_from_port, const StringName &p_to, int p_to_port) {
	if (graph.is_null()) {
		return;
	}
	const Snapshot before = _snapshot();
	const Error err = graph->connect_nodes(_node_id(p_from), _node_id(p_to), p_to_port);
	if (err == ERR_CYCLIC_LINK) {
		EditorToaster::get_singleton()->popup_str(TTR("Connection rejected: it would create a cycle."), EditorToaster::SEVERITY_ERROR);
		return;
	}
	if (err != OK) {
		EditorToaster::get_singleton()->popup_str(TTR("Connection rejected."), EditorToaster::SEVERITY_WARNING);
		return;
	}
	_commit(TTR("Connect PCG Nodes"), before);
}

void PCGGraphEditor::_disconnection_request(const StringName &p_from, int p_from_port, const StringName &p_to, int p_to_port) {
	if (graph.is_null()) {
		return;
	}
	const Snapshot before = _snapshot();
	graph->disconnect_nodes(_node_id(p_from), _node_id(p_to), p_to_port);
	_commit(TTR("Disconnect PCG Nodes"), before);
}

void PCGGraphEditor::_delete_nodes_request(const Array &p_names) {
	if (graph.is_null() || p_names.is_empty()) {
		return;
	}
	const Snapshot before = _snapshot();
	for (int i = 0; i < p_names.size(); i++) {
		graph->remove_node(_node_id(p_names[i]));
	}
	if (selected_id >= 0 && graph->get_node_by_id(selected_id).is_null()) {
		selected_id = -1;
	}
	_commit(TTR("Delete PCG Nodes"), before);
}

void PCGGraphEditor::_duplicate_nodes_request() {
	if (graph.is_null()) {
		return;
	}
	const Vector<int> ids = _selected_ids();
	if (ids.is_empty()) {
		return;
	}
	const Snapshot before = _snapshot();
	HashMap<int, int> remap;
	for (int i = 0; i < ids.size(); i++) {
		Ref<PCGNode> source = graph->get_node_by_id(ids[i]);
		if (source.is_null()) {
			continue;
		}
		Ref<PCGNode> copy = _pcg_dup_node(source);
		if (copy.is_null()) {
			continue;
		}
		copy->set_node_id(-1);
		copy->set_graph_position(source->get_graph_position() + Vector2(40, 40));
		remap[ids[i]] = graph->add_node(copy);
	}
	// Keep links between duplicated nodes.
	Array conns = before.connections;
	for (int i = 0; i < conns.size(); i++) {
		Dictionary c = conns[i];
		const int from = int(c.get("from", -1));
		const int to = int(c.get("to", -1));
		if (remap.has(from) && remap.has(to)) {
			graph->connect_nodes(remap[from], remap[to], int(c.get("to_port", 0)));
		}
	}
	_commit(TTR("Duplicate PCG Nodes"), before);
}

void PCGGraphEditor::_node_selected(Node *p_node) {
	GraphNode *gn = Object::cast_to<GraphNode>(p_node);
	if (!gn || graph.is_null()) {
		return;
	}
	selected_id = _node_id(gn->get_name());
	Ref<PCGNode> node = graph->get_node_by_id(selected_id);
	if (node.is_valid()) {
		inspecting = true;
		EditorNode::get_singleton()->push_item(node.ptr());
		inspecting = false;
	}
	_update_debug_mesh();
}

void PCGGraphEditor::_node_deselected(Node *p_node) {
	GraphNode *gn = Object::cast_to<GraphNode>(p_node);
	if (gn && _node_id(gn->get_name()) == selected_id) {
		selected_id = -1;
		_update_debug_mesh();
	}
}

void PCGGraphEditor::_begin_node_move() {
	move_start_positions.clear();
	if (graph.is_null()) {
		return;
	}
	TypedArray<PCGNode> nodes = graph->get_nodes();
	for (int i = 0; i < nodes.size(); i++) {
		Ref<PCGNode> node = nodes[i];
		if (node.is_valid()) {
			move_start_positions[node->get_node_id()] = node->get_graph_position();
		}
	}
}

void PCGGraphEditor::_end_node_move() {
	if (graph.is_null()) {
		return;
	}
	Vector<int> moved;
	Vector<Vector2> new_positions;
	for (int i = 0; i < graph_edit->get_child_count(); i++) {
		GraphNode *gn = Object::cast_to<GraphNode>(graph_edit->get_child(i));
		if (!gn) {
			continue;
		}
		const int id = _node_id(gn->get_name());
		Ref<PCGNode> node = graph->get_node_by_id(id);
		if (node.is_null() || !move_start_positions.has(id)) {
			continue;
		}
		if (!node->get_graph_position().is_equal_approx(gn->get_position_offset())) {
			moved.push_back(id);
			new_positions.push_back(gn->get_position_offset());
		}
	}
	if (moved.is_empty()) {
		return;
	}
	EditorUndoRedoManager *ur = EditorUndoRedoManager::get_singleton();
	ur->create_action(TTR("Move PCG Nodes"), UndoRedo::MERGE_DISABLE, graph.ptr());
	for (int i = 0; i < moved.size(); i++) {
		Ref<PCGNode> node = graph->get_node_by_id(moved[i]);
		ur->add_do_method(node.ptr(), "set_graph_position", new_positions[i]);
		ur->add_undo_method(node.ptr(), "set_graph_position", move_start_positions[moved[i]]);
	}
	// Undo/redo of a move does not emit "changed"; do it so the view re-syncs (signature includes positions).
	ur->add_do_method(graph.ptr(), "emit_changed");
	ur->add_undo_method(graph.ptr(), "emit_changed");
	// Apply to the nodes now without triggering a rebuild, then record without re-executing.
	for (int i = 0; i < moved.size(); i++) {
		graph->get_node_by_id(moved[i])->set_graph_position(new_positions[i]);
	}
	last_signature = _structure_signature();
	ur->commit_action(false);
}

void PCGGraphEditor::_new_graph_pressed() {
	PCGComponent3D *component = _get_component();
	if (!component) {
		return;
	}
	Ref<PCGGraph> new_graph;
	new_graph.instantiate();
	EditorUndoRedoManager *ur = EditorUndoRedoManager::get_singleton();
	ur->create_action(TTR("Create PCG Graph"), UndoRedo::MERGE_DISABLE, component);
	ur->add_do_method(component, "set_graph", new_graph);
	ur->add_undo_method(component, "set_graph", component->get_graph());
	ur->commit_action();
	edit_graph(new_graph, component);
}

void PCGGraphEditor::_toggle_changed(bool p_pressed) {
	if (!debug_toggle->is_pressed()) {
		_clear_debug_mesh();
	}
	_run();
}

void PCGGraphEditor::_clear_cache_pressed() {
	executor->clear_cache();
	PCGComponent3D *component = _get_component();
	if (component && component->get_executor().is_valid()) {
		component->get_executor()->clear_cache();
	}
	_run();
}

// ---------------------------------------------------------------- Public

void PCGGraphEditor::edit_graph(const Ref<PCGGraph> &p_graph, PCGComponent3D *p_component) {
	if (graph.is_valid() && graph->is_connected(CoreStringName(changed), callable_mp(this, &PCGGraphEditor::_graph_changed))) {
		graph->disconnect(CoreStringName(changed), callable_mp(this, &PCGGraphEditor::_graph_changed));
	}
	if (graph != p_graph || _get_component() != p_component) {
		_clear_debug_mesh();
		selected_id = -1;
		last_result = Dictionary();
		executor->clear_cache();
	}
	graph = p_graph;
	component_id = p_component ? p_component->get_instance_id() : ObjectID();
	if (graph.is_valid()) {
		graph->connect(CoreStringName(changed), callable_mp(this, &PCGGraphEditor::_graph_changed));
	}
	_rebuild();
	if (graph.is_valid()) {
		refresh_timer->start();
	}
}

void PCGGraphEditor::on_hidden() {
	_clear_debug_mesh();
}

PCGGraphEditor::PCGGraphEditor() {
	pending_add_position = Vector2(-1, -1);
	executor.instantiate();
	set_name("PCGGraphEditor");

	HBoxContainer *toolbar = memnew(HBoxContainer);
	add_child(toolbar);

	add_button = memnew(MenuButton);
	add_button->set_text(TTR("Add Node"));
	add_button->set_flat(false);
	add_button->get_popup()->connect("about_to_popup", callable_mp(this, &PCGGraphEditor::_collect_node_classes));
	add_button->get_popup()->connect("about_to_popup", callable_mp(this, &PCGGraphEditor::_populate_menu).bind(add_button->get_popup()));
	add_button->get_popup()->connect("id_pressed", callable_mp(this, &PCGGraphEditor::_add_node_pressed));
	toolbar->add_child(add_button);

	new_graph_button = memnew(Button);
	new_graph_button->set_text(TTR("New Graph"));
	new_graph_button->connect("pressed", callable_mp(this, &PCGGraphEditor::_new_graph_pressed));
	new_graph_button->hide();
	toolbar->add_child(new_graph_button);

	live_toggle = memnew(CheckButton);
	live_toggle->set_text(TTR("Live Preview"));
	live_toggle->set_pressed(true);
	live_toggle->set_tooltip_text(TTR("Regenerate the PCGComponent3D (or run a 64x64 preview for a bare graph) shortly after every change."));
	live_toggle->connect("toggled", callable_mp(this, &PCGGraphEditor::_toggle_changed));
	toolbar->add_child(live_toggle);

	debug_toggle = memnew(CheckButton);
	debug_toggle->set_text(TTR("Debug"));
	debug_toggle->set_tooltip_text(TTR("Run with debug on: nodes show output point counts; selecting a node draws its output points in the 3D viewport."));
	debug_toggle->connect("toggled", callable_mp(this, &PCGGraphEditor::_toggle_changed));
	toolbar->add_child(debug_toggle);

	refresh_button = memnew(Button);
	refresh_button->set_text(TTR("Regenerate"));
	refresh_button->connect("pressed", callable_mp(this, &PCGGraphEditor::_run));
	toolbar->add_child(refresh_button);

	clear_cache_button = memnew(Button);
	clear_cache_button->set_text(TTR("Clear Cache"));
	clear_cache_button->connect("pressed", callable_mp(this, &PCGGraphEditor::_clear_cache_pressed));
	toolbar->add_child(clear_cache_button);

	status_label = memnew(Label);
	status_label->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	status_label->set_text_overrun_behavior(TextServer::OVERRUN_TRIM_ELLIPSIS);
	toolbar->add_child(status_label);

	HSplitContainer *split = memnew(HSplitContainer);
	split->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	add_child(split);

	graph_edit = memnew(GraphEdit);
	graph_edit->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	graph_edit->set_right_disconnects(true);
	graph_edit->set_minimap_enabled(true);
	graph_edit->connect("connection_request", callable_mp(this, &PCGGraphEditor::_connection_request));
	graph_edit->connect("disconnection_request", callable_mp(this, &PCGGraphEditor::_disconnection_request));
	graph_edit->connect("delete_nodes_request", callable_mp(this, &PCGGraphEditor::_delete_nodes_request));
	graph_edit->connect("duplicate_nodes_request", callable_mp(this, &PCGGraphEditor::_duplicate_nodes_request));
	graph_edit->connect("node_selected", callable_mp(this, &PCGGraphEditor::_node_selected));
	graph_edit->connect("node_deselected", callable_mp(this, &PCGGraphEditor::_node_deselected));
	graph_edit->connect("popup_request", callable_mp(this, &PCGGraphEditor::_popup_request));
	graph_edit->connect("begin_node_move", callable_mp(this, &PCGGraphEditor::_begin_node_move));
	graph_edit->connect("end_node_move", callable_mp(this, &PCGGraphEditor::_end_node_move));
	split->add_child(graph_edit);

	context_menu = memnew(PopupMenu);
	context_menu->connect("id_pressed", callable_mp(this, &PCGGraphEditor::_add_node_pressed));
	add_child(context_menu);

	VBoxContainer *side = memnew(VBoxContainer);
	side->set_custom_minimum_size(Size2(280 * EDSCALE, 0));
	Label *profile_title = memnew(Label);
	profile_title->set_text(TTR("Profile"));
	side->add_child(profile_title);
	ScrollContainer *scroll = memnew(ScrollContainer);
	scroll->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	side->add_child(scroll);
	profile_label = memnew(Label);
	scroll->add_child(profile_label);
	split->add_child(side);

	refresh_timer = memnew(Timer);
	refresh_timer->set_one_shot(true);
	refresh_timer->set_wait_time(0.25);
	refresh_timer->connect("timeout", callable_mp(this, &PCGGraphEditor::_run));
	add_child(refresh_timer);

	status_label->set_text(TTR("No graph. Select a PCGGraph resource or a PCGComponent3D."));
}

PCGGraphEditor::~PCGGraphEditor() {
	// The debug mesh belongs to the edited scene; it is removed in on_hidden().
}

// ---------------------------------------------------------------- Inspector plugin

bool PCGComponentInspectorPlugin::can_handle(Object *p_object) {
	return Object::cast_to<PCGComponent3D>(p_object) != nullptr;
}

void PCGComponentInspectorPlugin::parse_begin(Object *p_object) {
	HBoxContainer *bar = memnew(HBoxContainer);
	Button *generate = memnew(Button);
	generate->set_text(TTR("Generate"));
	generate->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	generate->connect("pressed", callable_mp(this, &PCGComponentInspectorPlugin::_on_generate).bind((uint64_t)p_object->get_instance_id()));
	bar->add_child(generate);
	Button *clear = memnew(Button);
	clear->set_text(TTR("Clear"));
	clear->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	clear->connect("pressed", callable_mp(this, &PCGComponentInspectorPlugin::_on_clear).bind((uint64_t)p_object->get_instance_id()));
	bar->add_child(clear);
	add_custom_control(bar);
}

void PCGComponentInspectorPlugin::_on_generate(uint64_t p_object_id) {
	PCGComponent3D *component = ObjectDB::get_instance<PCGComponent3D>(ObjectID(p_object_id));
	if (!component) {
		return;
	}
	if (component->get_graph().is_null()) {
		EditorToaster::get_singleton()->popup_str(TTR("PCGComponent3D has no graph."), EditorToaster::SEVERITY_WARNING);
		return;
	}
	component->regenerate();
	Ref<PCGPointData> points = component->get_all_points();
	EditorToaster::get_singleton()->popup_str(vformat(TTR("PCG generated %d points."), points.is_valid() ? points->get_point_count() : 0), EditorToaster::SEVERITY_INFO);
}

void PCGComponentInspectorPlugin::_on_clear(uint64_t p_object_id) {
	PCGComponent3D *component = ObjectDB::get_instance<PCGComponent3D>(ObjectID(p_object_id));
	if (component) {
		component->clear();
	}
}

// ---------------------------------------------------------------- Plugin

bool PCGGraphEditorPlugin::handles(Object *p_object) const {
	if (Object::cast_to<PCGGraph>(p_object) || Object::cast_to<PCGComponent3D>(p_object)) {
		return true;
	}
	// Keep the panel while one of the graph's nodes is shown in the inspector.
	return graph_editor->has_node_resource(p_object);
}

void PCGGraphEditorPlugin::edit(Object *p_object) {
	if (PCGGraph *g = Object::cast_to<PCGGraph>(p_object)) {
		graph_editor->edit_graph(Ref<PCGGraph>(g), nullptr);
	} else if (PCGComponent3D *c = Object::cast_to<PCGComponent3D>(p_object)) {
		graph_editor->edit_graph(c->get_graph(), c);
	}
	// PCGNode selections come from the graph itself; nothing to do.
}

void PCGGraphEditorPlugin::make_visible(bool p_visible) {
	if (p_visible) {
		bottom_button->show();
		EditorNode::get_bottom_panel()->make_item_visible(graph_editor, true);
	} else {
		bottom_button->hide();
		EditorNode::get_bottom_panel()->make_item_visible(graph_editor, false);
		graph_editor->on_hidden();
	}
}

PCGGraphEditorPlugin::PCGGraphEditorPlugin() {
	graph_editor = memnew(PCGGraphEditor);
	graph_editor->set_custom_minimum_size(Size2(0, 320 * EDSCALE));
	bottom_button = EditorNode::get_bottom_panel()->add_item(TTR("PCG Graph"), graph_editor);
	bottom_button->hide();

	inspector_plugin.instantiate();
	EditorInspector::add_inspector_plugin(inspector_plugin);
}

PCGGraphEditorPlugin::~PCGGraphEditorPlugin() {
	if (inspector_plugin.is_valid()) {
		EditorInspector::remove_inspector_plugin(inspector_plugin);
	}
}
