/**************************************************************************/
/*  test_tilemap_layer_cell_revision.cpp                                  */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                          */
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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF   */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_tilemap_layer_cell_revision)

#ifdef TOOLS_ENABLED
#include "modules/modules_enabled.gen.h"
#ifdef MODULE_TILEMAP_ENABLED
#include "modules/tilemap/tile_map_layer.h"

namespace TestTileMapLayerCellRevision {

TEST_CASE("[TileMapLayer][Editor] Cell revision tracks meaningful cell edits") {
    TileMapLayer *layer = memnew(TileMapLayer);
    const uint64_t first_revision = layer->get_cell_data_revision();
    const Vector2i first_coord(4, 7);
    const Vector2i atlas_coord(0, 0);

    layer->set_cell(first_coord, 7, atlas_coord, 0);
    CHECK(layer->get_cell_data_revision() == first_revision + 1);

    // Idempotent changes must not invalidate the expensive overlay cache.
    layer->set_cell(first_coord, 7, atlas_coord, 0);
    CHECK(layer->get_cell_data_revision() == first_revision + 1);

    layer->set_cell(first_coord, 8, atlas_coord, 0);
    CHECK(layer->get_cell_data_revision() == first_revision + 2);

    layer->erase_cell(first_coord);
    CHECK(layer->get_cell_data_revision() == first_revision + 3);
    layer->erase_cell(first_coord);
    CHECK(layer->get_cell_data_revision() == first_revision + 3);

    // Removing a nonexistent cell must also avoid needless invalidation.
    layer->erase_cell(Vector2i(99, 99));
    CHECK(layer->get_cell_data_revision() == first_revision + 3);
    memdelete(layer);
}

TEST_CASE("[TileMapLayer][Editor] Cell cache sees the same data as the public accessors") {
    TileMapLayer *layer = memnew(TileMapLayer);
    const Vector2i coord(-3, 5);
    const Vector2i atlas(2, 4);
    layer->set_cell(coord, 17, atlas, 2);
    const HashMap<Vector2i, CellData> &cells = layer->get_tile_map_layer_data();

    CHECK(cells.has(coord));
    if (cells.has(coord)) {
        const TileMapCell &cell = cells[coord].cell;
        CHECK(cell.source_id == layer->get_cell_source_id(coord));
        CHECK(cell.get_atlas_coords() == layer->get_cell_atlas_coords(coord));
        CHECK(cell.alternative_tile == layer->get_cell_alternative_tile(coord));
    }

    layer->erase_cell(coord);
    // Deletions can remain in the map until the deferred update; the scanner
    // must always skip invalid (negative) source IDs.
    CHECK(layer->get_cell_source_id(coord) < 0);
    memdelete(layer);
}

} // namespace TestTileMapLayerCellRevision
#endif // MODULE_TILEMAP_ENABLED
#endif // TOOLS_ENABLED
