/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/
#include "register_types.h"

#ifndef _3D_DISABLED
#include "normal_variance_mipmaps.h"
#include "core/object/class_db.h"
#endif

void initialize_normal_variance_mipmaps_module(ModuleInitializationLevel p_level) {
#ifndef _3D_DISABLED
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(NormalVarianceMipmaps);
	}
#else
	(void)p_level;
#endif
}

void uninitialize_normal_variance_mipmaps_module(ModuleInitializationLevel p_level) {
	(void)p_level;
}
