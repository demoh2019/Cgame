"""Guard source-level no-copy contracts for hot-path C++ collection reads.

These checks do not replace compilation, runtime tests or benchmarks.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ZeroCopyCollectionsContracts(unittest.TestCase):

    def test_class_db_1(self):
        source = (ROOT / "core/object/class_db.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const LocalVector<MethodBind *> &compat = E.value;"), 1)

    def test_ip_2(self):
        source = (ROOT / "core/io/ip.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const List<IPAddress> &res = resolver->queue[p_id].response;"), 2)

    def test_filesystem_dock_3(self):
        source = (ROOT / "editor/docks/filesystem_dock.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const HashMap<StringName, PropertyInfo> &prop_info = ProjectSettings::get_singleton()->get_custom_property_info();"), 1)

    def test_editor_export_4(self):
        source = (ROOT / "editor/export/editor_export.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const List<EditorExportPlatform::ExportOption> &options = platform_options[preset->get_platform()->get_name()];"), 1)

    def test_scene_import_settings_5(self):
        source = (ROOT / "editor/import/3d/scene_import_settings.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const HashMap<StringName, Variant> &settings = animation_map[selected_id].settings;"), 1)
        self.assertEqual(source.count("const HashMap<StringName, Variant> &settings = animation_map[p_animation_name].settings;"), 1)

    def test_scene_tree_editor_6(self):
        source = (ROOT / "editor/scene/scene_tree_editor.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const List<Node *> &selection = editor_selection->get_top_selected_node_list();"), 1)

    def test_shader_create_dialog_7(self):
        source = (ROOT / "editor/shader/shader_create_dialog.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const List<String> &extensions = type_data.get(type_menu->get_selected()).extensions;"), 1)

    def test_editor_properties_8(self):
        source = (ROOT / "editor/inspector/editor_properties.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const HashMap<String, List<Ref<InputEvent>>> &builtins = InputMap::get_singleton()->get_builtins();"), 1)

    def test_group_settings_editor_9(self):
        source = (ROOT / "editor/scene/group_settings_editor.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count("const HashMap<StringName, HashSet<StringName>> &scene_groups_cache = ProjectSettings::get_singleton()->get_scene_groups_cache();"), 1)


if __name__ == "__main__":
    unittest.main()
