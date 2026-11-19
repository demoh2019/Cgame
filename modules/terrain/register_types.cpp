/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/

#include "register_types.h"

#include "terrain_3d.h"
#include "core/object/class_db.h"

#ifdef TOOLS_ENABLED
#include "editor/terrain_editor_plugin.h"
#endif

void initialize_terrain_module(ModuleInitializationLevel p_level) {
    if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(HeightmapTerrain3D);
    }
#ifdef TOOLS_ENABLED
    if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
        GDREGISTER_VIRTUAL_CLASS(Terrain3DEditorPlugin);
        EditorPlugins::add_by_type<Terrain3DEditorPlugin>();
    }
#endif
}

void uninitialize_terrain_module(ModuleInitializationLevel p_level) {
}
