#pragma once
#include "../audio_occlusion_probe_planner.h"
#include "tests/test_macros.h"
#include <limits>

namespace TestAudioOcclusionProbePlanner {

TEST_CASE("[AudioOcclusionProbePlanner] Due times, urgency, priority and stable ties") {
	Ref<AudioOcclusionProbePlanner> p;
	p.instantiate();
	PackedFloat64Array due = { 0.4, 0.9, 0.0, 1.1 };
	PackedByteArray priorities = { 0, 3, 1, 3 };
	PackedFloat64Array audibility = { -20.0, -20.0, -30.0, 0.0 };
	PackedInt64Array ids = { 17, 11, 15, 18 };
	PackedInt32Array selected = p->select_due(due, priorities, audibility, ids, 1.0, 2);
	REQUIRE(selected.size() == 2);
	CHECK(selected[0] == 2);
	CHECK(selected[1] == 0);
	CHECK(p->select_due(due, priorities, audibility, ids, 0.1, 2).is_empty());
	CHECK(p->select_due(due, priorities, audibility, ids, 1.0, 0).is_empty());

	due = { 1.0, 1.0 };
	priorities = { 0, 3 };
	audibility = { -10.0, -80.0 };
	ids = { 15, 16 };
	selected = p->select_due(due, priorities, audibility, ids, 1.0, 1);
	REQUIRE(selected.size() == 1);
	CHECK(selected[0] == 1);
	priorities = { 0, 0 };
	selected = p->select_due(due, priorities, audibility, ids, 1.0, 1);
	CHECK(selected[0] == 0);
	audibility = { -20.0, -20.0 };
	ids = { 17, 11 };
	selected = p->select_due(due, priorities, audibility, ids, 1.0, 1);
	CHECK(selected[0] == 1);
}

TEST_CASE("[AudioOcclusionProbePlanner] Invalid snapshots fail closed") {
	Ref<AudioOcclusionProbePlanner> p;
	p.instantiate();
	PackedFloat64Array due = { 0.0, 0.2 };
	PackedByteArray priorities = { 0, 1 };
	PackedFloat64Array db = { -20.0, -40.0 };
	PackedInt64Array ids = { 11, 12 };
	CHECK(p->select_due(due, priorities, db, ids, 0.5, 1).size() == 1);
	CHECK(p->select_due(due, priorities, db, ids, -1.0, 1).is_empty());
	CHECK(p->select_due(due, priorities, db, ids, std::numeric_limits<double>::infinity(), 1).is_empty());
	CHECK(p->select_due(due, priorities, db, ids, 0.5, 17).is_empty());
	priorities.set(0, 4);
	CHECK(p->select_due(due, priorities, db, ids, 0.5, 1).is_empty());
	priorities.set(0, 0);
	db.set(0, std::numeric_limits<double>::quiet_NaN());
	CHECK(p->select_due(due, priorities, db, ids, 0.5, 1).is_empty());
	db.set(0, -20.0);
	ids.set(1, 11);
	CHECK(p->select_due(due, priorities, db, ids, 0.5, 1).is_empty());
	ids.set(1, 12);
	due.set(0, -1.0);
	CHECK(p->select_due(due, priorities, db, ids, 0.5, 1).is_empty());
}

TEST_CASE("[AudioOcclusionProbePlanner] Bounded probes do not starve quiet audio") {
	Ref<AudioOcclusionProbePlanner> p;
	p.instantiate();
	PackedFloat64Array due;
	PackedByteArray priorities;
	PackedFloat64Array db;
	PackedInt64Array ids;
	for (int i = 0; i < 12; ++i) {
		due.push_back(0.0);
		priorities.push_back(i < 9 ? 3 : 0);
		db.push_back(i < 9 ? 0.0 : -70.0);
		ids.push_back(i + 1);
	}
	int counts[12] = { 0 };
	for (int frame = 0; frame < 240; ++frame) {
		const double now = frame * (1.0 / 30.0);
		PackedInt32Array selected = p->select_due(due, priorities, db, ids, now, 3);
		CHECK(selected.size() <= 3);
		for (int idx : selected) {
			++counts[idx];
			due.set(idx, now + 0.25);
		}
	}
	for (int i = 0; i < 12; ++i) {
		CHECK(counts[i] >= 2);
	}
}
} // namespace TestAudioOcclusionProbePlanner
