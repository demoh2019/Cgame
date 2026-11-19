#!/usr/bin/env python3
"""Synthetic correctness/work comparison for offscreen TileMap warnings.

Models the work counts in upstream Godot #124288 and the Cgame direct-map
variant. This is NOT a benchmark of the C++ engine or actual editor FPS.
"""
from __future__ import annotations

from collections import namedtuple
from time import perf_counter

Cell = namedtuple("Cell", "x y invalid")


def synthetic_grid(width: int = 150, height: int = 100) -> list[Cell]:
    return [Cell(x, y, (x * 97 + y * 41) % 61 == 0)
            for y in range(height) for x in range(width)]


def is_visible(cell: Cell, rect: tuple[int, int, int, int]) -> bool:
    left, top, right, bottom = rect
    return left <= cell.x <= right and top <= cell.y <= bottom


def legacy_visible_draw(cells: list[Cell], rect: tuple[int, int, int, int]) -> tuple[tuple[int, int], ...]:
    # Old editor enumerates EVERY cell and generates warnings for all invalid
    # cells, including those outside the viewport. Rendering eventually clips.
    return tuple((c.x, c.y) for c in cells if c.invalid and is_visible(c, rect))


def cached_visible_draw(invalid_cells: list[Cell], rect: tuple[int, int, int, int]) -> tuple[tuple[int, int], ...]:
    return tuple((c.x, c.y) for c in invalid_cells if is_visible(c, rect))


def main() -> None:
    cells = synthetic_grid()
    rects = [(x, y, x + 12, y + 9)
             for y in (0, 18, 39, 67, 88) for x in (0, 40, 81, 122)]
    invalid_cells = [c for c in cells if c.invalid]  # Once per mutation.
    start = perf_counter()
    old = [legacy_visible_draw(cells, rect) for rect in rects]
    legacy_ms = (perf_counter() - start) * 1000
    start = perf_counter()
    new = [cached_visible_draw(invalid_cells, rect) for rect in rects]
    cache_ms = (perf_counter() - start) * 1000
    assert old == new, "Visible missing-tile warnings changed"

    # A change to the edited tile layer invalidates and rebuilds the cache.
    modified = cells.copy()
    target = next(i for i, cell in enumerate(modified) if not cell.invalid)
    cell = modified[target]
    modified[target] = Cell(cell.x, cell.y, True)
    changed_cache = [c for c in modified if c.invalid]
    for rect in rects:
        assert legacy_visible_draw(modified, rect) == cached_visible_draw(changed_cache, rect)
    assert any((cell.x, cell.y) in cached_visible_draw(changed_cache, rect)
               for rect in rects if is_visible(cell, rect))

    print(f"PASS: {len(cells):,} cells, {len(invalid_cells):,} invalid, "
          f"{len(rects)} frames; visible result identical before/after edits")
    print(f"Synthetic Python legacy: {legacy_ms:.3f} ms; cached: {cache_ms:.3f} ms")
    print(f"Approximate cell checks: legacy {len(cells)*len(rects):,}; "
          f"cached {len(cells)+len(invalid_cells)*len(rects):,} "
          "(includes one cache rebuild)")


if __name__ == "__main__":
    main()
