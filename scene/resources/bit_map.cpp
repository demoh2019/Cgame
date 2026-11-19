/**************************************************************************/
/*  bit_map.cpp                                                           */
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

#include "bit_map.h"

#include "core/object/class_db.h"
#include "core/templates/local_vector.h"
#include "core/variant/typed_array.h"

#include <cmath>

void BitMap::create(const Size2i &p_size) {
	ERR_FAIL_COND(p_size.width < 1);
	ERR_FAIL_COND(p_size.height < 1);

	ERR_FAIL_COND(static_cast<int64_t>(p_size.width) * static_cast<int64_t>(p_size.height) > INT32_MAX);

	Error err = bitmask.resize(Math::division_round_up(p_size.width * p_size.height, 8));
	ERR_FAIL_COND(err != OK);

	width = p_size.width;
	height = p_size.height;

	memset(bitmask.ptrw(), 0, bitmask.size());
}

void BitMap::create_from_image_alpha(const Ref<Image> &p_image, float p_threshold) {
	ERR_FAIL_COND(p_image.is_null() || p_image->is_empty());
	// Already-LA8 images can be read directly. Only duplicate before a
	// format conversion, which must never mutate the caller's Image.
	Ref<Image> img = p_image;
	if (img->get_format() != Image::FORMAT_LA8) {
		img = img->duplicate();
		img->convert(Image::FORMAT_LA8);
	}
	ERR_FAIL_COND(img->get_format() != Image::FORMAT_LA8);

	create(Size2i(img->get_width(), img->get_height()));

	const uint8_t *r = img->get_data().ptr();
	uint8_t *w = bitmask.ptrw();
	const int pixels = width * height;

	// Small alpha masks avoid the cutoff setup and are often used for
	// tiny collision and navigation resources.
	if (pixels < 256) {
		for (int i = 0; i < pixels; i++) {
			if (r[i * 2 + 1] / 255.0 > p_threshold) {
				w[i >> 3] |= uint8_t(1u << (i & 7));
			}
		}
		return;
	}

	// Alpha has only 256 discrete values. Find the first value satisfying
	// the original floating-point comparison once, rather than dividing
	// every pixel by 255. This also preserves NaN/negative thresholds.
	int first_opaque_alpha = 0;
	while (first_opaque_alpha < 256 && !(first_opaque_alpha / 255.0 > p_threshold)) {
		first_opaque_alpha++;
	}

	// All transparent and all opaque inputs can be handled in one fill.
	// Preserve the zeroed padding bits in the final partial byte.
	const int full_bytes = pixels >> 3;
	const int remaining = pixels & 7;
	if (first_opaque_alpha == 256) {
		return;
	}
	if (first_opaque_alpha == 0) {
		memset(w, 0xff, full_bytes);
		if (remaining > 0) {
			w[full_bytes] = uint8_t((1u << remaining) - 1);
		}
		return;
	}

	// Assemble eight destination bits at a time, using sequential reads
	// of the LA8 image.
	for (int byte_index = 0; byte_index < full_bytes; byte_index++) {
		const uint8_t *alpha = r + (byte_index << 4) + 1;
		uint8_t packed = 0;
		for (int bit = 0; bit < 8; bit++) {
			packed |= uint8_t((alpha[bit << 1] >= first_opaque_alpha) << bit);
		}
		w[byte_index] = packed;
	}
	if (remaining > 0) {
		const uint8_t *alpha = r + (full_bytes << 4) + 1;
		uint8_t packed = 0;
		for (int bit = 0; bit < remaining; bit++) {
			packed |= uint8_t((alpha[bit << 1] >= first_opaque_alpha) << bit);
		}
		w[full_bytes] = packed;
	}
}

void BitMap::set_bit_rect(const Rect2i &p_rect, bool p_value) {
	const Rect2i current = Rect2i(0, 0, width, height).intersection(p_rect);
	if (current.size.x <= 0 || current.size.y <= 0) {
		return;
	}

	uint8_t *data = bitmask.ptrw();
	if (current.position == Point2i() && current.size == Size2i(width, height)) {
		// A full-map rectangle is a single contiguous bit range. Replace
		// one row-at-a-time memset with one bulk fill, while preserving
		// padding bits in a partially filled final byte.
		const int bytes = bitmask.size();
		const int tail_bits = (width * height) & 7;
		if (tail_bits == 0) {
			memset(data, p_value ? 0xff : 0, bytes);
		} else {
			const uint8_t tail_mask = uint8_t((1u << tail_bits) - 1);
			const uint8_t old_padding = data[bytes - 1] & uint8_t(~tail_mask);
			memset(data, p_value ? 0xff : 0, bytes - 1);
			data[bytes - 1] = old_padding | (p_value ? tail_mask : 0);
		}
		return;
	}
	// BitMap rows share bytes when the width is not a multiple of eight.
	// Keep the boundary bits intact and fill whole interior bytes at once.
	int64_t start_bit = int64_t(width) * current.position.y + current.position.x;
	for (int row = 0; row < current.size.y; row++) {
		const int64_t end_bit = start_bit + current.size.x - 1;
		const int first_byte = int(start_bit >> 3);
		const int last_byte = int(end_bit >> 3);
		const uint8_t first_mask = uint8_t(0xffu << (start_bit & 7));
		const uint8_t last_mask = uint8_t(0xffu >> (7 - (end_bit & 7)));

		if (first_byte == last_byte) {
			const uint8_t mask = first_mask & last_mask;
			if (p_value) {
				data[first_byte] |= mask;
			} else {
				data[first_byte] &= uint8_t(~mask);
			}
		} else {
			if (p_value) {
				data[first_byte] |= first_mask;
				data[last_byte] |= last_mask;
			} else {
				data[first_byte] &= uint8_t(~first_mask);
				data[last_byte] &= uint8_t(~last_mask);
			}
			if (last_byte - first_byte > 1) {
				memset(data + first_byte + 1, p_value ? 0xff : 0, last_byte - first_byte - 1);
			}
		}
		start_bit += width;
	}
}

int BitMap::get_true_bit_count() const {
	const int size = bitmask.size();
	const uint8_t *data = bitmask.ptr();
	int count = 0;
	int i = 0;

	// Count eight packed bytes per iteration without alignment assumptions,
	// platform-specific intrinsics, or an auxiliary lookup table.
	for (; i + 8 <= size; i += 8) {
		uint64_t bits;
		memcpy(&bits, data + i, sizeof(bits));
		bits -= (bits >> 1) & 0x5555555555555555ULL;
		bits = (bits & 0x3333333333333333ULL) + ((bits >> 2) & 0x3333333333333333ULL);
		bits = (bits + (bits >> 4)) & 0x0f0f0f0f0f0f0f0fULL;
		count += int((bits * 0x0101010101010101ULL) >> 56);
	}
	for (; i < size; i++) {
		uint32_t bits = data[i];
		bits -= (bits >> 1) & 0x55u;
		bits = (bits & 0x33u) + ((bits >> 2) & 0x33u);
		count += (bits + (bits >> 4)) & 0x0fu;
	}
	return count;
}

void BitMap::set_bitv(const Point2i &p_pos, bool p_value) {
	set_bit(p_pos.x, p_pos.y, p_value);
}

void BitMap::set_bit(int p_x, int p_y, bool p_value) {
	ERR_FAIL_INDEX(p_x, width);
	ERR_FAIL_INDEX(p_y, height);

	int ofs = width * p_y + p_x;
	int bbyte = ofs / 8;
	int bbit = ofs % 8;

	uint8_t b = bitmask[bbyte];

	if (p_value) {
		b |= (1 << bbit);
	} else {
		b &= ~(1 << bbit);
	}

	bitmask.write[bbyte] = b;
}

bool BitMap::get_bitv(const Point2i &p_pos) const {
	return get_bit(p_pos.x, p_pos.y);
}

bool BitMap::get_bit(int p_x, int p_y) const {
	ERR_FAIL_INDEX_V(p_x, width, false);
	ERR_FAIL_INDEX_V(p_y, height, false);

	int ofs = width * p_y + p_x;
	int bbyte = ofs / 8;
	int bbit = ofs % 8;

	return (bitmask[bbyte] & (1 << bbit)) != 0;
}

Size2i BitMap::get_size() const {
	return Size2i(width, height);
}

void BitMap::_set_data(const Dictionary &p_d) {
	ERR_FAIL_COND(!p_d.has("size"));
	ERR_FAIL_COND(!p_d.has("data"));

	create(p_d["size"]);
	bitmask = p_d["data"];
}

Dictionary BitMap::_get_data() const {
	Dictionary d;
	d["size"] = get_size();
	d["data"] = bitmask;
	return d;
}

Vector<Vector<Vector2>> BitMap::_march_square(const Rect2i &p_rect, const Point2i &p_start) const {
	int stepx = 0;
	int stepy = 0;
	int prevx = 0;
	int prevy = 0;
	int startx = p_start.x;
	int starty = p_start.y;
	int curx = startx;
	int cury = starty;
	unsigned int count = 0;

	HashMap<Point2i, int> cross_map;

	Vector<Vector2> _points;
	int points_size = 0;

	Vector<Vector<Vector2>> ret;

	// Add starting entry at start of return.
	ret.resize(1);

	do {
		int sv = 0;
		{ // Square value

			/*
			checking the 2x2 pixel grid, assigning these values to each pixel, if not transparent
			+---+---+
			| 1 | 2 |
			+---+---+
			| 4 | 8 | <- current pixel (curx,cury)
			+---+---+
			*/
			Point2i tl = Point2i(curx - 1, cury - 1);
			sv += (p_rect.has_point(tl) && get_bitv(tl)) ? 1 : 0;
			Point2i tr = Point2i(curx, cury - 1);
			sv += (p_rect.has_point(tr) && get_bitv(tr)) ? 2 : 0;
			Point2i bl = Point2i(curx - 1, cury);
			sv += (p_rect.has_point(bl) && get_bitv(bl)) ? 4 : 0;
			Point2i br = Point2i(curx, cury);
			sv += (p_rect.has_point(br) && get_bitv(br)) ? 8 : 0;
			ERR_FAIL_COND_V(sv == 0 || sv == 15, Vector<Vector<Vector2>>());
		}

		switch (sv) {
			case 1:
			case 5:
			case 13:
				/* going UP with these cases:
				1          5           13
				+---+---+  +---+---+  +---+---+
				| 1 |   |  | 1 |   |  | 1 |   |
				+---+---+  +---+---+  +---+---+
				|   |   |  | 4 |   |  | 4 | 8 |
				+---+---+  +---+---+  +---+---+
				*/
				stepx = 0;
				stepy = -1;
				break;

			case 8:
			case 10:
			case 11:
				/* going DOWN with these cases:
				8          10         11
				+---+---+  +---+---+  +---+---+
				|   |   |  |   | 2 |  | 1 | 2 |
				+---+---+  +---+---+  +---+---+
				|   | 8 |  |   | 8 |  |   | 8 |
				+---+---+  +---+---+  +---+---+
				*/
				stepx = 0;
				stepy = 1;
				break;

			case 4:
			case 12:
			case 14:
				/* going LEFT with these cases:
				4          12         14
				+---+---+  +---+---+  +---+---+
				|   |   |  |   |   |  |   | 2 |
				+---+---+  +---+---+  +---+---+
				| 4 |   |  | 4 | 8 |  | 4 | 8 |
				+---+---+  +---+---+  +---+---+
				*/
				stepx = -1;
				stepy = 0;
				break;

			case 2:
			case 3:
			case 7:
				/* going RIGHT with these cases:
				2          3          7
				+---+---+  +---+---+  +---+---+
				|   | 2 |  | 1 | 2 |  | 1 | 2 |
				+---+---+  +---+---+  +---+---+
				|   |   |  |   |   |  | 4 |   |
				+---+---+  +---+---+  +---+---+
				*/
				stepx = 1;
				stepy = 0;
				break;
			case 9:
				/* Going DOWN if coming from the LEFT, otherwise go UP.
				9
				+---+---+
				| 1 |   |
				+---+---+
				|   | 8 |
				+---+---+
				*/

				if (prevx == 1) {
					stepx = 0;
					stepy = 1;
				} else {
					stepx = 0;
					stepy = -1;
				}
				break;
			case 6:
				/* Going RIGHT if coming from BELOW, otherwise go LEFT.
				6
				+---+---+
				|   | 2 |
				+---+---+
				| 4 |   |
				+---+---+
				*/

				if (prevy == -1) {
					stepx = 1;
					stepy = 0;
				} else {
					stepx = -1;
					stepy = 0;
				}
				break;
			default:
				ERR_PRINT("this shouldn't happen.");
		}

		// Handle crossing points.
		if (sv == 6 || sv == 9) {
			const Point2i cur_pos(curx, cury);

			// Find if this point has occurred before.
			if (HashMap<Point2i, int>::Iterator found = cross_map.find(cur_pos)) {
				// Add points after the previous crossing to the result.
				ret.push_back(_points.slice(found->value + 1, points_size));

				// Remove points after crossing point.
				points_size = found->value + 1;

				// Erase trailing map elements.
				while (cross_map.last() != found) {
					cross_map.remove(cross_map.last());
				}

				cross_map.erase(cur_pos);
			} else {
				// Add crossing point to map.
				cross_map.insert(cur_pos, points_size - 1);
			}
		}

		// Small optimization:
		// If the previous direction is same as the current direction,
		// then we should modify the last vector to current.
		curx += stepx;
		cury += stepy;
		if (stepx == prevx && stepy == prevy) {
			_points.set(points_size - 1, Vector2(curx, cury) - p_rect.position);
		} else {
			_points.resize(MAX(points_size + 1, _points.size()));
			_points.set(points_size, Vector2(curx, cury) - p_rect.position);
			points_size++;
		}

		count++;
		prevx = stepx;
		prevy = stepy;

		ERR_FAIL_COND_V((int)count > 2 * (width * height + 1), Vector<Vector<Vector2>>());
	} while (curx != startx || cury != starty);

	// Add remaining points to result.
	_points.resize(points_size);

	ret.set(0, _points);

	return ret;
}

static float perpendicular_distance(const Vector2 &i, const Vector2 &start, const Vector2 &end) {
	float res;
	float slope;
	float intercept;

	if (start.x == end.x) {
		res = Math::abs(i.x - end.x);
	} else if (start.y == end.y) {
		res = Math::abs(i.y - end.y);
	} else {
		slope = (end.y - start.y) / (end.x - start.x);
		intercept = start.y - (slope * start.x);
		res = Math::abs(slope * i.x - i.y + intercept) / Math::sqrt(Math::pow(slope, 2.0f) + 1.0);
	}
	return res;
}

static Vector<Vector2> rdp(const Vector<Vector2> &v, float optimization) {
	if (v.size() < 3) {
		return v;
	}

	int index = -1;
	float dist = 0.0;
	// Not looping first and last point.
	for (size_t i = 1, size = v.size(); i < size - 1; ++i) {
		float cdist = perpendicular_distance(v[i], v[0], v[v.size() - 1]);
		if (cdist > dist) {
			dist = cdist;
			index = static_cast<int>(i);
		}
	}
	if (dist > optimization) {
		Vector<Vector2> left, right;
		left.resize(index);
		for (int i = 0; i < index; i++) {
			left.write[i] = v[i];
		}
		right.resize(v.size() - index);
		for (int i = 0; i < right.size(); i++) {
			right.write[i] = v[index + i];
		}
		Vector<Vector2> r1 = rdp(left, optimization);
		Vector<Vector2> r2 = rdp(right, optimization);

		int middle = r1.size();
		r1.resize(r1.size() + r2.size());
		for (int i = 0; i < r2.size(); i++) {
			r1.write[middle + i] = r2[i];
		}
		return r1;
	} else {
		Vector<Vector2> ret;
		ret.push_back(v[0]);
		ret.push_back(v[v.size() - 1]);
		return ret;
	}
}

static Vector<Vector2> reduce(const Vector<Vector2> &points, const Rect2i &rect, float epsilon) {
	int size = points.size();
	// If there are less than 3 points, then we have nothing.
	ERR_FAIL_COND_V(size < 3, Vector<Vector2>());
	// If there are less than 9 points (but more than 3), then we don't need to reduce it.
	if (size < 9) {
		return points;
	}

	float maxEp = MIN(rect.size.width, rect.size.height);
	float ep = CLAMP(epsilon, 0.0, maxEp / 2);
	Vector<Vector2> result = rdp(points, ep);

	Vector2 last = result[result.size() - 1];

	if (last.y > result[0].y && last.distance_to(result[0]) < ep * 0.5f) {
		result.write[0].y = last.y;
		result.resize(result.size() - 1);
	}
	return result;
}

struct FillBitsStackEntry {
	Point2i pos;
	int i = 0;
	int j = 0;
};

static void fill_bits(const BitMap *p_src, Ref<BitMap> &p_map, const Point2i &p_pos, const Rect2i &rect) {
	// Using a custom stack to work iteratively to avoid stack overflow on big bitmaps.
	Vector<FillBitsStackEntry> stack;
	// Tracking size since we won't be shrinking the stack vector.
	int stack_size = 0;

	Point2i pos = p_pos;
	int next_i = 0;
	int next_j = 0;

	bool reenter = true;
	bool popped = false;
	do {
		if (reenter) {
			next_i = pos.x - 1;
			next_j = pos.y - 1;
			reenter = false;
		}

		for (int i = next_i; i <= pos.x + 1; i++) {
			for (int j = next_j; j <= pos.y + 1; j++) {
				if (popped) {
					// The next loop over j must start normally.
					next_j = pos.y - 1;
					popped = false;
					// Skip because an iteration was already executed with current counter values.
					continue;
				}

				if (i < rect.position.x || i >= rect.position.x + rect.size.x) {
					continue;
				}
				if (j < rect.position.y || j >= rect.position.y + rect.size.y) {
					continue;
				}

				if (p_map->get_bit(i, j)) {
					continue;

				} else if (p_src->get_bit(i, j)) {
					p_map->set_bit(i, j, true);

					FillBitsStackEntry se = { pos, i, j };
					stack.resize(MAX(stack_size + 1, stack.size()));
					stack.set(stack_size, se);
					stack_size++;

					pos = Point2i(i, j);
					reenter = true;
					break;
				}
			}
			if (reenter) {
				break;
			}
		}
		if (!reenter) {
			if (stack_size) {
				FillBitsStackEntry se = stack.get(stack_size - 1);
				stack_size--;
				pos = se.pos;
				next_i = se.i;
				next_j = se.j;
				popped = true;
			}
		}
	} while (reenter || popped);
}

Vector<Vector<Vector2>> BitMap::clip_opaque_to_polygons(const Rect2i &p_rect, float p_epsilon) const {
	Rect2i r = Rect2i(0, 0, width, height).intersection(p_rect);

	Ref<BitMap> fill;
	fill.instantiate();
	fill->create(get_size());

	Vector<Vector<Vector2>> polygons;
	for (int i = r.position.y; i < r.position.y + r.size.height; i++) {
		for (int j = r.position.x; j < r.position.x + r.size.width; j++) {
			if (!fill->get_bit(j, i) && get_bit(j, i)) {
				fill_bits(this, fill, Point2i(j, i), r);

				for (Vector<Vector2> polygon : _march_square(r, Point2i(j, i))) {
					polygon = reduce(polygon, r, p_epsilon);

					if (polygon.size() < 3) {
						print_verbose("Invalid polygon, skipped");
						continue;
					}

					polygons.push_back(polygon);
				}
			}
		}
	}

	return polygons;
}

void BitMap::grow_mask(int p_pixels, const Rect2i &p_rect) {
	if (p_pixels == 0) {
		return;
	}

	// A radius of one can only reach the four cardinal neighbors.
	// Avoid creating a temporary BitMap, the quadratic neighborhood loop,
	// repeated bounds checks and floating-point distance calculations.
	if (p_pixels == 1 || p_pixels == -1) {
		const Rect2i current = Rect2i(0, 0, width, height).intersection(p_rect);
		if (current.size.x <= 0 || current.size.y <= 0) {
			return;
		}
		const bool bit_value = p_pixels > 0;
		const int64_t left = p_rect.position.x;
		const int64_t top = p_rect.position.y;
		const int64_t right = left + p_rect.size.x;
		const int64_t bottom = top + p_rect.size.y;
		// A shared immutable view retains the pre-operation mask; ptrw()
		// detaches it once for the updates instead of building a BitMap.
		const Vector<uint8_t> original = bitmask;
		uint8_t *destination = bitmask.ptrw();
		const uint8_t *source = original.ptr();

		auto matches = [&](int64_t x, int64_t y) -> bool {
			// Grow ignores outside-rectangle pixels. Shrink treats them as
			// unset, exactly as the generic neighborhood implementation.
			if (x < left || x >= right || y < top || y >= bottom) {
				return !bit_value;
			}
			if (x < 0 || x >= width || y < 0 || y >= height) {
				return !bit_value;
			}
			const int bit = int(y) * width + int(x);
			const bool set = (source[bit >> 3] & (1u << (bit & 7))) != 0;
			return set == bit_value;
		};

		for (int y = current.position.y; y < current.position.y + current.size.y; y++) {
			for (int x = current.position.x; x < current.position.x + current.size.x; x++) {
				const int bit = y * width + x;
				const uint8_t mask = uint8_t(1u << (bit & 7));
				const bool original_bit = (source[bit >> 3] & mask) != 0;
				if (original_bit == bit_value) {
					continue;
				}
				if (matches(int64_t(x) - 1, y) || matches(int64_t(x) + 1, y) ||
						matches(x, int64_t(y) - 1) || matches(x, int64_t(y) + 1)) {
					if (bit_value) {
						destination[bit >> 3] |= mask;
					} else {
						destination[bit >> 3] &= uint8_t(~mask);
					}
				}
			}
		}
		return;
	}

	const bool bit_value = p_pixels > 0;
	const int radius = Math::abs(p_pixels);
	const int64_t radius_squared = int64_t(radius) * radius;
	const Rect2i current = Rect2i(0, 0, width, height).intersection(p_rect);
	if (current.size.x <= 0 || current.size.y <= 0) {
		return;
	}

	// Keep the pre-operation bits in a COW snapshot. No temporary Resource,
	// second zero-initialized buffer, or get_bit/set_bit calls are needed.
	const Vector<uint8_t> original = bitmask;
	uint8_t *destination = bitmask.ptrw();
	const uint8_t *source = original.ptr();
	// Only source pixels inside the intersection of image and p_rect can
	// contribute to growth. For shrinking, stepping outside that region is
	// already a transparent neighbor, so an entire border band is known.
	const int64_t left = current.position.x;
	const int64_t top = current.position.y;
	const int64_t right = left + current.size.x;
	const int64_t bottom = top + current.size.y;

	// Cache each disk scanline's half-width once instead of testing every
	// candidate in the surrounding square against the radius.
	const int max_delta_y = MIN(radius, current.size.y - 1);
	LocalVector<int> horizontal_extents;
	horizontal_extents.resize_uninitialized(max_delta_y + 1);
	for (int dy = 0; dy <= max_delta_y; dy++) {
		const int64_t dy_squared = int64_t(dy) * dy;
		int64_t extent = int64_t(std::sqrt(double(radius_squared - dy_squared)));
		// Correct possible floating-point rounding at the exact boundary.
		while (extent * extent + dy_squared > radius_squared) {
			extent--;
		}
		while ((extent + 1) * (extent + 1) + dy_squared <= radius_squared) {
			extent++;
		}
		horizontal_extents[dy] = int(extent);
	}

	for (int y = current.position.y; y < current.position.y + current.size.y; y++) {
		for (int x = current.position.x; x < current.position.x + current.size.x; x++) {
			const int bit = y * width + x;
			const uint8_t mask = uint8_t(1u << (bit & 7));
			if (((source[bit >> 3] & mask) != 0) == bit_value) {
				continue;
			}

			// A radius reaching past the image/p_rect intersection always
			// encounters an unset pixel, so erosion can clear it immediately.
			if (!bit_value && (int64_t(x) - left < radius || right - x <= radius ||
					int64_t(y) - top < radius || bottom - y <= radius)) {
				destination[bit >> 3] &= uint8_t(~mask);
				continue;
			}

			bool found = false;
			const int64_t first_y = MAX(top, int64_t(y) - radius);
			const int64_t last_y = MIN(bottom - 1, int64_t(y) + radius);
			for (int64_t candidate_y = first_y; candidate_y <= last_y && !found; candidate_y++) {
				const int dy = ABS(int(candidate_y - y));
				const int half_width = horizontal_extents[dy];
				const int64_t first_x = MAX(left, int64_t(x) - half_width);
				const int64_t last_x = MIN(right - 1, int64_t(x) + half_width);
				const int source_row = int(candidate_y) * width;
				for (int64_t candidate_x = first_x; candidate_x <= last_x; candidate_x++) {
					const int neighbor_bit = source_row + int(candidate_x);
					const bool neighbor = (source[neighbor_bit >> 3] & (1u << (neighbor_bit & 7))) != 0;
					if (neighbor == bit_value) {
						found = true;
						break;
					}
				}
			}
			if (found) {
				if (bit_value) {
					destination[bit >> 3] |= mask;
				} else {
					destination[bit >> 3] &= uint8_t(~mask);
				}
			}
		}
	}
}

void BitMap::shrink_mask(int p_pixels, const Rect2i &p_rect) {
	grow_mask(-p_pixels, p_rect);
}

TypedArray<PackedVector2Array> BitMap::_opaque_to_polygons_bind(const Rect2i &p_rect, float p_epsilon) const {
	Vector<Vector<Vector2>> result = clip_opaque_to_polygons(p_rect, p_epsilon);

	// Convert result to bindable types.

	TypedArray<PackedVector2Array> result_array;
	result_array.resize(result.size());
	for (int i = 0; i < result.size(); i++) {
		const Vector<Vector2> &polygon = result[i];

		PackedVector2Array polygon_array;
		polygon_array.resize(polygon.size());

		{
			Vector2 *w = polygon_array.ptrw();
			for (int j = 0; j < polygon.size(); j++) {
				w[j] = polygon[j];
			}
		}

		result_array[i] = polygon_array;
	}

	return result_array;
}

void BitMap::resize(const Size2i &p_new_size) {
	ERR_FAIL_COND(p_new_size.width < 0 || p_new_size.height < 0);
	if (p_new_size == get_size()) {
		return;
	}

	Ref<BitMap> new_bitmap;
	new_bitmap.instantiate();
	new_bitmap->create(p_new_size);
	if (new_bitmap->get_size() == p_new_size && p_new_size.width > 0 && p_new_size.height > 0 && width > 0 && height > 0) {
		// Match the original nearest-neighbor sampling and float precision,
		// but traverse destination rows in order. The destination is zeroed
		// by create(), so only the set source bits need to be written.
		const float scale_x = float(width) / p_new_size.width;
		const float scale_y = float(height) / p_new_size.height;
		const uint8_t *source = bitmask.ptr();
		uint8_t *destination = new_bitmap->bitmask.ptrw();
		for (int y = 0; y < p_new_size.height; y++) {
			const int source_y = int(y * scale_y);
			if (source_y < 0 || source_y >= height) {
				continue;
			}
			const int source_row = source_y * width;
			const int dest_row = y * p_new_size.width;
			for (int x = 0; x < p_new_size.width; x++) {
				const int source_x = int(x * scale_x);
				if (source_x < 0 || source_x >= width) {
					continue;
				}
				const int source_bit = source_row + source_x;
				if (source[source_bit >> 3] & (1u << (source_bit & 7))) {
					const int dest_bit = dest_row + x;
					destination[dest_bit >> 3] |= uint8_t(1u << (dest_bit & 7));
				}
			}
		}
	}
	width = new_bitmap->width;
	height = new_bitmap->height;
	bitmask = new_bitmap->bitmask;
}

Ref<Image> BitMap::convert_to_image() const {
	if (width == 0 || height == 0) {
		return Image::create_empty(width, height, false, Image::FORMAT_L8);
	}

	// FORMAT_L8 is one byte per pixel. Avoid per-pixel Color conversion,
	// bounds checks and image updates; the packed mask is already row-major.
	Vector<uint8_t> image_data;
	image_data.resize(width * height);
	uint8_t *dst = image_data.ptrw();
	const uint8_t *src = bitmask.ptr();
	const int pixels = width * height;
	for (int i = 0; i < pixels; i++) {
		dst[i] = (src[i >> 3] & (1u << (i & 7))) ? 0xff : 0;
	}
	return Image::create_from_data(width, height, false, Image::FORMAT_L8, image_data);
}

void BitMap::blit(const Vector2i &p_pos, const Ref<BitMap> &p_bitmap) {
	ERR_FAIL_COND_MSG(p_bitmap.is_null(), "It's not a reference to a valid BitMap object.");

	const int source_width = p_bitmap->width;
	const int source_height = p_bitmap->height;

	if (p_bitmap.ptr() == this) {
		// Preserve the existing column-major behavior for overlapping
		// self-blits, where writes can affect subsequent source reads.
		for (int x = 0; x < source_width; x++) {
			for (int y = 0; y < source_height; y++) {
				const int px = p_pos.x + x;
				const int py = p_pos.y + y;
				if (px >= 0 && px < width && py >= 0 && py < height && get_bit(x, y)) {
					set_bit(px, py, true);
				}
			}
		}
		return;
	}

	// Clip before copying. Using 64-bit coordinates prevents addition
	// overflow if the caller passes a position near the integer limits.
	const int64_t x_begin = MAX(int64_t(0), int64_t(p_pos.x));
	const int64_t y_begin = MAX(int64_t(0), int64_t(p_pos.y));
	const int64_t x_end = MIN(int64_t(width), int64_t(p_pos.x) + source_width);
	const int64_t y_end = MIN(int64_t(height), int64_t(p_pos.y) + source_height);
	if (x_begin >= x_end || y_begin >= y_end) {
		return;
	}

	// OR full destination bytes instead of testing each source pixel.
	// The source and destination bit rows can be unaligned (including when
	// their widths are not multiples of eight), so combine adjacent source
	// bytes to form each aligned destination byte.
	uint8_t *destination = bitmask.ptrw();
	const uint8_t *source = p_bitmap->bitmask.ptr();
	const int bits_per_row = int(x_end - x_begin);
	for (int64_t y = y_begin; y < y_end; y++) {
		int source_bit = int(y - p_pos.y) * source_width + int(x_begin - p_pos.x);
		int dest_bit = int(y) * width + int(x_begin);
		int remaining_bits = bits_per_row;

		// Preserve the bits preceding the covered region in the first byte.
		while (remaining_bits > 0 && (dest_bit & 7)) {
			destination[dest_bit >> 3] |= uint8_t(((source[source_bit >> 3] >> (source_bit & 7)) & 1u) << (dest_bit & 7));
			source_bit++;
			dest_bit++;
			remaining_bits--;
		}

		// The common case is a long run of complete destination bytes.
		const int whole_bytes = remaining_bits >> 3;
		const int source_shift = source_bit & 7;
		const uint8_t *src = source + (source_bit >> 3);
		uint8_t *dst = destination + (dest_bit >> 3);
		if (source_shift == 0) {
			for (int byte = 0; byte < whole_bytes; byte++) {
				dst[byte] |= src[byte];
			}
		} else {
			for (int byte = 0; byte < whole_bytes; byte++) {
				dst[byte] |= uint8_t((src[byte] >> source_shift) | (src[byte + 1] << (8 - source_shift)));
			}
		}
		const int bulk_bits = whole_bytes << 3;
		source_bit += bulk_bits;
		dest_bit += bulk_bits;
		remaining_bits -= bulk_bits;

		// Preserve the bits following the covered region in the final byte.
		while (remaining_bits > 0) {
			destination[dest_bit >> 3] |= uint8_t(((source[source_bit >> 3] >> (source_bit & 7)) & 1u) << (dest_bit & 7));
			source_bit++;
			dest_bit++;
			remaining_bits--;
		}
	}
}

void BitMap::_bind_methods() {
	ClassDB::bind_method(D_METHOD("create", "size"), &BitMap::create);
	ClassDB::bind_method(D_METHOD("create_from_image_alpha", "image", "threshold"), &BitMap::create_from_image_alpha, DEFVAL(0.1));

	ClassDB::bind_method(D_METHOD("set_bitv", "position", "bit"), &BitMap::set_bitv);
	ClassDB::bind_method(D_METHOD("set_bit", "x", "y", "bit"), &BitMap::set_bit);
	ClassDB::bind_method(D_METHOD("get_bitv", "position"), &BitMap::get_bitv);
	ClassDB::bind_method(D_METHOD("get_bit", "x", "y"), &BitMap::get_bit);

	ClassDB::bind_method(D_METHOD("set_bit_rect", "rect", "bit"), &BitMap::set_bit_rect);
	ClassDB::bind_method(D_METHOD("get_true_bit_count"), &BitMap::get_true_bit_count);

	ClassDB::bind_method(D_METHOD("get_size"), &BitMap::get_size);
	ClassDB::bind_method(D_METHOD("resize", "new_size"), &BitMap::resize);

	ClassDB::bind_method(D_METHOD("_set_data", "data"), &BitMap::_set_data);
	ClassDB::bind_method(D_METHOD("_get_data"), &BitMap::_get_data);

	ClassDB::bind_method(D_METHOD("grow_mask", "pixels", "rect"), &BitMap::grow_mask);
	ClassDB::bind_method(D_METHOD("convert_to_image"), &BitMap::convert_to_image);
	ClassDB::bind_method(D_METHOD("opaque_to_polygons", "rect", "epsilon"), &BitMap::_opaque_to_polygons_bind, DEFVAL(2.0));

	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "data", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_INTERNAL), "_set_data", "_get_data");
}
