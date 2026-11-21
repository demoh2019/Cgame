/**************************************************************************/
/*  register_types.cpp                                                    */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "register_types.h"

#include "pcg_component_3d.h"
#include "pcg_core_nodes.h"
#include "pcg_data.h"
#include "pcg_graph.h"
#include "pcg_graph_executor.h"
#include "pcg_terrain_nodes.h"
#include "pcg_node.h"

#include "core/object/class_db.h"

#ifdef TOOLS_ENABLED
#include "editor/pcg_graph_editor_plugin.h"
#include "editor/plugins/editor_plugin.h"
#endif // TOOLS_ENABLED

void initialize_pcg_graph_module(ModuleInitializationLevel p_level) {
#ifdef TOOLS_ENABLED
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		EditorPlugins::add_by_type<PCGGraphEditorPlugin>();
	}
#endif // TOOLS_ENABLED
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(PCGData);
	GDREGISTER_CLASS(PCGPointData);
	GDREGISTER_CLASS(PCGSplineData);
	GDREGISTER_CLASS(PCGParamData);
	GDREGISTER_CLASS(PCGContext);
	GDREGISTER_CLASS(PCGNode);
	GDREGISTER_CLASS(PCGGraph);
	GDREGISTER_CLASS(PCGGraphExecutor);
	GDREGISTER_CLASS(PCGComponent3D);

	GDREGISTER_CLASS(PCGSurfaceSamplerNode);
	GDREGISTER_CLASS(PCGDensityNoiseNode);
	GDREGISTER_CLASS(PCGDensityFilterNode);
	GDREGISTER_CLASS(PCGSurfaceFilterNode);
	GDREGISTER_CLASS(PCGBiomeMaskNode);
	GDREGISTER_CLASS(PCGExclusionFilterNode);
	GDREGISTER_CLASS(PCGSpatialQueryNode);
	GDREGISTER_CLASS(PCGSelfPruneNode);
	GDREGISTER_CLASS(PCGTransformNode);
	GDREGISTER_CLASS(PCGMergeNode);
	GDREGISTER_CLASS(PCGSplineSamplerNode);
	GDREGISTER_CLASS(PCGPointSourceNode);
	GDREGISTER_CLASS(PCGAssetRuleNode);
	GDREGISTER_CLASS(PCGClusterNode);
	GDREGISTER_CLASS(PCGCountLimitNode);
	GDREGISTER_CLASS(PCGAttributeSetNode);
	GDREGISTER_CLASS(PCGOutputNode);
	register_pcg_terrain_nodes();
}

void uninitialize_pcg_graph_module(ModuleInitializationLevel p_level) {
}
