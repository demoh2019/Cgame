/**************************************************************************/
/*  register_types.cpp                                                      */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "register_types.h"

#include "pcg_instance_cluster_3d.h"
#include "pcg_path_falloff_3d.h"
#include "pcg_spatial_filter_2d.h"
#include "pcg_spatial_filter_3d.h"
#include "pcg_surface_filter_3d.h"
#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_pcg_instance_cluster_3d.h"
#include "tests/test_pcg_path_falloff_3d.h"
#include "tests/test_pcg_spatial_filter_2d.h"
#include "tests/test_pcg_spatial_filter_3d.h"
#include "tests/test_pcg_surface_filter_3d.h"
#endif

void initialize_procedural_scatter_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(PCGInstanceCluster3D);
	GDREGISTER_CLASS(PCGPathFalloff3D);
	GDREGISTER_CLASS(PCGSpatialFilter2D);
	GDREGISTER_CLASS(PCGSpatialFilter3D);
	GDREGISTER_CLASS(PCGSurfaceFilter3D);
}

void uninitialize_procedural_scatter_module(ModuleInitializationLevel p_level) {
}
