/**************************************************************************/
/*  test_fuzzy_search.cpp                                                 */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_fuzzy_search)

#include "core/io/file_access.h"
#include "core/string/fuzzy_search.h"
#include "tests/test_utils.h"

namespace TestFuzzySearch {

struct FuzzySearchTestCase {
	String query;
	String expected;
};

// Ideally each of these test queries should represent a different aspect, and potentially bottleneck, of the search process.
const FuzzySearchTestCase test_cases[] = {
	// Short query, many matches, few adjacent characters
	{ "///gd", "./menu/menu/characters/dead_guy/dead_guy.gd" },
	// Filename match with typo
	{ "sm.png", "./entity/blood_sword/sam.png" },
	// Multipart filename word matches
	{ "ham ", "./entity/game_trap/ha_missed_me.wav" },
	// Single word token matches
	{ "push background", "./entity/background_zone1/background/push.png" },
	// Long token matches
	{ "background_freighter background png", "./entity/background_freighter/background/background.png" },
	// Many matches, many short tokens
	{ "menu menu characters wav", "./menu/menu/characters/smoker/0.wav" },
	// Maximize total matches
	{ "entity gd", "./entity/entity_man.gd" },
	// End of filename bonus (vs ".menu/widgets/toggle.gd")
	{ "gg", "./entity/background_freighter/Master.ogg" },
	// Exact filename start beats exact word boundary in the filename of a shorter path
	{ "fallback", "./menu/fonts/fallback_font.tres" },
	// Incomplete exact word at filename start beats exact complete word later in filename
	{ "me", "./menu/metal_text.tres" },
	// Exact word boundary in middle of a filename beats exact dirname start
	{ "floor", "./entity/background_freighter/background/background_floor.png" },
	// Exact match beats inexact filename start match (vs "./entity/background_zone_2/background/wall_overlay.png")
	{ "wor", "./entity/blood_sword/data.gd" },
	// Match starting on filename beats match later in filename (vs "./menu/ui_colors.tres")
	{ "colo.tres", "./menu/menu/characters/color.tres" }
};

Vector<String> load_test_data() {
	Ref<FileAccess> fp = FileAccess::open(TestUtils::get_data_path("fuzzy_search/project_dir_tree.txt"), FileAccess::READ);
	REQUIRE(fp.is_valid());
	return fp->get_as_utf8_string().split("\n");
}

TEST_CASE("[FuzzySearch] Test fuzzy search results") {
	FuzzySearch search;
	Vector<String> targets = load_test_data();

	for (FuzzySearchTestCase test_case : test_cases) {
		Vector<Ref<FuzzySearchMatch>> results = search.search_all(test_case.query, targets);
		CHECK_GT(results.size(), 0);
		CHECK_EQ(results[0]->get_target(), test_case.expected);
	}
}

TEST_CASE("[FuzzySearch] Reuse failed candidates without leaking token scores or matches") {
	FuzzySearch search;
	search.set_use_exact_tokens(true);
	search.set_filter_low_scores(false);

	Vector<String> targets;
	for (int i = 0; i < 256; i++) {
		targets.append("unrelated_" + itos(i) + ".gd");
	}
	// The first token matches but the second fails; this must not contaminate
	// the score, intervals or token matches of subsequent candidates.
	targets.append("alpha_only.gd");
	targets.append("beta_only.gd");
	targets.append("prefix_alpha_beta.gd");
	targets.append("alpha_without_second.gd");
	targets.append("prefix_beta_alpha.tscn");
	targets.append("alpha_beta_02.tscn");

	for (int i = 0; i < 256; i++) {
		targets.append("irrelevant_" + itos(i) + ".tscn");
	}

	Vector<Ref<FuzzySearchMatch>> results = search.search_all("alpha beta", targets);
	REQUIRE(results.size() == 3);

	bool seen[3] = { false, false, false };
	const int expected_indices[3] = { 258, 260, 261 };
	for (const Ref<FuzzySearchMatch> &result : results) {
		const int index = result->get_original_index();
		int expected_pos = -1;
		for (int i = 0; i < 3; i++) {
			if (expected_indices[i] == index) {
				expected_pos = i;
				break;
			}
		}
		REQUIRE(expected_pos != -1);
		CHECK_FALSE(seen[expected_pos]);
		seen[expected_pos] = true;

		Ref<FuzzySearchMatch> independent = search.search("alpha beta", targets[index]);
		REQUIRE(independent.is_valid());
		CHECK_EQ(result->get_target(), independent->get_target());
		CHECK_EQ(result->get_score(), independent->get_score());
		CHECK_EQ(result->get_matched_substrings().size(), independent->get_matched_substrings().size());
	}
	for (bool found : seen) {
		CHECK(found);
	}
}

TEST_CASE("[FuzzySearch] Length prefilter preserves miss budget and start offset semantics") {
	FuzzySearch search;
	search.set_filter_low_scores(false);
	search.set_max_misses(2);
	search.set_start_offset(1);

	Vector<String> targets;
	targets.append("_");
	targets.append("_abc");
	targets.append("_abf");
	targets.append("_abef");
	targets.append("_abcf");
	targets.append("_abcdef");
	targets.append("_abc_def");
	targets.append("_ABEF");
	targets.append("_xyzxyz");
	targets.append("_abcdef_extra");

	// Four matched characters are sufficient when two of six characters are missed.
	REQUIRE(search.search("abc def", "_abef").is_valid());
	CHECK(search.search("abc def", "_abf").is_null());

	for (bool exact : { false, true }) {
		search.set_use_exact_tokens(exact);
		Vector<Ref<FuzzySearchMatch>> results = search.search_all("abc def", targets);

		int expected_matches = 0;
		for (int i = 0; i < targets.size(); i++) {
			if (search.search("abc def", targets[i]).is_valid()) {
				expected_matches++;
			}
		}
		REQUIRE(results.size() == expected_matches);

		for (const Ref<FuzzySearchMatch> &result : results) {
			const int index = result->get_original_index();
			REQUIRE(index >= 0);
			REQUIRE(index < targets.size());
			Ref<FuzzySearchMatch> independent = search.search("abc def", targets[index]);
			REQUIRE(independent.is_valid());
			CHECK_EQ(result->get_target(), independent->get_target());
			CHECK_EQ(result->get_score(), independent->get_score());
			CHECK_EQ(result->get_matched_substrings().size(), independent->get_matched_substrings().size());
		}
	}

	CHECK_EQ(search.search_all("", targets).size(), 0);
	CHECK_EQ(search.search_all("   ", targets).size(), 0);
}

TEST_CASE("[FuzzySearch] Boundary scoring retains all ASCII separators") {
	FuzzySearch search;
	search.set_use_exact_tokens(true);
	search.set_case_sensitive(true);

	Ref<FuzzySearchMatch> inside_word = search.search("a", "x?ay");
	REQUIRE(inside_word.is_valid());

	const char *targets[] = {
		"x/ay",
		"x\\\\ay",
		"x-ay",
		"x_ay",
		"x.ay",
		"x ay",
	};

	for (const char *target : targets) {
		Ref<FuzzySearchMatch> at_boundary = search.search("a", target);
		REQUIRE(at_boundary.is_valid());
		CHECK_GT(at_boundary->get_score(), inside_word->get_score());
	}
}

} // namespace TestFuzzySearch
