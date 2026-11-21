/**************************************************************************/
/*  runtime_object_profiler.h                                             */
/*  On-demand, bounded object population profiling for debug builds.     */
/*  SPDX-License-Identifier: MIT                                          */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

/**
 * Lightweight object-class census inspired by Unreal's obj list/MemReport.
 * The debugger's full ObjectDB snapshot serializes all properties; this
 * method only counts up to 32 requested EXACT native class names in one
 * ObjectDB traversal, without retaining objects or touching the scene tree.
 * Available only when Cgame's debug-only objectdb_profiler module is built.
 */
class ObjectDBRuntimeProfiler : public RefCounted {
	GDCLASS(ObjectDBRuntimeProfiler, RefCounted);

protected:
	static void _bind_methods();

public:
	// {"total": count, "classes": { "MeshInstance3D": count, ... }}
	// Empty dictionary on invalid filter input. No polling/timers.
	Dictionary sample_classes(const PackedStringArray &p_class_names) const;
};
