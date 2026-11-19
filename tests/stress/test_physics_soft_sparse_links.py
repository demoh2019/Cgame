"""Sparse soft-body edge construction and bending-link graph contracts.

Run:
    python3 -m unittest discover -s tests/stress -p 'test_physics_soft_sparse_links.py'

The graph tests compare against independent shortest-path search. A compiled
Godot binary is still required for runtime correctness and throughput checks.
"""
from collections import deque
from pathlib import Path
from random import Random
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOFT_BODY_SOURCE = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"


def make_edges(triangles):
    """Reference for orientation-independent triangle edge deduplication."""
    result = set()
    for a, b, c in triangles:
        for u, v in ((a, b), (b, c), (c, a)):
            if u != v:
                result.add(tuple(sorted((u, v))))
    return result


def sparse_bending(node_count, structural_edges, distance=2):
    adjacency = [[] for _ in range(node_count)]
    registered = set(structural_edges)
    for a, b in structural_edges:
        adjacency[a].append(b)
        adjacency[b].append(a)

    bending = set()
    if distance == 2:
        for neighbors in adjacency:
            for i, a in enumerate(neighbors):
                for b in neighbors[i + 1:]:
                    edge = tuple(sorted((a, b)))
                    if edge not in registered:
                        registered.add(edge)
                        bending.add(edge)
    else:
        for origin in range(node_count):
            visited = [-1] * node_count
            visited[origin] = 0
            frontier = deque([origin])
            while frontier:
                node = frontier.popleft()
                if visited[node] >= distance:
                    continue
                for neighbor in adjacency[node]:
                    if visited[neighbor] != -1:
                        continue
                    visited[neighbor] = visited[node] + 1
                    if visited[neighbor] == distance:
                        if origin < neighbor:
                            bending.add((origin, neighbor))
                    else:
                        frontier.append(neighbor)
    return bending


def reference_distance_pairs(node_count, edges, distance):
    adjacency = [[] for _ in range(node_count)]
    for a, b in edges:
        adjacency[a].append(b)
        adjacency[b].append(a)
    pairs = set()
    for origin in range(node_count):
        distances = [-1] * node_count
        distances[origin] = 0
        queue = deque([origin])
        while queue:
            vertex = queue.popleft()
            for neighbor in adjacency[vertex]:
                if distances[neighbor] == -1:
                    distances[neighbor] = distances[vertex] + 1
                    queue.append(neighbor)
        pairs.update((origin, other) for other in range(origin + 1, node_count)
                     if distances[other] == distance)
    return pairs


class SparseSoftBodyLinkContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOFT_BODY_SOURCE.read_text(encoding="utf-8")
        a = cls.source.index("bool GodotSoftBody3D::create_from_trimesh(")
        b = cls.source.index("void GodotSoftBody3D::generate_bending_constraints(", a)
        cls.mesh = cls.source[a:b]
        c = cls.source.index("// This function takes in a list of interdependent Links", b)
        cls.bending = cls.source[b:c]

    def test_no_quadratic_dense_matrix_in_mesh_constructor(self):
        self.assertIn("HashSet<uint64_t> unique_edges;", self.mesh)
        self.assertIn("_soft_body_edge_key(idx[j], idx[k])", self.mesh)
        self.assertNotIn("node_count * node_count", self.mesh)
        self.assertNotIn("LocalVector<bool> chks;", self.mesh)

    def test_bending_graph_uses_sparse_edges_and_bounded_bfs(self):
        code = self.bending
        self.assertIn("HashSet<uint64_t> registered_edges;", code)
        self.assertIn("neighbors.resize(node_count);", code)
        self.assertIn("if (p_distance == 2)", code)
        self.assertIn("if (!registered_edges.has(key))", code)
        self.assertIn("const int next_distance = distances[current] + 1;", code)
        self.assertNotIn("memnew_arr(unsigned", code)
        self.assertNotIn("adj_size", code)

    def test_reversed_and_duplicate_triangles_share_edges(self):
        edges = make_edges([(0, 1, 2), (2, 1, 0), (0, 1, 2), (1, 1, 2)])
        self.assertEqual(edges, {(0, 1), (1, 2), (0, 2)})
        self.assertEqual(sparse_bending(3, edges), set())

    def test_two_hop_edges_match_shortest_paths_for_many_graphs(self):
        rng = Random(260619)
        for node_count in range(2, 18):
            for trial in range(12):
                edges = {(i, j) for i in range(node_count)
                         for j in range(i + 1, node_count)
                         if rng.random() < 0.24}
                with self.subTest(nodes=node_count, trial=trial):
                    self.assertEqual(sparse_bending(node_count, edges),
                                     reference_distance_pairs(node_count, edges, 2))

    def test_other_distances_preserve_exact_shortest_paths(self):
        for count in (5, 9, 14):
            edges = {(i, i + 1) for i in range(count - 1)}
            edges.add((0, count - 1))
            for distance in (2, 3, 4):
                with self.subTest(nodes=count, distance=distance):
                    self.assertEqual(sparse_bending(count, edges, distance),
                                     reference_distance_pairs(count, edges, distance))

    def test_large_grid_pair_count_scales_with_mesh_not_vertex_square(self):
        width = 32
        triangles = []
        for y in range(width - 1):
            for x in range(width - 1):
                i = y * width + x
                triangles.extend(((i, i + 1, i + width),
                                  (i + 1, i + width + 1, i + width)))
        structural = make_edges(triangles)
        bending = sparse_bending(width * width, structural)
        self.assertGreater(len(bending), width * width)
        self.assertLess(len(bending), 24 * width * width)
        self.assertFalse(structural.intersection(bending))


if __name__ == "__main__":
    unittest.main()
