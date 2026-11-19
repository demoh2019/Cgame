#!/usr/bin/env python3
"""RenderingDevice dependency map compaction and iterator safety contracts.

Native tests exercise the actual AHashMap<RID, HashSet<RID>> behavior, including
the order-changing erase operation and recursive resource graph teardown.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "servers/rendering/rendering_device.cpp"
HEADER = ROOT / "servers/rendering/rendering_device.h"
NATIVE = ROOT / "tests/core/templates/test_render_dependency_hash_map.cpp"


class RenderDependencyCompactMaps(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = SOURCE.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        a = cls.cpp.index("void RenderingDevice::_free_dependencies(")
        b = cls.cpp.index("\nvoid RenderingDevice::_replace_dependency(", a)
        cls.free = cls.cpp[a:b]

    def test_compact_maps_are_owned_by_device(self):
        self.assertIn('#include "core/templates/a_hash_map.h"', self.header)
        self.assertIn("AHashMap<RID, HashSet<RID>> dependency_map;", self.header)
        self.assertIn("AHashMap<RID, HashSet<RID>> reverse_dependency_map;", self.header)
        self.assertNotIn("\tHashMap<RID, HashSet<RID>> dependency_map;", self.header)

    def test_call_sites_use_matching_iterator_types(self):
        self.assertEqual(self.cpp.count("AHashMap<RID, HashSet<RID>>::Iterator"), 6)
        self.assertNotIn("HashMap<RID, HashSet<RID>>::Iterator", self.cpp.replace("AHashMap<RID, HashSet<RID>>::Iterator", ""))

    def test_recurse_does_not_hold_iterator_across_free(self):
        self.assertIn("while (true) {", self.free)
        self.assertIn("AHashMap<RID, HashSet<RID>>::Iterator E = dependency_map.find(p_id);", self.free)
        self.assertIn("const RID dependent = *E->value.begin();", self.free)
        self.assertIn("free_rid(dependent);", self.free)
        self.assertIn("dependency_map.erase(p_id);", self.free)
        self.assertNotIn("while (E->value.size())", self.free)

    def test_reverse_graph_edges_are_updated(self):
        self.assertIn("reverse_dependency_map.find(p_id)", self.free)
        self.assertIn("dependency_map.find(F)", self.free)
        self.assertIn("G->value.erase(p_id);", self.free)
        self.assertIn("reverse_dependency_map.remove(E);", self.free)

    def test_reference_map_operations_still_supported(self):
        section = self.cpp[
            self.cpp.index("void RenderingDevice::_add_dependency("):
            self.cpp.index("void RenderingDevice::_free_dependencies(")
        ]
        self.assertIn("dependency_map.getptr(p_depends_on)", section)
        self.assertIn("reverse_dependency_map.getptr(p_id)", section)
        self.assertIn("dependency_map.insert(p_depends_on, HashSet<RID>())", section)

    def test_native_test_cases_cover_growth_and_lifecycle(self):
        self.assertIn("TEST_FORCE_LINK(test_render_dependency_hash_map)", self.native)
        self.assertEqual(self.native.count('TEST_CASE("[RenderDependencyMap]'), 6)
        for marker in (
            "Nested dependency sets preserve keys through growth",
            "Erasing map keys preserves relocated nested sets",
            "Recursive freeing relooks up after container relocation",
            "Replacing a dependency preserves both directions",
            "Duplicate edges are idempotent",
            "Clear and reserve allow repeated resource lifecycles",
        ):
            self.assertIn(marker, self.native)


if __name__ == "__main__":
    unittest.main()
