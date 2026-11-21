/**************************************************************************/
/*  test_runtime_object_profiler.h                                        */
/*  SPDX-License-Identifier: MIT                                          */
/**************************************************************************/
#pragma once

#include "../runtime_object_profiler.h"

#include "scene/3d/node_3d.h"
#include "tests/test_macros.h"

namespace TestObjectDBRuntimeProfiler {

TEST_CASE("[ObjectDBRuntimeProfiler] native class census detects object births and releases without retention") {
	Ref<ObjectDBRuntimeProfiler> profiler;
	profiler.instantiate();
	const PackedStringArray names = { "Node3D", "ObjectDBRuntimeProfiler", "MissingClassForCensusTest" };
	const Dictionary initial = profiler->sample_classes(names);
	REQUIRE(initial.has("total"));
	REQUIRE(initial.has("classes"));
	const Dictionary before = initial["classes"];
	CHECK(int(before["ObjectDBRuntimeProfiler"]) >= 1);
	CHECK(int(before["MissingClassForCensusTest"]) == 0);
	CHECK(int(initial["total"]) >= int(before["Node3D"]) + int(before["ObjectDBRuntimeProfiler"]));

	Node3D *temporary = memnew(Node3D);
	const Dictionary present = profiler->sample_classes(names);
	REQUIRE(present.has("classes"));
	const Dictionary while_alive = present["classes"];
	CHECK(int(while_alive["Node3D"]) == int(before["Node3D"]) + 1);
	CHECK(int(present["total"]) == int(initial["total"]) + 1);

	memdelete(temporary);
	const Dictionary restored = profiler->sample_classes(names);
	REQUIRE(restored.has("classes"));
	const Dictionary after = restored["classes"];
	CHECK(int(after["Node3D"]) == int(before["Node3D"]));
	CHECK(int(restored["total"]) == int(initial["total"]));
}

TEST_CASE("[ObjectDBRuntimeProfiler] invalid class filters are rejected before ObjectDB scan") {
	Ref<ObjectDBRuntimeProfiler> profiler;
	profiler.instantiate();
	CHECK(profiler->sample_classes(PackedStringArray()).is_empty());
	CHECK(profiler->sample_classes({ "Node3D", "Node3D" }).is_empty());
	CHECK(profiler->sample_classes({ "Node3D", "" }).is_empty());
	CHECK(profiler->sample_classes({ " Node3D" }).is_empty());
	CHECK(profiler->sample_classes({ "Node3D " }).is_empty());
	PackedStringArray too_many;
	for (int i = 0; i < 33; ++i) {
		too_many.push_back("Class" + itos(i));
	}
	CHECK(profiler->sample_classes(too_many).is_empty());
	// Request exactly 32 distinct classes and preserve the caller's keys,
	// including missing classes represented as zero.
	too_many.resize(32);
	const Dictionary maximum = profiler->sample_classes(too_many);
	REQUIRE(maximum.has("classes"));
	const Dictionary counts = maximum["classes"];
	CHECK(counts.size() == 32);
	for (int i = 0; i < 32; ++i) {
		CHECK(int(counts[too_many[i]]) == 0);
	}
}

} // namespace TestObjectDBRuntimeProfiler
