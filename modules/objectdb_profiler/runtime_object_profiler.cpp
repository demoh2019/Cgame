/**************************************************************************/
/*  runtime_object_profiler.cpp                                           */
/*  On-demand, bounded object population profiling for debug builds.     */
/*  SPDX-License-Identifier: MIT                                          */
/**************************************************************************/
#include "runtime_object_profiler.h"

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"

namespace {

constexpr int MAX_CLASS_FILTERS = 32;

struct ClassCensus {
	HashMap<StringName, int> slots;
	Vector<int> counts;
	int total = 0;
};

// ObjectDB::debug_objects holds the ObjectDB lock while invoking this callback.
// Count by exact native class name, with no property serialization, Object
// retention, scene-tree visits or ObjectDB reentry from inside the callback.
static void count_object_class(Object *p_object, void *p_context) {
	ClassCensus *census = static_cast<ClassCensus *>(p_context);
	++census->total;
	const int *slot = census->slots.getptr(p_object->get_class_name());
	if (slot != nullptr) {
		census->counts.write[*slot] += 1;
	}
}

} // namespace

void ObjectDBRuntimeProfiler::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sample_classes", "class_names"), &ObjectDBRuntimeProfiler::sample_classes);
}

Dictionary ObjectDBRuntimeProfiler::sample_classes(const PackedStringArray &p_class_names) const {
	Dictionary invalid;
	const int count = p_class_names.size();
	if (count <= 0 || count > MAX_CLASS_FILTERS) {
		return invalid;
	}
	ClassCensus census;
	census.counts.resize(count);
	for (int i = 0; i < count; ++i) {
		const String class_string = p_class_names[i];
		if (class_string.is_empty() || class_string.length() > 128 ||
				class_string != class_string.strip_edges()) {
			return invalid;
		}
		const StringName name(class_string);
		if (census.slots.has(name)) {
			return invalid; // Duplicate keys would make before/after unstable.
		}
		census.slots.insert(name, i);
		census.counts.write[i] = 0;
	}
	// Single synchronized census. The profiler itself is counted as an
	// ObjectDB object; total and class counts correspond to the same pass.
	ObjectDB::debug_objects(count_object_class, &census);

	Dictionary classes;
	for (int i = 0; i < count; ++i) {
		classes[p_class_names[i]] = census.counts[i];
	}
	Dictionary result;
	result["total"] = census.total;
	result["classes"] = classes;
	return result;
}
