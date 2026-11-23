/**************************************************************************/
/*  cgame_meshlet_pages.h                                                 */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Offline/loading-stage cluster page format for future GPU-resident
// virtualized geometry. Pages store meshlet descriptors, global original
// vertex references, and local u8 triangle indices. They do NOT copy,
// simplify or discard the source mesh's normals, tangents, UVs or materials.
// These buffers are not submitted to a GPU or used for drawing yet.
class CgameMeshletPages : public RefCounted {
	GDCLASS(CgameMeshletPages, RefCounted);

protected:
	static void _bind_methods();

public:
	// Binary v1, explicitly little-endian:
	// 32-byte header, 48-byte fixed descriptor per meshlet, tightly packed
	// global u32 vertex IDs and tightly packed local u8 triangle indices.
	static constexpr int HEADER_BYTES = 32;
	static constexpr int DESCRIPTOR_BYTES = 48;
	static constexpr int DEFAULT_PAGE_BYTES = 16384;
	static constexpr int MAX_PAGE_BYTES = 65536;

	static Array build_pages(const PackedVector3Array &p_vertices, const PackedInt32Array &p_indices,
			int p_page_bytes = DEFAULT_PAGE_BYTES);
	// Strict parser useful for asset build validation and CPU fallback
	// inspection. Rejects corrupt offsets and invalid triangle references.
	static Dictionary inspect_page(const PackedByteArray &p_page);
};
