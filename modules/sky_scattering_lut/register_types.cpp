/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/
#include "register_types.h"

#ifndef _3D_DISABLED
#include "sky_scattering_lut.h"
#include "core/object/class_db.h"
#endif

void initialize_sky_scattering_lut_module(ModuleInitializationLevel p_level) {
#ifndef _3D_DISABLED
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(SkyScatteringLUT);
	}
#else
	(void)p_level;
#endif
}

void uninitialize_sky_scattering_lut_module(ModuleInitializationLevel p_level) {
	(void)p_level;
}
