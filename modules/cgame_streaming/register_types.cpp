/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "register_types.h"

#include "navmesh_carving.h"
#include "navmesh_stitching.h"
#include "origin_rebasing.h"
#include "probe_volume.h"
#include "sh_lighting.h"
#include "stream_readiness_gate.h"
#include "stream_replication.h"
#include "stream_request_queue.h"
#include "virtual_shadow_pages.h"
#include "virtual_texture_page_cache.h"
#include "world_partition_bake.h"

#include "core/object/class_db.h"

void initialize_cgame_streaming_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(WorldPartitionBake);
	GDREGISTER_CLASS(OriginRebasing);
	GDREGISTER_CLASS(StreamRequestQueue);
	GDREGISTER_CLASS(StreamReadinessGate);
	GDREGISTER_CLASS(StreamReplication);
	GDREGISTER_CLASS(StreamReplicationClient);
	GDREGISTER_CLASS(NavMeshStitching);
	GDREGISTER_CLASS(NavMeshCarving);
	GDREGISTER_CLASS(SHLighting);
	GDREGISTER_CLASS(ProbeVolume);
	GDREGISTER_CLASS(VirtualTexturePageCache);
	GDREGISTER_CLASS(VirtualShadowPages);
}

void uninitialize_cgame_streaming_module(ModuleInitializationLevel p_level) {
}
