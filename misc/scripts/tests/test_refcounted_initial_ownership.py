#!/usr/bin/env python3
"""Regression contracts for RefCounted initial-reference ownership.

This is a source-level guard, not a memory-safety or concurrency proof.
Companion C++ tests cover creation/copy/legacy wrapping and destruction.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
REF_HEADER = ROOT / "core/object/ref_counted.h"
REF_SOURCE = ROOT / "core/object/ref_counted.cpp"
MEMORY = ROOT / "core/os/memory.h"
CLASSDB = ROOT / "core/object/class_db.cpp"
NATIVE = ROOT / "tests/core/object/test_refcounted_initial_ownership.cpp"

class RefCountedFastOwnershipContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = REF_HEADER.read_text(encoding="utf-8")
        cls.cpp = REF_SOURCE.read_text(encoding="utf-8")
        cls.mem = MEMORY.read_text(encoding="utf-8")
        cls.db = CLASSDB.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_no_old_initialization_ref_counter(self):
        self.assertNotIn("refcount_init", self.h)
        self.assertNotIn("refcount_init", self.cpp)
        self.assertIn("SafeNumeric<uint32_t> negative_refcount{ 0 };", self.h)
        self.assertIn("SafeNumeric<uint32_t> dereference_count{ 0 };", self.h)

    def test_no_increment_unreference_cycle_for_initial_ownership(self):
        self.assertIn("if (negative_refcount.get() > 0 && negative_refcount.decrement() == 0)", self.cpp)
        self.assertIn("negative_refcount.increment();", self.cpp)
        self.assertIn("refcount.init();", self.cpp)
        self.assertNotIn("refcount_init.init();", self.cpp)

    def test_memnew_wraps_newly_created_object_once(self):
        self.assertIn("static T *wrap(T *p_obj) { return p_obj; }", self.mem)
        self.assertIn("postinitialize_handler(p_obj);", self.mem)
        self.assertIn("return memnew_result<T>::wrap(p_obj);", self.mem)
        self.assertNotIn("memnew_result_t<T> result{ p_obj };", self.mem)

    def test_refcounted_memnew_assumes_existing_reference(self):
        self.assertIn("static Ref assume_ownership(T *p_object)", self.h)
        self.assertIn("result.reference = p_object;", self.h)
        self.assertIn("static Ref<T> wrap(T *p_object)", self.h)
        self.assertIn("return Ref<T>::assume_ownership(p_object);", self.h)
        self.assertNotIn("postinitialize_handler(Ref<T> &p_object)", self.h)

    def test_classdb_legacy_without_refcount_preserved(self):
        self.assertIn("if (!p_with_refcount && object != nullptr && object->is_ref_counted())", self.db)
        self.assertIn("((RefCounted *)object)->deinit_ref();", self.db)
        self.assertNotIn("ref_counted->init_ref();", self.db)

    def test_native_tests_cover_reference_lifecycle(self):
        self.assertIn("TEST_FORCE_LINK(test_refcounted_initial_ownership)", self.native)
        self.assertEqual(self.native.count('TEST_CASE("[RefInitialOwnership]'), 8)
        for token in ("ClassDB::instantiate", "get_reference_count()", "assume_ownership",
                      "ObjectDB::get_instance", "std::thread", "memnew(PlainObject)"):
            self.assertIn(token, self.native)

if __name__ == "__main__":
    unittest.main()
