/**************************************************************************/
/*  test_pcg_editor_logic.h                                               */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#ifdef TOOLS_ENABLED

#include "../editor/pcg_editor_logic.h"

#include "tests/test_macros.h"

namespace TestPCGEditorLogic {

TEST_CASE("[PCGEditor] Node entries sort by category then title") {
	Vector<PCGEditorLogic::NodeEntry> entries;
	entries.push_back({ "Filter", "Slope", "A" });
	entries.push_back({ "Sampler", "Surface", "B" });
	entries.push_back({ "", "Zed", "C" });
	entries.push_back({ "Filter", "Density", "D" });
	Vector<PCGEditorLogic::NodeEntry> sorted = PCGEditorLogic::sort_entries(entries);
	REQUIRE(sorted.size() == 4);
	CHECK(sorted[0].title == "Density");
	CHECK(sorted[1].title == "Slope");
	CHECK(sorted[2].category == "General");
	CHECK(sorted[3].category == "Sampler");
	Vector<String> categories = PCGEditorLogic::category_list(sorted);
	REQUIRE(categories.size() == 3);
	CHECK(categories[0] == "Filter");
	CHECK(categories[2] == "Sampler");
}

TEST_CASE("[PCGEditor] Category colors are deterministic") {
	CHECK(PCGEditorLogic::category_color("Filter") == PCGEditorLogic::category_color("Filter"));
	CHECK(PCGEditorLogic::category_color("") == PCGEditorLogic::category_color("General"));
}

TEST_CASE("[PCGEditor] Duration and badge formatting") {
	CHECK(PCGEditorLogic::format_duration_us(12) == "12 us");
	CHECK(PCGEditorLogic::format_duration_us(2500) == "2.50 ms");
	CHECK(PCGEditorLogic::format_point_badge(-1) == "- pts");
	CHECK(PCGEditorLogic::format_point_badge(42) == "42 pts");
}

} // namespace TestPCGEditorLogic

#endif // TOOLS_ENABLED
