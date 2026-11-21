/**************************************************************************/
/*  pcg_editor_logic.h                                                    */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// Pure (UI-free) helpers of the PCG graph editor, kept separate so they can be unit tested.

#include "core/math/color.h"
#include "core/string/ustring.h"
#include "core/templates/vector.h"

namespace PCGEditorLogic {

struct NodeEntry {
	String category;
	String title;
	String class_name;
};

inline bool entry_less(const NodeEntry &p_a, const NodeEntry &p_b) {
	if (p_a.category != p_b.category) {
		return p_a.category.naturalnocasecmp_to(p_b.category) < 0;
	}
	if (p_a.title != p_b.title) {
		return p_a.title.naturalnocasecmp_to(p_b.title) < 0;
	}
	return p_a.class_name < p_b.class_name;
}

// Stable insertion sort by (category, title, class); empty categories are reported as "General".
inline Vector<NodeEntry> sort_entries(const Vector<NodeEntry> &p_entries) {
	Vector<NodeEntry> out;
	for (int i = 0; i < p_entries.size(); i++) {
		NodeEntry entry = p_entries[i];
		if (entry.category.is_empty()) {
			entry.category = "General";
		}
		int at = out.size();
		while (at > 0 && entry_less(entry, out[at - 1])) {
			at--;
		}
		out.insert(at, entry);
	}
	return out;
}

// Distinct categories in sorted order.
inline Vector<String> category_list(const Vector<NodeEntry> &p_sorted) {
	Vector<String> categories;
	for (int i = 0; i < p_sorted.size(); i++) {
		if (categories.is_empty() || categories[categories.size() - 1] != p_sorted[i].category) {
			categories.push_back(p_sorted[i].category);
		}
	}
	return categories;
}

// Deterministic header color for a category (same name -> same color).
inline Color category_color(const String &p_category) {
	uint32_t h = 2166136261u;
	const String name = p_category.is_empty() ? String("General") : p_category;
	for (int i = 0; i < name.length(); i++) {
		h = (h ^ (uint32_t)name[i]) * 16777619u;
	}
	return Color::from_hsv(float(h % 360u) / 360.0f, 0.45f, 0.55f);
}

inline String format_duration_us(int64_t p_usec) {
	if (p_usec < 1000) {
		return vformat("%d us", p_usec);
	}
	if (p_usec < 1000000) {
		return vformat("%.2f ms", double(p_usec) / 1000.0);
	}
	return vformat("%.2f s", double(p_usec) / 1000000.0);
}

inline String format_point_badge(int p_count) {
	if (p_count < 0) {
		return String("- pts");
	}
	if (p_count >= 1000000) {
		return vformat("%.1fM pts", double(p_count) / 1000000.0);
	}
	if (p_count >= 10000) {
		return vformat("%.1fk pts", double(p_count) / 1000.0);
	}
	return vformat("%d pts", p_count);
}

} // namespace PCGEditorLogic
