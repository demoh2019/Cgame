"""Offline mathematical contracts for procedural streamed terrain.

Run with: python3 -m unittest discover -s tests -p 'test_terrain_*.py' -v

This test checks height/normal continuity and independently models the
fan-triangulated LOD boundary stitching. It cannot replace the GDScript smoke
tests, a Godot import/compile, or actual renderer/physics verification.
"""

from __future__ import annotations

from collections import Counter
from math import cos, sin, sqrt
from pathlib import Path
from unittest import TestCase

SAMPLES = 33
CELLS = 32
ROOT = Path(__file__).resolve().parents[1]


def height(x: float, z: float) -> float:
    return (
        1.7 * sin(x * 0.058) * cos(z * 0.063)
        + 0.85 * sin((x + z) * 0.135)
        + 0.25 * sin(x * 0.47) * cos(z * 0.39)
    )


def normal(x: float, z: float) -> tuple[float, float, float]:
    e = 0.3
    dx = (height(x + e, z) - height(x - e, z)) / (2.0 * e)
    dz = (height(x, z + e) - height(x, z - e)) / (2.0 * e)
    length = sqrt(dx * dx + 1.0 + dz * dz)
    return (-dx / length, 1.0 / length, -dz / length)


def tile_sample(tile_x: int, tile_z: int, x: int, z: int) -> tuple[float, tuple[float, float, float]]:
    world_x = float(tile_x * CELLS + x)
    world_z = float(tile_z * CELLS + z)
    return height(world_x, world_z), normal(world_x, world_z)


def _index(x: int, z: int) -> int:
    return z * SAMPLES + x


def lod_indices(step: int) -> list[int]:
    """Independent mathematical model of the GDScript outer-edge fan LOD."""
    result: list[int] = []
    assert step in (2, 4, 8)
    for z in range(0, CELLS, step):
        for x in range(0, CELLS, step):
            perimeter: list[int] = []
            perimeter += [_index(x + i, z) for i in range(step if z == 0 else 1)]
            perimeter += [
                _index(x + step, z + i)
                for i in range(step if x + step == CELLS else 1)
            ]
            perimeter += [
                _index(x + step - i, z + step)
                for i in range(step if z + step == CELLS else 1)
            ]
            perimeter += [
                _index(x, z + step - i)
                for i in range(step if x == 0 else 1)
            ]
            center = _index(x + step // 2, z + step // 2)
            for i in range(len(perimeter)):
                result.extend((center, perimeter[(i + 1) % len(perimeter)], perimeter[i]))
    return result


class StreamedTerrainContracts(TestCase):
    def test_adjacent_tile_seam_heights_and_normals(self) -> None:
        # Left and right sides of adjacent tiles refer to identical global
        # coordinates. This covers negative origins and every shared vertex.
        for cell_x in (-2, -1, 0, 1):
            for cell_z in (-1, 0, 1):
                for offset in range(SAMPLES):
                    east_edge = tile_sample(cell_x, cell_z, CELLS, offset)
                    west_edge = tile_sample(cell_x + 1, cell_z, 0, offset)
                    self.assertEqual(east_edge, west_edge)
                    south_edge = tile_sample(cell_x, cell_z, offset, CELLS)
                    north_edge = tile_sample(cell_x, cell_z + 1, offset, 0)
                    self.assertEqual(south_edge, north_edge)

    def test_lods_have_same_complete_outer_border(self) -> None:
        border = {
            _index(x, 0) for x in range(SAMPLES)
        } | {
            _index(x, CELLS) for x in range(SAMPLES)
        } | {
            _index(0, z) for z in range(SAMPLES)
        } | {
            _index(CELLS, z) for z in range(SAMPLES)
        }
        previous_triangles = CELLS * CELLS * 2
        for step in (2, 4, 8):
            indices = lod_indices(step)
            self.assertEqual(len(indices) % 3, 0)
            self.assertLess(len(indices) // 3, previous_triangles)
            previous_triangles = len(indices) // 3
            self.assertTrue(set(indices).issubset(set(range(SAMPLES * SAMPLES))))
            edge_use: Counter[tuple[int, int]] = Counter()
            for a, b, c in zip(indices[::3], indices[1::3], indices[2::3]):
                ax, az = a % SAMPLES, a // SAMPLES
                bx, bz = b % SAMPLES, b // SAMPLES
                cx, cz = c % SAMPLES, c // SAMPLES
                self.assertGreater((bz - az) * (cx - ax) - (bx - ax) * (cz - az), 0)
                for u, v in ((a, b), (b, c), (c, a)):
                    edge_use[tuple(sorted((u, v)))] += 1
            self.assertTrue(all(count in (1, 2) for count in edge_use.values()))
            boundary = {v for edge, count in edge_use.items() if count == 1 for v in edge}
            self.assertEqual(boundary, border)
            self.assertEqual(sum(count == 1 for count in edge_use.values()), CELLS * 4)

    def test_source_contracts_are_still_wired(self) -> None:
        patch = (ROOT / "scripts/streamed_terrain_patch.gd").read_text(encoding="utf-8")
        forest = (ROOT / "scripts/streamed_forest_cell.gd").read_text(encoding="utf-8")
        world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
        player = (ROOT / "scripts/explorer_character.gd").read_text(encoding="utf-8")
        assert "HeightMapShape3D.new()" in patch
        assert "TerrainHeight.height_at(wx, wz)" in patch
        assert "_build_lod_indices(8)" in patch
        assert "terrain_collision.position = Vector3(CELL_SIZE * 0.5" in patch
        assert "TerrainPatch.new()" in forest
        assert "_create_terrain()" not in world
        assert "world_partition.is_cell_loaded(cell)" in world
        assert "_position_has_terrain" in player
