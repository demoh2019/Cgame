/**************************************************************************/
/*  grid_container.cpp                                                    */
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

#include "grid_container.h"

#include "core/object/class_db.h"
#include "core/templates/local_vector.h"
#include "scene/theme/theme_db.h"

void GridContainer::_resort() {
	// Dense scratch buffers avoid per-cell tree allocations during reflow.
	// Real column and row indices are contiguous. Trailing empty
	// columns are represented by a count rather than allocated entries.
	const int child_count = get_child_count();
	const int col_capacity = MIN(columns, child_count);
	const int row_capacity = child_count == 0 ? 0 : (child_count - 1) / columns + 1;
	LocalVector<int> col_minw;
	LocalVector<int> row_minh;
	LocalVector<int> col_desiredw;
	LocalVector<int> row_desiredh;
	LocalVector<int> col_maxw;
	LocalVector<int> row_maxh;
	col_minw.resize_initialized(col_capacity);
	col_desiredw.resize_initialized(col_capacity);
	col_maxw.resize_initialized(col_capacity);
	row_minh.resize_initialized(row_capacity);
	row_desiredh.resize_initialized(row_capacity);
	row_maxh.resize_initialized(row_capacity);
	LocalVector<uint8_t> col_expanded;
	LocalVector<uint8_t> row_expanded;
	col_expanded.resize_initialized(col_capacity);
	row_expanded.resize_initialized(row_capacity);
	int col_expanded_count = 0;
	int row_expanded_count = 0;

	// Compute the per-column/per-row data.
	int valid_controls_index = 0;
	Size2i size = Size2i(get_size());
	Size2i combined_max_size = Size2i(get_combined_maximum_size());

	for (int i = 0; i < child_count; i++) {
		Control *c = as_sortable_control(get_child(i));
		if (!c) {
			continue;
		}

		int row = valid_controls_index / columns;
		int col = valid_controls_index % columns;
		valid_controls_index++;

		Size2i ms = c->get_bound_minimum_size().ceil();
		Size2i desired_size = c->get_bound_desired_size().ceil();
		Size2i max_size = c->get_combined_maximum_size().floor();
		col_minw[col] = MAX(col_minw[col], ms.width);
		row_minh[row] = MAX(row_minh[row], ms.height);
		col_desiredw[col] = MAX(col_desiredw[col], desired_size.width);
		row_desiredh[row] = MAX(row_desiredh[row], desired_size.height);

		int max_width = int(max_size.width) >= 0 ? int(max_size.width) : (combined_max_size.width >= 0 ? combined_max_size.width : size.width);
		col_maxw[col] = MAX(col_maxw[col], max_width);

		int max_height = int(max_size.height) >= 0 ? int(max_size.height) : (combined_max_size.height >= 0 ? combined_max_size.height : size.height);
		row_maxh[row] = MAX(row_maxh[row], max_height);

		if (c->get_h_size_flags().has_flag(SIZE_EXPAND) && !col_expanded[col]) {
			col_expanded[col] = 1;
			col_expanded_count++;
		}
		if (c->get_v_size_flags().has_flag(SIZE_EXPAND) && !row_expanded[row]) {
			row_expanded[row] = 1;
			row_expanded_count++;
		}
	}

	const int max_col = MIN(valid_controls_index, columns);
	const int max_row = valid_controls_index == 0 ? 0 : (valid_controls_index - 1) / columns + 1;
	for (int i = 0; i < max_col; i++) {
		col_maxw[i] = MAX(col_maxw[i], col_minw[i]);
	}
	for (int i = 0; i < max_row; i++) {
		row_maxh[i] = MAX(row_maxh[i], row_minh[i]);
	}

	// Trailing empty columns have no nodes and do not need storage.
	// Keep their contribution to expansion as a count, not RBSet entries.
	int empty_expanded_columns = MAX(columns - valid_controls_index, 0);
	col_expanded_count += empty_expanded_columns;

	// Evaluate the remaining space for expanded columns/rows.
	Size2 remaining_space = get_size();
	Size2 empty_space = remaining_space;
	for (int i = 0; i < max_col; i++) {
		if (!col_expanded[i]) {
			remaining_space.width -= col_minw[i];
		}
		empty_space.width -= col_minw[i];
	}
	for (int i = 0; i < max_row; i++) {
		if (!row_expanded[i]) {
			remaining_space.height -= row_minh[i];
		}
		empty_space.height -= row_minh[i];
	}
	remaining_space.height -= theme_cache.v_separation * MAX(max_row - 1, 0);
	remaining_space.width -= theme_cache.h_separation * MAX(max_col - 1, 0);
	empty_space.height -= theme_cache.v_separation * MAX(max_row - 1, 0);
	empty_space.width -= theme_cache.h_separation * MAX(max_col - 1, 0);

	// Distribute the remaining space to cols/rows which have a desired size larger than their minimum size, up to their desired size, in proportion to how much extra space they want.
	int total_desired_extra_space = 0;
	for (int i = 0; i < max_col; i++) {
		int desired_extra_space = col_desiredw[i] - col_minw[i];
		if (desired_extra_space > 0) {
			total_desired_extra_space += desired_extra_space;
		}
	}
	if (empty_space.width > 0 && total_desired_extra_space > 0) {
		real_t space_available_ratio = MIN(real_t(empty_space.width) / real_t(total_desired_extra_space), 1.0);
		for (int i = 0; i < max_col; i++) {
			int desired_extra_space = col_desiredw[i] - col_minw[i];
			if (desired_extra_space > 0) {
				int desired_size_increase = floor(desired_extra_space * space_available_ratio);
				col_minw[i] += desired_size_increase;
				if (!col_expanded[i]) {
					remaining_space.width -= desired_size_increase;
				}
			}
		}
	}
	total_desired_extra_space = 0;
	for (int i = 0; i < max_row; i++) {
		int desired_extra_space = row_desiredh[i] - row_minh[i];
		if (desired_extra_space > 0) {
			total_desired_extra_space += desired_extra_space;
		}
	}
	if (empty_space.height > 0 && total_desired_extra_space > 0) {
		real_t space_available_ratio = MIN(real_t(empty_space.height) / real_t(total_desired_extra_space), 1.0);
		for (int i = 0; i < max_row; i++) {
			int desired_extra_space = row_desiredh[i] - row_minh[i];
			if (desired_extra_space > 0) {
				int desired_size_increase = floor(desired_extra_space * space_available_ratio);
				row_minh[i] += desired_size_increase;
				if (!row_expanded[i]) {
					remaining_space.height -= desired_size_increase;
				}
			}
		}
	}

	// Preserve the original 'largest minimum first' constraint removal.
	while (col_expanded_count > 0) {
		int max_index = -1;
		int max_minimum = 0;
		for (int i = 0; i < max_col; i++) {
			if (col_expanded[i] && (max_index == -1 || col_minw[i] > max_minimum)) {
				max_index = i;
				max_minimum = col_minw[i];
			}
		}
		if (empty_expanded_columns > 0 && (max_index == -1 || max_minimum < 0)) {
			max_index = max_col;
			max_minimum = 0;
		}
		if (remaining_space.width / col_expanded_count >= max_minimum) {
			break;
		}
		if (max_index == max_col) {
			// No empty column can reduce negative remaining space.
			col_expanded_count -= empty_expanded_columns;
			empty_expanded_columns = 0;
		} else {
			col_expanded[max_index] = 0;
			col_expanded_count--;
			remaining_space.width -= max_minimum;
		}
	}

	while (row_expanded_count > 0) {
		int max_index = -1;
		int max_minimum = 0;
		for (int i = 0; i < max_row; i++) {
			if (row_expanded[i] && (max_index == -1 || row_minh[i] > max_minimum)) {
				max_index = i;
				max_minimum = row_minh[i];
			}
		}
		if (remaining_space.height / row_expanded_count >= max_minimum) {
			break;
		}
		row_expanded[max_index] = 0;
		row_expanded_count--;
		remaining_space.height -= max_minimum;
	}

	// Cap at maximum sizes, redistributing the remainder to other cells.
	while (col_expanded_count > 0) {
		int capped_col = -1;
		for (int i = 0; i < max_col; i++) {
			if (col_expanded[i] && remaining_space.width / col_expanded_count > col_maxw[i]) {
				capped_col = i;
				break;
			}
		}
		if (capped_col < 0) {
			break;
		}
		col_expanded[capped_col] = 0;
		col_expanded_count--;
		remaining_space.width -= col_maxw[capped_col];
		col_minw[capped_col] = col_maxw[capped_col];
	}

	while (row_expanded_count > 0) {
		int capped_row = -1;
		for (int i = 0; i < max_row; i++) {
			if (row_expanded[i] && remaining_space.height / row_expanded_count > row_maxh[i]) {
				capped_row = i;
				break;
			}
		}
		if (capped_row < 0) {
			break;
		}
		row_expanded[capped_row] = 0;
		row_expanded_count--;
		remaining_space.height -= row_maxh[capped_row];
		row_minh[capped_row] = row_maxh[capped_row];
	}

	// Finally, fit the nodes.
	int col_remaining_pixel = 0;
	int col_expand = 0;
	if (col_expanded_count > 0) {
		col_expand = remaining_space.width / col_expanded_count;
		col_remaining_pixel = remaining_space.width - col_expanded_count * col_expand;
	}

	int row_remaining_pixel = 0;
	int row_expand = 0;
	if (row_expanded_count > 0) {
		row_expand = remaining_space.height / row_expanded_count;
		row_remaining_pixel = remaining_space.height - row_expanded_count * row_expand;
	}

	bool rtl = is_layout_rtl();

	int col_ofs = 0;
	int row_ofs = 0;

	// Calculate the index of rows and columns that receive the remaining pixel.
	int col_remaining_pixel_index = 0;
	for (int i = 0; i < max_col; i++) {
		if (col_remaining_pixel == 0) {
			break;
		}
		if (col_expanded[i]) {
			col_remaining_pixel_index = i + 1;
			col_remaining_pixel--;
		}
	}
	int row_remaining_pixel_index = 0;
	for (int i = 0; i < max_row; i++) {
		if (row_remaining_pixel == 0) {
			break;
		}
		if (row_expanded[i]) {
			row_remaining_pixel_index = i + 1;
			row_remaining_pixel--;
		}
	}

	valid_controls_index = 0;
	for (int i = 0; i < child_count; i++) {
		Control *c = as_sortable_control(get_child(i));
		if (!c) {
			continue;
		}
		int row = valid_controls_index / columns;
		int col = valid_controls_index % columns;
		valid_controls_index++;

		if (col == 0) {
			if (rtl) {
				col_ofs = get_size().width;
			} else {
				col_ofs = 0;
			}
			if (row > 0) {
				row_ofs += (row_expanded[row - 1] ? row_expand : row_minh[row - 1]) + theme_cache.v_separation;

				if (row_expanded[row - 1] && row - 1 < row_remaining_pixel_index) {
					// Apply the remaining pixel of the previous row.
					row_ofs++;
				}
			}
		}

		Size2 s(
				col_expanded[col] ? col_expand : col_minw[col],
				row_expanded[row] ? row_expand : row_minh[row]);

		// Add the remaining pixel to the expanding columns and rows, starting from left and top.
		if (col_expanded[col] && col < col_remaining_pixel_index) {
			s.x++;
		}
		if (row_expanded[row] && row < row_remaining_pixel_index) {
			s.y++;
		}

		if (rtl) {
			Point2 p(col_ofs - s.width, row_ofs);
			fit_child_in_rect(c, Rect2(p, s));
			col_ofs -= s.width + theme_cache.h_separation;
		} else {
			Point2 p(col_ofs, row_ofs);
			fit_child_in_rect(c, Rect2(p, s));
			col_ofs += s.width + theme_cache.h_separation;
		}
	}
}

void GridContainer::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_SORT_CHILDREN: {
			_resort();
			update_minimum_size();
		} break;

		case NOTIFICATION_THEME_CHANGED: {
			update_minimum_size();
		} break;

		case NOTIFICATION_TRANSLATION_CHANGED:
		case NOTIFICATION_LAYOUT_DIRECTION_CHANGED: {
			queue_sort();
		} break;
	}
}

void GridContainer::set_columns(int p_columns) {
	ERR_FAIL_COND(p_columns < 1);

	if (columns == p_columns) {
		return;
	}

	columns = p_columns;
	queue_sort();
	update_minimum_size();
}

int GridContainer::get_columns() const {
	return columns;
}

int GridContainer::get_h_separation() const {
	return theme_cache.h_separation;
}

void GridContainer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_columns", "columns"), &GridContainer::set_columns);
	ClassDB::bind_method(D_METHOD("get_columns"), &GridContainer::get_columns);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "columns", PROPERTY_HINT_RANGE, "1,1024,1"), "set_columns", "get_columns");

	BIND_THEME_ITEM(Theme::DATA_TYPE_CONSTANT, GridContainer, h_separation);
	BIND_THEME_ITEM(Theme::DATA_TYPE_CONSTANT, GridContainer, v_separation);
}

Size2 GridContainer::_get_minimum_size(bool p_use_desired_sizes) const {
	// Column and row indices are dense in [0, count). Avoid per-entry
	// RBMap allocations and logarithmic lookups during UI minimum-size
	// propagation, which can run repeatedly while building large scenes.
	const int child_count = get_child_count();
	LocalVector<int> col_minw;
	LocalVector<int> row_minh;
	col_minw.resize_initialized(MIN(columns, child_count));
	row_minh.resize_initialized(child_count == 0 ? 0 : (child_count - 1) / columns + 1);

	int max_row = 0;
	int max_col = 0;
	int valid_controls_index = 0;
	for (int i = 0; i < child_count; i++) {
		Control *c = as_sortable_control(get_child(i), SortableVisibilityMode::VISIBLE);
		if (!c) {
			continue;
		}
		const int row = valid_controls_index / columns;
		const int col = valid_controls_index % columns;
		valid_controls_index++;

		const Size2 min_size = p_use_desired_sizes ? c->get_bound_desired_size() : c->get_bound_minimum_size();
		const Size2 max_size = c->get_custom_maximum_size();
		const real_t col_width = (c->get_h_size_flags().has_flag(SIZE_MAXIMIZE) && max_size.width >= 0) ? max_size.width : min_size.width;
		const real_t row_height = (c->get_v_size_flags().has_flag(SIZE_MAXIMIZE) && max_size.height >= 0) ? max_size.height : min_size.height;

		// Preserve the old RBMap<int, int> conversion to integer pixels.
		col_minw[col] = MAX(col_minw[col], int(col_width));
		row_minh[row] = MAX(row_minh[row], int(row_height));
		max_col = MAX(col, max_col);
		max_row = MAX(row, max_row);
	}

	Size2 ms;
	const int used_columns = MIN(valid_controls_index, columns);
	const int used_rows = valid_controls_index == 0 ? 0 : (valid_controls_index - 1) / columns + 1;
	for (int col = 0; col < used_columns; col++) {
		ms.width += col_minw[col];
	}
	for (int row = 0; row < used_rows; row++) {
		ms.height += row_minh[row];
	}
	ms.height += theme_cache.v_separation * max_row;
	ms.width += theme_cache.h_separation * max_col;
	return ms;
}

Size2 GridContainer::get_minimum_size() const {
	return _get_minimum_size(false);
}

Size2 GridContainer::get_desired_size() const {
	return _get_minimum_size(true);
}
