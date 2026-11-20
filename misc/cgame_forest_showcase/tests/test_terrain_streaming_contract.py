"""Offline mathematical contracts for procedural streamed terrain.

Run with: python3 -m unittest discover -s tests -p 'test_terrain_*.py' -v

This test checks height/normal continuity and independently models the
fan-triangulated LOD boundary stitching. It cannot replace the GDScript smoke
tests, a Godot import/compile, or actual renderer/physics verification.
"""

from __future__ import annotations

from collections import Counter
from math import cos, sin, sqrt, floor, isclose
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


def route_supercover(ax: float, az: float, bx: float, bz: float,
                     max_cells: int = 64, size: int = 32) -> list[tuple[int, int]]:
    """Independent 2D supercover model with a hard nontruncating cell cap."""
    x, z = floor(ax / size), floor(az / size)
    last_x, last_z = floor(bx / size), floor(bz / size)
    if max_cells < 1:
        return []
    result: list[tuple[int, int]] = []
    dx, dz = (bx - ax) / size, (bz - az) / size
    sx, sz = (1 if dx > 0 else -1 if dx < 0 else 0,
              1 if dz > 0 else -1 if dz < 0 else 0)
    abs_dx, abs_dz = abs(dx), abs(dz)
    tx = float("inf") if sx == 0 else (
        (floor(ax / size) + 1 - ax / size) if sx > 0
        else (ax / size - floor(ax / size))) / abs_dx
    tz = float("inf") if sz == 0 else (
        (floor(az / size) + 1 - az / size) if sz > 0
        else (az / size - floor(az / size))) / abs_dz
    dtx = float("inf") if sx == 0 else 1 / abs_dx
    dtz = float("inf") if sz == 0 else 1 / abs_dz
    boundary_x = sx == 0 and ax / size == floor(ax / size)
    boundary_z = sz == 0 and az / size == floor(az / size)

    def append_cell(cx: int, cz: int) -> bool:
        touched = [(cx, cz)]
        if boundary_x:
            touched.append((cx - 1, cz))
        if boundary_z:
            touched.append((cx, cz - 1))
        if boundary_x and boundary_z:
            touched.append((cx - 1, cz - 1))
        if len(result) + len(touched) > max_cells:
            return False
        result.extend(touched)
        return True

    if not append_cell(x, z):
        return []
    if (x, z) == (last_x, last_z):
        return result
    while (x, z) != (last_x, last_z):
        if sx and sz and isclose(tx, tz, rel_tol=1e-8, abs_tol=1e-8):
            if not append_cell(x + sx, z) or not append_cell(x, z + sz):
                return []
            x, z = x + sx, z + sz
            tx, tz = tx + dtx, tz + dtz
        elif tx < tz:
            x += sx
            tx += dtx
        else:
            z += sz
            tz += dtz
        if not append_cell(x, z):
            return []
    return result


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

    def test_distant_hlod_sparse_vertex_contract(self) -> None:
        """The simplified mesh keeps 1m borders with 8m interior cells."""
        source = lod_indices(8)
        unique = set(source)
        self.assertEqual(len(source) // 3, 176)
        self.assertEqual(len(unique), 153)
        self.assertLess(len(unique), SAMPLES * SAMPLES)

        border = (
            {_index(x, 0) for x in range(SAMPLES)}
            | {_index(x, CELLS) for x in range(SAMPLES)}
            | {_index(0, z) for z in range(SAMPLES)}
            | {_index(CELLS, z) for z in range(SAMPLES)}
        )
        self.assertEqual(len(border), 128)
        self.assertTrue(border.issubset(unique))

        # This mirrors the runtime's stable source-index -> compact-index map.
        mapping: dict[int, int] = {}
        compact: list[tuple[int, int]] = []
        remapped: list[int] = []
        for old in source:
            if old not in mapping:
                mapping[old] = len(compact)
                compact.append((old % SAMPLES, old // SAMPLES))
            remapped.append(mapping[old])
        self.assertEqual(len(compact), 153)
        self.assertTrue(all(0 <= i < len(compact) for i in remapped))
        for tile_x, tile_z in ((-2, -1), (0, 0), (9, 7)):
            for local_x, local_z in compact:
                if local_x in (0, CELLS) or local_z in (0, CELLS):
                    x = tile_x * CELLS + local_x
                    z = tile_z * CELLS + local_z
                    self.assertEqual(
                        tile_sample(tile_x, tile_z, local_x, local_z),
                        (height(float(x), float(z)), normal(float(x), float(z))),
                    )

    def test_distant_hlod_wiring(self) -> None:
        manager = (ROOT / "scripts/distant_terrain_hlod.gd").read_text(encoding="utf-8")
        world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_distant_hlod.gd").read_text(encoding="utf-8")
        for expected in (
            "TerrainHeight.height_at(wx, wz)",
            "TerrainHeight.normal_at(wx, wz)",
            "SharedAssets.ground_material()",
            "source._build_lod_indices(LOD_STEP)",
            "streaming_world.is_cell_loaded(cell)",
            "get_proxy_for_cell(cell: Vector2i)",
            "MAX_BUILDS_PER_FRAME: int = 2",
            "proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF",
        ):
            self.assertIn(expected, manager)
        self.assertIn("_create_distant_terrain()", world)
        self.assertIn('distant_terrain.call("set_high_quality", high)', world)
        self.assertIn("DistantTerrainHLOD", world)
        self.assertIn("HLODTestManager", smoke)
        self.assertNotIn("StaticBody3D.new()", manager)

    def test_distant_hlod_resource_cache_contract(self) -> None:
        """Resource-only LRU remains bounded and integrates into HLOD rebuild."""
        cache = (ROOT / "scripts/distant_hlod_cache.gd").read_text(encoding="utf-8")
        manager = (ROOT / "scripts/distant_terrain_hlod.gd").read_text(encoding="utf-8")
        canopies = (ROOT / "scripts/distant_forest_canopies.gd").read_text(encoding="utf-8")
        world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_hlod_cache.gd").read_text(encoding="utf-8")
        runtime_smoke = (ROOT / "tests/smoke_distant_hlod.gd").read_text(encoding="utf-8")

        self.assertIn("MAX_CACHED_TILES: int = 96", cache)
        self.assertIn("_order.erase(cell)", cache)
        self.assertIn("_order.push_back(cell)", cache)
        self.assertIn("_tiles.erase(oldest)", cache)
        self.assertIn('"terrain": terrain_mesh', cache)
        self.assertIn('"canopies": canopy_batch', cache)
        self.assertNotIn("Node3D.new()", cache)
        self.assertNotIn("StaticBody3D.new()", cache)
        self.assertIn("HLODCache.lookup(cell)", manager)
        self.assertIn("HLODCache.insert(cell, mesh, canopies.multimesh)", manager)
        self.assertIn('mesh = resources["terrain"]', manager)
        self.assertIn('canopies.configure(cell, resources["canopies"])', manager)
        self.assertIn('"cache": HLODCache.get_stats()', manager)
        self.assertIn("MAX_BUILD_CPU_MS: float = 2.0", manager)
        self.assertIn("built_this_frame == 0", manager)
        self.assertIn('"last_rebuild_cpu_ms": _last_rebuild_cpu_ms', manager)

        self.assertIn("if cached_batch != null:", canopies)
        self.assertIn("multimesh = cached_batch", canopies)
        self.assertIn('far.get("cache",', world)
        self.assertIn('far_cache["hits"]', world)
        self.assertIn("KEY_F3:", world)
        self.assertIn("HLODCache.clear()", world)
        self.assertIn("TileCache.clear()", world)
        self.assertIn("KEY_F4:", world)
        self.assertIn("world_partition.retry_failed_cells()", world)

        self.assertIn("HLODCache.clear()", smoke)
        self.assertIn('int(stats["entries"]) != capacity', smoke)
        self.assertIn('revisited.mesh != old_terrain_mesh', runtime_smoke)
        self.assertIn('new_canopies.multimesh != old_canopy_batch', runtime_smoke)

    def test_distant_canopy_placement_contract(self) -> None:
        """Keep far/near deterministic forest generation locked together."""
        near = (ROOT / "scripts/streamed_forest_cell.gd").read_text(encoding="utf-8")
        far = (ROOT / "scripts/distant_forest_canopies.gd").read_text(encoding="utf-8")
        shared = (ROOT / "scripts/forest_shared_assets.gd").read_text(encoding="utf-8")
        manager = (ROOT / "scripts/distant_terrain_hlod.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_distant_hlod.gd").read_text(encoding="utf-8")

        for literal in (
            "TREE_COUNT: int = 54",
            "rng.randf_range(1.0, CELL_SIZE - 1.0)",
            "Vector2(wx, wz - 9.0).length() < 8.0",
            "Vector2(wx - 208.0, wz - 208.0).length() < 6.0",
            "rng.randf_range(0.70, 1.5)",
            "Basis(Vector3.UP, rng.randf_range(-PI, PI))",
            "scale * 4.15",
            "scale * 2.0, scale * 1.75, scale * 2.0",
        ):
            self.assertIn(literal, near)
            self.assertIn(literal, far)

        self.assertIn("rng.seed = 913481 + cell_x * 73856093 + cell_z * 19349663", near)
        self.assertIn("rng.seed = 913481 + cell.x * 73856093 + cell.y * 19349663", far)
        self.assertIn("Color(rng.randf(), rng.randf(), rng.randf(), 1.0)", near)
        self.assertIn("var r: float = rng.randf()", far)
        self.assertIn("var g: float = rng.randf()", far)
        self.assertIn("var b: float = rng.randf()", far)
        self.assertIn("batch.use_colors = true", far)
        self.assertIn("batch.instance_count = transforms.size()", far)
        self.assertIn("batch.mesh = SharedAssets.distant_tree_canopy()", far)
        self.assertIn("radial_segments = 5", shared)
        self.assertIn("rings = 2", shared)
        self.assertIn("proxy.add_child(canopies)", manager)
        self.assertIn("visible_canopies", manager)
        self.assertIn("low.is_equal_approx(high)", smoke)
        self.assertNotIn("StaticBody3D.new()", far)
        self.assertNotIn("CollisionShape3D.new()", far)

    def test_named_streaming_sources_engine_game_contract(self) -> None:
        """Named runtime sources must stay wired through native API and game."""
        repository = ROOT.parents[1]
        header = (repository / "modules/world_partition/world_partition_3d.h").read_text(encoding="utf-8")
        cpp = (repository / "modules/world_partition/world_partition_3d.cpp").read_text(encoding="utf-8")
        xml = (repository / "modules/world_partition/doc_classes/WorldPartition3D.xml").read_text(encoding="utf-8")
        cpp_tests = (repository / "modules/world_partition/tests/test_world_partition_3d.h").read_text(encoding="utf-8")
        world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_streaming_sources.gd").read_text(encoding="utf-8")
        integrated = (ROOT / "tests/smoke_source_controls.gd").read_text(encoding="utf-8")

        native_methods = (
            "set_streaming_source",
            "set_streaming_source_node",
            "remove_streaming_source",
            "clear_streaming_sources",
            "get_streaming_source",
            "get_streaming_source_names",
            "get_streaming_source_count",
            "is_streaming_source_ready",
            "get_streaming_source_progress",
        )
        for name in native_methods:
            self.assertIn(name + "(", header)
            self.assertIn("WorldPartition3D::" + name + "(", cpp)
            self.assertIn('D_METHOD("' + name + '"', cpp)
            self.assertIn('method name="' + name + '"', xml)

        self.assertIn("MAX_STREAMING_SOURCES = 8;", header)
        self.assertIn("p_unload_radius < p_load_radius", cpp)
        self.assertIn("p_priority < 0 || p_priority > 100", cpp)
        self.assertIn("is_source_cell(E.key, true)", cpp)
        self.assertIn("is_source_cell(E.key, false)", cpp)
        self.assertIn("Vector<StreamingSource> source_snapshot = streaming_sources", cpp)
        self.assertIn("void WorldPartition3D::_update_streaming_source_positions()", cpp)
        self.assertIn("source.node_path = p_node_path", cpp)
        self.assertIn("target->get_global_position()", cpp)
        self.assertIn("to_local(target->get_global_position())", cpp)
        self.assertIn("if (source.active && _within_radius", cpp)
        self.assertIn('result["node_path"] = source.node_path', cpp)
        self.assertIn('result["active"] = source.active', cpp)
        self.assertIn("source.active && are_cells_loaded", cpp)
        self.assertIn("_update_streaming_source_positions();", cpp)
        self.assertIn("get_subname_count() > 0", cpp)
        self.assertIn("node_path;", header)
        self.assertIn("bool active = true;", header)

        self.assertIn("source_snapshot[j - 1].priority < item.priority", cpp)
        self.assertIn("source_snapshot.write[j] = item", cpp)
        self.assertIn("if (still_current)", cpp)
        self.assertIn("void WorldPartition3D::_refresh_source_readiness()", cpp)
        self.assertIn('SNAME("streaming_source_ready")', cpp)
        self.assertIn('SNAME("streaming_source_unready")', cpp)
        self.assertIn('signal name="streaming_source_ready"', xml)
        self.assertIn('signal name="streaming_source_unready"', xml)
        self.assertLess(
            cpp.index("Vector<Vector2i> pinned_snapshot;"),
            cpp.index("Vector<StreamingSource> source_snapshot = streaming_sources"),
        )
        self.assertLess(
            cpp.index("Vector<StreamingSource> source_snapshot = streaming_sources"),
            cpp.index("prefetch_coordinate(step, ahead)"),
        )

        self.assertIn("Named streaming sources validate radii priority", cpp_tests)
        self.assertIn("Named source priority and readiness", cpp_tests)
        self.assertIn("SURVEY_SOURCE: String = \"survey_drone\"", world)
        self.assertIn("WATCHTOWER_SOURCE: String = \"watchtower\"", world)
        self.assertIn("KEY_F8:", world)
        self.assertIn("KEY_F10:", world)
        self.assertIn("KEY_F11:", world)
        self.assertIn("survey_drone_paused", world)
        self.assertIn("survey_drone.position = Vector3(drone_x", world)
        self.assertIn("world_partition.get_path_to(survey_drone)", world)

        self.assertIn("world_partition.set_streaming_source_node(", world)
        self.assertIn("world_partition.set_streaming_source(", world)
        self.assertIn("world_partition.get_streaming_source_progress(SURVEY_SOURCE)", world)
        self.assertIn("world_partition.get_streaming_source_progress(WATCHTOWER_SOURCE)", world)
        self.assertIn("world.get_streaming_source_progress(\"survey\")", smoke)
        self.assertIn("world_partition.remove_streaming_source(name)", world)
        self.assertIn("streaming_source_ready.connect(_on_streaming_source_ready)", world)
        self.assertIn("streaming_source_unready.connect(_on_streaming_source_unready)", world)
        self.assertIn('source_ready_events += 1', world)
        self.assertIn('source_unready_events += 1', world)
        self.assertIn('world.set_streaming_source("survey", SURVEY, 1, 2, 80)', smoke)
        self.assertIn('world.set_streaming_source("watchtower", TOWER, 0, 1, 25)', smoke)
        self.assertIn('world.call("_toggle_streaming_source", SURVEY_NAME)', integrated)
        self.assertIn('world.call("_toggle_streaming_source", TOWER_NAME)', integrated)
        self.assertIn('label.text.contains("Источники: 2/8")', integrated)
        moving = (ROOT / "tests/smoke_moving_sources.gd").read_text(encoding="utf-8")
        self.assertIn('stream.get_streaming_source(NAME).get("center")', moving)
        self.assertIn("world.remove_child(actor)", moving)
        self.assertIn("world.add_child(actor)", moving)
        self.assertIn('missing.get("active", true)', moving)
        self.assertIn('hud.text.contains("Дрон X=0 Z=4")', moving)


    def test_streamed_navigation_corridor_and_avoidance_contract(self) -> None:
        """Native safe-path API is used by real patrols and obstacle sources."""
        repository = ROOT.parents[1]
        header = (repository / "modules/world_partition/world_partition_3d.h").read_text(encoding="utf-8")
        cpp = (repository / "modules/world_partition/world_partition_3d.cpp").read_text(encoding="utf-8")
        xml = (repository / "modules/world_partition/doc_classes/WorldPartition3D.xml").read_text(encoding="utf-8")
        native_tests = (repository / "modules/world_partition/tests/test_world_partition_3d.h").read_text(encoding="utf-8")
        npc = (ROOT / "scripts/streamed_patrol_agent.gd").read_text(encoding="utf-8")
        forest = (ROOT / "scripts/streamed_forest_cell.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_navigation_routes.gd").read_text(encoding="utf-8")

        for name in ("get_navigation_route_cells", "is_navigation_route_ready",
                     "get_streamed_navigation_path"):
            self.assertIn(name + "(", header)
            self.assertIn("WorldPartition3D::" + name + "(", cpp)
            self.assertIn('D_METHOD("' + name + '"', cpp)
            self.assertIn('method name="' + name + '"', xml)

        self.assertIn("p_max_cells < 1 || p_max_cells > 256", cpp)
        self.assertIn("Math::is_equal_approx(t_max_x, t_max_z)", cpp)
        self.assertIn("const bool boundary_x = step_x == 0", cpp)
        self.assertIn("const bool boundary_z = step_z == 0", cpp)
        self.assertIn("result.push_back(Vector2i(p_cell.x - 1, p_cell.y))", cpp)
        self.assertIn("result.push_back(Vector2i(p_cell.x, p_cell.y - 1))", cpp)
        self.assertIn("append_cell(Vector2i(cell.x + step_x, cell.y))", cpp)
        self.assertIn("append_cell(Vector2i(cell.x, cell.y + step_z))", cpp)
        self.assertIn("return Array(); // Never report a silently truncated corridor.", cpp)
        self.assertIn("is_cell_navigation_ready(cells[i])", cpp)
        self.assertIn("navigation->map_get_path(", cpp)
        self.assertIn("get_world_3d()", cpp)
        self.assertIn("route[route.size() - 1].distance_to(p_to_global)", cpp)
        self.assertIn("is_navigation_route_ready(route[i - 1], route[i], p_max_cells)", cpp)
        self.assertIn("Supercover navigation corridor respects streaming", native_tests)

        self.assertIn("navigator.velocity_computed.connect(_on_safe_velocity)", npc)
        self.assertIn("navigator.velocity = desired", npc)
        self.assertIn("navigator.avoidance_enabled = true", npc)
        self.assertIn("streaming_world.is_navigation_route_ready(global_position, target, 16)", npc)
        self.assertIn("streaming_world.get_streamed_navigation_path(", npc)
        self.assertIn("intercell_route_count += 1", npc)
        self.assertIn("NavigationObstacle3D.new()", forest)
        self.assertIn("MAX_TREE_AVOIDANCE_OBSTACLES: int = 8", forest)
        self.assertIn("MAX_ROCK_AVOIDANCE_OBSTACLES: int = 3", forest)
        self.assertIn("avoidance.affect_navigation_mesh = false", forest)
        self.assertIn("stream.get_navigation_route_cells(from, to)", smoke)
        self.assertIn("stream.get_streamed_navigation_path(", smoke)
        self.assertIn("stream.is_navigation_route_ready(from, to)", smoke)
        self.assertIn('guard.get("intercell_route_count")', smoke)
        self.assertIn("stream.unpin_cell(EAST)", smoke)

    def test_navigation_supercover_route_geometry(self) -> None:
        """Conservative corridor catches corners, reverse paths and limits."""
        self.assertEqual(
            route_supercover(2, 9, 70, 9),
            [(0, 0), (1, 0), (2, 0)],
        )
        self.assertEqual(
            route_supercover(70, 9, 2, 9),
            [(2, 0), (1, 0), (0, 0)],
        )
        self.assertEqual(
            route_supercover(1, 1, 65, 65),
            [(0, 0), (1, 0), (0, 1), (1, 1),
             (2, 1), (1, 2), (2, 2)],
        )
        self.assertEqual(
            route_supercover(-1, -1, -65, -1),
            [(-1, -1), (-2, -1), (-3, -1)],
        )
        self.assertEqual(route_supercover(2, 9, 20, 20, 1), [(0, 0)])
        self.assertEqual(route_supercover(2, 9, 70, 9, 2), [])
        self.assertEqual(route_supercover(1, 1, 65, 65, 6), [])
        self.assertEqual(route_supercover(1, 1, 65, 65, 7)[-1], (2, 2))
        self.assertEqual(
            route_supercover(32, 1, 32, 70),
            [(1, 0), (0, 0), (1, 1), (0, 1), (1, 2), (0, 2)],
        )
        self.assertEqual(
            route_supercover(1, 32, 70, 32),
            [(0, 1), (0, 0), (1, 1), (1, 0), (2, 1), (2, 0)],
        )
        self.assertEqual(
            route_supercover(32, 32, 32, 32),
            [(1, 1), (0, 1), (1, 0), (0, 0)],
        )
        self.assertEqual(route_supercover(32, 1, 32, 70, 5), [])

    def test_streamed_navigation_and_agent_contract(self) -> None:
        """Native NavServer readiness must match the actual procedural game."""
        repository = ROOT.parents[1]
        header = (repository / "modules/world_partition/world_partition_3d.h").read_text(encoding="utf-8")
        cpp = (repository / "modules/world_partition/world_partition_3d.cpp").read_text(encoding="utf-8")
        xml = (repository / "modules/world_partition/doc_classes/WorldPartition3D.xml").read_text(encoding="utf-8")
        native_test = (repository / "modules/world_partition/tests/test_world_partition_3d.h").read_text(encoding="utf-8")
        forest = (ROOT / "scripts/streamed_forest_cell.gd").read_text(encoding="utf-8")
        nav_patch = (ROOT / "scripts/streamed_navigation_patch.gd").read_text(encoding="utf-8")
        agent = (ROOT / "scripts/streamed_patrol_agent.gd").read_text(encoding="utf-8")
        world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_navigation_streaming.gd").read_text(encoding="utf-8")

        native_api = (
            "is_cell_navigation_ready", "are_cells_navigation_ready",
            "get_navigation_ready_cell_count", "get_navigation_pending_cell_count",
            "is_streaming_source_navigation_ready",
            "get_streaming_source_navigation_progress",
        )
        for method in native_api:
            self.assertIn(method + "(", header)
            self.assertIn("WorldPartition3D::" + method + "(", cpp)
            self.assertIn('D_METHOD("' + method + '"', cpp)
            self.assertIn('method name="' + method + '"', xml)

        self.assertIn("navigation_pending_regions;", header)
        self.assertIn("navigation_ready_regions;", header)
        self.assertIn("NavigationServer3D::get_singleton()", cpp)
        self.assertIn("region_get_iteration_id(region_rid) > 0", cpp)
        self.assertIn("map_get_iteration_id(map) > 0", cpp)
        self.assertIn("region_get_map(region_rid) == map", cpp)
        self.assertIn("region_get_enabled(region_rid)", cpp)
        self.assertIn("is_cell_physics_ready(p_cell)", cpp)
        self.assertIn("navigation_pending_regions.insert(p_cell", cpp)
        self.assertIn("navigation_pending_regions.erase(p_cell)", cpp)
        self.assertIn("stale.push_back(E.key)", cpp)
        self.assertIn("navigation_pending_regions.erase(cell)", cpp)
        self.assertIn("navigation_pending_regions.insert(cell, region_id)", cpp)
        self.assertIn("navigation_ready_regions.erase(p_cell)", cpp)
        self.assertIn("navigation_pending_regions.insert(cell, region_id)", cpp)
        self.assertIn('SNAME("cell_navigation_ready")', cpp)
        self.assertIn('SNAME("cell_navigation_unready")', cpp)
        self.assertIn('signal name="cell_navigation_ready"', xml)
        self.assertIn('signal name="cell_navigation_unready"', xml)
        self.assertIn("Instantiated cells without navigation remain nav-unready", native_test)

        self.assertIn('const NavigationPatch = preload("res://scripts/streamed_navigation_patch.gd")', forest)
        self.assertIn('const ForestPatrol = preload("res://scripts/streamed_patrol_agent.gd")', forest)
        self.assertIn('navigation.name = "GroundNavigation"', forest)
        self.assertIn('_spawn_patrol(cell_x, cell_z)', forest)
        self.assertIn("TerrainHeight.height_at(world_x, world_z)", nav_patch)
        self.assertIn("const STEP: int = 4", nav_patch)
        self.assertIn("const SAMPLE_COUNT: int = EDGE / STEP + 1", nav_patch)
        self.assertIn("nav.vertices = vertices", nav_patch)
        self.assertIn("nav.add_polygon(PackedInt32Array([", nav_patch)
        self.assertIn("navigation_mesh = nav", nav_patch)
        self.assertIn("extends CharacterBody3D", agent)
        self.assertIn("NavigationAgent3D.new()", agent)
        self.assertIn("streaming_world.is_cell_navigation_ready(owning_cell)", agent)
        self.assertIn("navigator.get_next_path_position()", agent)
        self.assertIn("move_and_slide()", agent)
        self.assertIn('world_partition.get_streaming_source_navigation_progress(SURVEY_SOURCE)', world)
        self.assertIn('world_partition.get_navigation_ready_cell_count()', world)
        self.assertIn("cell_navigation_ready.connect(_on_stream_cell_navigation_ready)", world)
        self.assertIn("cell_navigation_unready.connect(_on_stream_cell_navigation_unready)", world)
        self.assertIn('NavigationServer3D.region_get_iteration_id(region_rid)', smoke)
        self.assertIn('NavigationServer3D.map_get_path(', smoke)
        self.assertIn('nav_a.enabled = false', smoke)
        self.assertIn('nav_a.enabled = true', smoke)
        self.assertIn('west_world.is_equal_approx(east_world)', smoke)

    def test_navigation_tile_edge_geometry(self) -> None:
        """Independent 4m nav grid model: 81 vertices, 128 triangles, no seam."""
        side = 9
        step = 4
        samples = [(x * step, z * step) for z in range(side) for x in range(side)]
        self.assertEqual(len(samples), 81)
        self.assertEqual((side - 1) * (side - 1) * 2, 128)
        for tile_z in (-8, 0, 7):
            for tile_x in (-4, 0, 8):
                for z in range(side):
                    west = tile_sample(tile_x, tile_z, 32, z * 4)[0]
                    east = tile_sample(tile_x + 1, tile_z, 0, z * 4)[0]
                    self.assertAlmostEqual(west, east, places=10)

    def test_native_physics_activation_and_gameplay_contract(self) -> None:
        """Two real physics ticks gate scene activation and game collisions."""
        repository = ROOT.parents[1]
        header = (repository / "modules/world_partition/world_partition_3d.h").read_text(encoding="utf-8")
        cpp = (repository / "modules/world_partition/world_partition_3d.cpp").read_text(encoding="utf-8")
        xml = (repository / "modules/world_partition/doc_classes/WorldPartition3D.xml").read_text(encoding="utf-8")
        native_tests = (repository / "modules/world_partition/tests/test_world_partition_3d.h").read_text(encoding="utf-8")
        world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
        player = (ROOT / "scripts/explorer_character.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_physics_readiness.gd").read_text(encoding="utf-8")
        physics_smoke = (ROOT / "tests/smoke_physics.gd").read_text(encoding="utf-8")
        travel_smoke = (ROOT / "tests/smoke_fast_travel.gd").read_text(encoding="utf-8")

        self.assertIn("physics_pending_cells;", header)
        self.assertIn("physics_ready_cells;", header)
        self.assertIn("uint64_t physics_tick_counter = 0;", header)
        for method in (
            "is_cell_physics_ready", "are_cells_physics_ready",
            "get_physics_ready_cell_count",
        ):
            self.assertIn(method + "(", header)
            self.assertIn("WorldPartition3D::" + method + "(", cpp)
            self.assertIn('D_METHOD("' + method + '"', cpp)
            self.assertIn('method name="' + method + '"', xml)

        self.assertIn("physics_pending_cells.insert(p_cell, physics_tick_counter + 2)", cpp)
        self.assertIn("physics_tick_counter++;", cpp)
        self.assertIn("NOTIFICATION_PHYSICS_PROCESS", cpp)
        self.assertIn("NOTIFICATION_ENTER_TREE", cpp)
        self.assertIn("physics_pending_cells.erase(p_cell)", cpp)
        self.assertIn("physics_ready_cells.erase(p_cell)", cpp)
        self.assertIn("set_physics_process(runtime && streaming_enabled", cpp)
        self.assertIn('SNAME("cell_physics_ready")', cpp)
        self.assertIn('SNAME("cell_physics_unready")', cpp)
        self.assertIn('signal name="cell_physics_ready"', xml)
        self.assertIn('signal name="cell_physics_unready"', xml)
        self.assertIn("Physics activation barrier resets on unload and re-stream", native_tests)
        self.assertIn("SceneTree::get_singleton()->physics_process(1.0 / 60.0)", native_tests)

        self.assertIn("cell_physics_ready.connect(_on_stream_cell_physics_ready)", world)
        self.assertIn("cell_physics_unready.connect(_on_stream_cell_physics_unready)", world)
        self.assertIn('world_partition.is_cell_physics_ready(cell)', world)
        self.assertIn('streaming_world.is_cell_physics_ready(cell)', player)
        self.assertIn('world_partition.are_cells_physics_ready(target_cell, 0)', world)
        self.assertIn('hit.get("collider") != terrain_body', world)
        self.assertIn("_fast_travel_verify_attempts >= 8", world)
        self.assertIn("_fast_travel_verify_attempts >= 90", world)
        self.assertIn('get_world_3d().direct_space_state.intersect_ray(ray)', world)
        self.assertIn('get_physics_ready_cell_count()', world)
        self.assertIn("stream.cell_physics_ready.connect", smoke)
        self.assertIn("stream.cell_physics_unready.connect", smoke)
        self.assertIn("stream.get_physics_ready_cell_count() != 1", smoke)
        self.assertIn("stream.is_cell_physics_ready(origin)", physics_smoke)
        self.assertIn("stream.is_cell_physics_ready(OUTPOST_CELL)", travel_smoke)
        self.assertIn("stream.is_cell_physics_ready(HOME_CELL)", travel_smoke)

    def test_native_manual_pin_streaming_contract(self) -> None:
        """Engine pins, editor docs and playable fast travel stay in sync."""
        repository = ROOT.parents[1]
        header = (repository / "modules/world_partition/world_partition_3d.h").read_text(encoding="utf-8")
        cpp = (repository / "modules/world_partition/world_partition_3d.cpp").read_text(encoding="utf-8")
        xml = (repository / "modules/world_partition/doc_classes/WorldPartition3D.xml").read_text(encoding="utf-8")
        native_tests = (repository / "modules/world_partition/tests/test_world_partition_3d.h").read_text(encoding="utf-8")
        world = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")
        smoke = (ROOT / "tests/smoke_pinned_cells.gd").read_text(encoding="utf-8")
        travel = (ROOT / "tests/smoke_fast_travel.gd").read_text(encoding="utf-8")

        self.assertIn("static constexpr int MAX_PINNED_CELLS = 16;", header)
        for method in ("pin_cell", "unpin_cell", "clear_pinned_cells",
                       "is_cell_pinned", "get_pinned_cell_count"):
            self.assertIn(method + "(", header)
            self.assertIn("WorldPartition3D::" + method + "(", cpp)
            self.assertIn('D_METHOD("' + method + '"', cpp)
            self.assertIn('method name="' + method + '"', xml)

        self.assertIn("_get_scene_path(p_cell).is_empty()", cpp)
        self.assertIn("pinned_cells.size() >= MAX_PINNED_CELLS", cpp)
        self.assertIn("pinned_cells.erase(p_cell)", cpp)
        self.assertIn("pinned_cells.clear()", cpp)
        self.assertIn("!pinned_cells.has(E.key)", cpp)
        self.assertIn("Vector<Vector2i> pinned_snapshot;", cpp)
        self.assertIn("if (pinned_cells.has(cell))", cpp)
        self.assertLess(cpp.index("for (int radius = 0; radius <= load_radius; radius++)"),
                        cpp.index("Vector<Vector2i> pinned_snapshot;"))
        self.assertLess(cpp.index("Vector<Vector2i> pinned_snapshot;"),
                        cpp.index("prefetch_coordinate(step, ahead)"))

        self.assertIn("Pinned cells are registered bounded and lifecycle-safe", native_tests)
        self.assertIn("Pinned remote cells load and unload independently", native_tests)
        self.assertIn("OUTPOST_CELL: Vector2i = Vector2i(6, 6)", world)
        self.assertIn("OUTPOST_POSITION: Vector2 = Vector2(208.0, 208.0)", world)
        self.assertIn("KEY_F6:", world)
        self.assertIn("KEY_F7:", world)
        self.assertIn("world_partition.pin_cell(target_cell)", world)
        self.assertIn("world_partition.are_cells_physics_ready(target_cell, 0)", world)
        self.assertIn("world_partition.unpin_cell(_fast_travel_target_cell)", world)
        self.assertIn("_fast_travel_in_progress = true", world)
        self.assertIn("func _physics_process(_delta: float) -> void:", world)
        self.assertIn("get_world_3d().direct_space_state.intersect_ray(ray)", world)
        self.assertIn("func _cancel_fast_travel(reason: String) -> void:", world)
        self.assertIn("if not world_partition.are_cells_physics_ready(target_cell, 0):", world)
        self.assertIn('world.get("_fast_travel_in_progress")', travel)
        self.assertIn("await physics_frame", travel)

        self.assertIn("world_partition.get_pinned_cell_count()", world)
        self.assertIn("stream.pin_cell(remote)", smoke)
        self.assertIn("stream.clear_pinned_cells()", smoke)
        self.assertIn('world.call("_fast_travel")', travel)
        self.assertIn("FastTravelOutpost", travel)

    def test_native_directional_prefetch_contract(self) -> None:
        """Spot-check the native engine integration as well as the GDScript client."""
        repository = ROOT.parents[1]
        cpp = (repository / "modules/world_partition/world_partition_3d.cpp").read_text(encoding="utf-8")
        header = (repository / "modules/world_partition/world_partition_3d.h").read_text(encoding="utf-8")
        xml = (repository / "modules/world_partition/doc_classes/WorldPartition3D.xml").read_text(encoding="utf-8")
        native_tests = (repository / "modules/world_partition/tests/test_world_partition_3d.h").read_text(encoding="utf-8")

        for method in ("set_prefetch_direction", "get_prefetch_direction",
                       "set_prefetch_distance", "get_prefetch_distance"):
            self.assertIn(method, cpp)
            self.assertIn(method, header)
        self.assertIn('member name="prefetch_direction"', xml)
        self.assertIn('member name="prefetch_distance"', xml)
        self.assertIn("Directional corridor prefetch prioritizes observer", native_tests)
        self.assertIn("int prefetch_distance = 0;", header)
        self.assertIn("prefetch_direction == Vector2i()", cpp)
        self.assertIn("!is_prefetch_cell(E.key)", cpp)
        self.assertIn("prefetch_coordinate(step, ahead)", cpp)
        self.assertLess(cpp.index("for (int radius = 0; radius <= load_radius; radius++)"),
                        cpp.index("prefetch_coordinate(step, ahead)"))
        self.assertIn("int64_t(center.x) + int64_t(prefetch_direction.x) * p_step", cpp)
        self.assertIn("can_instantiate()", cpp)
        self.assertIn("WorldPartition3D::retry_failed_cells()", cpp)
        self.assertIn("void retry_failed_cells();", header)
        self.assertIn('method name="retry_failed_cells"', xml)
        native_retry = (repository / "modules/world_partition/tests/test_world_partition_3d_extra.h").read_text(encoding="utf-8")
        self.assertIn("fixture.world->retry_failed_cells();", native_retry)


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
        assert "world_partition.is_cell_physics_ready(cell)" in world
        assert "_position_has_terrain" in player
        assert "WORLD_CELLS_PER_SIDE: int = 32" in world
        assert "world_partition.set_cell_scenes(registered_cells)" in world
        assert 'registered_cells[Vector2i(cx, cz)] = "res://cells/forest_cell.tscn"' in world
        assert "world_partition.set_cell_scene(" not in world

        assert "WORLD_EXTENT: float = 512.0" in world

        cache = (ROOT / "scripts/terrain_tile_cache.gd").read_text(encoding="utf-8")
        assert "MAX_CACHED_TILES: int = 12" in cache
        assert "_lru.erase(cell)" in cache
        assert "_tiles.erase(oldest)" in cache
        assert "TerrainTileCache.lookup(cell)" in patch
        assert "TerrainTileCache.insert(cell, mesh, collision_shape)" in patch
        assert "_create_patch_nodes(cached[\"mesh\"], cached[\"shape\"])" in patch
        shared = (ROOT / "scripts/forest_shared_assets.gd").read_text(encoding="utf-8")
        assert "SharedAssets.ground_material()" in patch
        assert "SharedAssets.tree_trunk()" in forest
        assert "SharedAssets.tree_canopy()" in forest
        assert "SharedAssets.grass_blade()" in forest
        assert "SharedAssets.rock_mesh()" in forest
        assert "static var _trunk: CylinderMesh" in shared
        assert "static var _ground_material: StandardMaterial3D" in shared
        assert "world_partition.prefetch_distance = 2" in world
        assert "world_partition.prefetch_direction = direction" in world
        assert "_update_predictive_streaming()" in world
        assert "prefetch_direction" in (
            ROOT / "tests/smoke_prefetch.gd"
        ).read_text(encoding="utf-8")



