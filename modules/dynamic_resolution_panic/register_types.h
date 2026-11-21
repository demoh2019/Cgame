/**************************************************************************/
/* register_types.h - Dynamic Resolution Panic module                      */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "modules/register_module_types.h"

void initialize_dynamic_resolution_panic_module(ModuleInitializationLevel p_level);
void uninitialize_dynamic_resolution_panic_module(ModuleInitializationLevel p_level);
