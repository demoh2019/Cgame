#!/usr/bin/env python3
"""Check the CoW-free area and contact working sets of GodotPhysics2D.

Complements native regression tests of the actual LocalVector operations,
and the full engine build provided by CI.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
HEADER = ROOT / "modules/godot_physics_2d/godot_body_2d.h"
SOURCE = ROOT / "modules/godot_physics_2d/godot_body_2d.cpp"
NATIVE = ROOT / "tests/core/templates/test_physics2d_local_vectors.cpp"


class LocalPhysics2DVectorContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_local_vector_type_declared(self):
        self.assertIn('#include "core/templates/local_vector.h"', self.header)
        self.assertIn("LocalVector<AreaCMP> areas;", self.header)
        self.assertIn("LocalVector<Contact> contacts;", self.header)

    def test_no_copy_on_write_container_for_area_or_contacts(self):
        self.assertNotIn("Vector<AreaCMP> areas;", self.header.replace("LocalVector<AreaCMP> areas;", ""))
        self.assertNotIn("Vector<Contact> contacts;", self.header.replace("LocalVector<Contact> contacts;", ""))
        self.assertNotIn("areas.write[", self.header)
        self.assertNotIn("contacts.ptrw()", self.header)

    def test_area_reference_bookkeeping(self):
        self.assertIn("areas[index].refCount += 1;", self.header)
        self.assertIn("areas[index].refCount -= 1;", self.header)
        self.assertIn("areas.ordered_insert(AreaCMP(p_area));", self.header)
        self.assertIn("areas.remove_at(index);", self.header)

    def test_area_iteration_uses_local_pointer(self):
        self.assertIn("areas.sort();", self.source)
        self.assertIn("const AreaCMP *aa = areas.ptr();", self.source)
        self.assertNotIn("const AreaCMP *aa = &areas[0];", self.source)

    def test_contact_mutation_and_limits_preserved(self):
        self.assertIn("Contact *c = contacts.ptr();", self.header)
        self.assertIn("contacts.resize(p_size);", self.header)
        self.assertIn("contact_count = 0;", self.header)
        self.assertIn("if (contact_count < c_max)", self.header)

    def test_companion_native_test_cases_present(self):
        self.assertEqual(self.native.count('TEST_CASE("[Physics2DLocalVector]'), 6)
        for fragment in (
            "Ordered insert preserves area priorities",
            "Area reference counts survive ordered removals",
            "Contact storage is directly mutable through ptr",
            "Resizing contacts invalidates only discarded values",
            "Contact replacement maintains deepest collisions",
            "Many area changes preserve lookup and order",
        ):
            self.assertIn(fragment, self.native)


if __name__ == "__main__":
    unittest.main()
