"""Source contracts for selected Godot upstream fixes.

These verify patch placement but DO NOT replace native builds or XR hardware tests.
Execute: python -m unittest discover -s misc/scripts/tests -p test_upstream_game_extensions_20261119.py -v
"""
from __future__ import annotations
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def method(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError("Unbalanced C++ method: " + signature)


class EmbeddedGameFocusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = read("editor/run/game_view_plugin.cpp")
        cls.method = method(cls.source, "void GameView::_embedded_process_focused()")

    def test_dock_manager_restores_focus(self):
        self.assertIn("EditorDockManager::get_singleton()->force_focus_dock(game_dock);", self.method)

    def test_stale_visibility_only_call_was_replaced(self):
        self.assertNotIn("game_dock->make_visible();", self.method)

    def test_focus_requires_embed_on_play(self):
        self.assertRegex(self.method, r"if \(embed_on_play && !window_wrapper->get_window_enabled\(\)\)")

    def test_focus_requires_native_window_disabled(self):
        self.assertLess(self.method.index("!window_wrapper->get_window_enabled()"),
                        self.method.index("force_focus_dock(game_dock)"))

    def test_focus_is_requested_only_once(self):
        self.assertEqual(self.method.count("force_focus_dock(game_dock)"), 1)

    def test_editor_already_uses_this_dock_api(self):
        self.assertGreaterEqual(self.source.count("EditorDockManager::get_singleton()->force_focus_dock(game_dock)"), 2)


class GDExtensionInitializationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = read("core/extension/gdextension_manager.cpp")
        cls.load = method(cls.source, "GDExtensionManager::LoadStatus GDExtensionManager::_load_extension_internal(")
        cls.unload = method(cls.source, "GDExtensionManager::LoadStatus GDExtensionManager::_unload_extension_internal(")

    def test_loading_is_conditioned_on_initialized_engine(self):
        self.assertIn("if (level >= 0)", self.load)

    def test_reload_restart_guard_preserved(self):
        self.assertIn("if (!p_first_load)", self.load)
        self.assertIn("return LOAD_STATUS_NEEDS_RESTART;", self.load)

    def test_minimum_level_only_limits_reload_guard(self):
        start = self.load.index("if (!p_first_load)")
        end = self.load.index("// Initialize up to current level", start)
        self.assertIn("get_minimum_library_initialization_level()", self.load[start:end])

    def test_initialization_always_starts_at_core(self):
        self.assertRegex(self.load, r"for \(int32_t i = GDExtension::INITIALIZATION_LEVEL_CORE; i <= level; i\+\+\)")

    def test_initialization_is_in_ascending_order(self):
        self.assertIn("initialize_library(GDExtension::InitializationLevel(i))", self.load)

    def test_unload_is_in_reverse_order_to_core(self):
        self.assertRegex(self.unload,
                         r"for \(int32_t i = level; i >= GDExtension::INITIALIZATION_LEVEL_CORE; i--\)")

    def test_sentinel_restart_boundary_remains_scene(self):
        self.assertIn("minimum_level < MIN(level, GDExtension::INITIALIZATION_LEVEL_SCENE)", self.load)

    def test_success_status_preserved(self):
        self.assertIn("return LOAD_STATUS_OK;", self.load)


class OpenXRCompositionLayerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.extension = read("modules/openxr/extensions/openxr_composition_layer_extension.cpp")
        cls.scene = read("modules/openxr/scene/openxr_composition_layer.cpp")
        cls.free = method(cls.extension, "void OpenXRCompositionLayerExtension::_composition_layer_free_rt(")
        cls.register = method(cls.extension, "void OpenXRCompositionLayerExtension::_composition_layer_register_rt(")
        cls.unregister = method(cls.extension, "void OpenXRCompositionLayerExtension::_composition_layer_unregister_rt(")
        cls.notify = method(cls.scene, "void OpenXRCompositionLayer::_notification(")

    def test_free_takes_mutex_before_unregister(self):
        self.assertLess(self.free.index("MutexLock lock(composition_layer_mutex)"),
                        self.free.index("_composition_layer_unregister_rt(p_layer)"))

    def test_free_mutex_covers_owner_lookup(self):
        self.assertLess(self.free.index("MutexLock lock(composition_layer_mutex)"),
                        self.free.index("composition_layer_owner.get_or_null(p_layer)"))

    def test_free_mutex_covers_owner_release(self):
        self.assertLess(self.free.index("MutexLock lock(composition_layer_mutex)"),
                        self.free.index("composition_layer_owner.free(p_layer)"))

    def test_unregister_does_not_double_lock(self):
        self.assertNotIn("MutexLock lock(composition_layer_mutex)", self.unregister)

    def test_register_checks_null_layer(self):
        self.assertIn("ERR_FAIL_NULL(layer)", self.register)

    def test_registration_checks_for_existing_layer(self):
        self.assertIn("if (!registered_composition_layers.has(layer))", self.register)

    def test_registration_adds_layer_only_within_guard(self):
        self.assertRegex(self.register,
                         r"if \(!registered_composition_layers.has\(layer\)\)\s*\{\s*registered_composition_layers.push_back\(layer\);")

    def test_visibility_notification_avoids_double_setup(self):
        block = self.notify[self.notify.index("case NOTIFICATION_VISIBILITY_CHANGED"):
                            self.notify.index("case NOTIFICATION_LOCAL_TRANSFORM_CHANGED")]
        self.assertRegex(block, r"if \(!registered\)\s*\{\s*_setup_composition_layer\(\);")

    def test_visibility_still_updates_transform(self):
        block = self.notify[self.notify.index("case NOTIFICATION_VISIBILITY_CHANGED"):
                            self.notify.index("case NOTIFICATION_LOCAL_TRANSFORM_CHANGED")]
        self.assertIn("update_transform();", block)

    def test_enter_tree_checks_registration_preconditions(self):
        block = self.notify[self.notify.index("case NOTIFICATION_ENTER_TREE"):
                            self.notify.index("case NOTIFICATION_PARENTED")]
        self.assertIn("else if (_should_register())", block)

    def test_register_preconditions_check_lifecycle_and_visibility(self):
        body = method(self.scene, "bool OpenXRCompositionLayer::_should_register()")
        for expression in ("!registered", "openxr_session_running", "is_inside_tree()", "is_visible_in_tree()", "is_natively_supported()"):
            with self.subTest(expression=expression):
                self.assertIn(expression, body)


if __name__ == "__main__":
    unittest.main()
