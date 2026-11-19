"""Regression checks for Godot #125584's cached editor translations.

The first check verifies all changed call sites; the rest protect option keys,
dialog labels, and descriptions that dynamically update with locale changes.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
EDITOR = ROOT / "editor" / "editor_node.cpp"
REQUIRED_LINES = [
    "file->set_title(TTRC(\"Save Resource As...\"));",
    "file->set_title(TTRC(\"Save scene before running...\"));",
    "bool merge_with_existing_library = fd_options.get(TTRC(\"Merge With Existing\"), true);",
    "bool apply_mesh_instance_transforms = fd_options.get(TTRC(\"Apply MeshInstance Transforms\"), false);",
    "file->set_title(p_option == SCENE_OPEN_SCENE ? TTRC(\"Open Scene\") : TTRC(\"Open Base Scene\"));",
    "file->set_title(TTRC(\"Save Scene As...\"));",
    "file->set_title(TTRC(\"Save new main scene...\"));",
    "confirmation->set_text(TTRC(\"Stop running project before reloading the current project?\"));",
    "confirmation->set_ok_button_text(TTRC(\"Stop & Reload\"));",
    "confirmation->set_text(TTRC(\"Stop running project before exiting the editor?\"));",
    "confirmation->set_ok_button_text(TTRC(\"Stop & Quit\"));",
    "confirmation->set_text(TTRC(\"The export templates are still being downloaded.\"));",
    "save_confirmation->set_ok_button_text(TTRC(\"Save & Reload\"));",
    "save_confirmation->set_text(TTRC(\"Save modified resources before reloading?\"));",
    "save_confirmation->set_ok_button_text(TTRC(\"Save & Quit\"));",
    "save_confirmation->set_text(TTRC(\"Save modified resources before closing?\"));",
    "file->set_title(TTRC(\"Pick a Main Scene\"));",
    "file_export_lib->set_title(TTRC(\"Export Mesh Library\"));",
    "file_menu->set_item_tooltip(file_menu->get_item_index(SCENE_SAVE_ALL_SCENES), TTRC(\"All scenes are already saved.\"));",
    "return TTRC(\"Multi-window support is not available because the `--single-window` command line argument was used to start the editor.\");",
    "return TTRC(\"Multi-window support is not available because the current platform doesn't support multiple windows.\");",
    "return TTRC(\"Multi-window support is not available because Interface > Editor > Single Window Mode is enabled in the editor settings.\");",
    "return TTRC(\"Multi-window support is not available because Interface > Multi Window > Enable is disabled in the editor settings.\");",
    "pick_main_scene->set_text(TTRC(\"No main scene has ever been defined. Select one?\\nYou can change it later in \\\"Project Settings\\\" under the 'application' category.\"));",
    "save_confirmation->set_ok_button_text(TTRC(\"Save & Close\"));",
    "command_palette->set_title(TTRC(\"Command Palette\"));",
    "gradle_build_manage_templates->set_text(TTRC(\"Android build template is missing, please install relevant templates.\"));",
    "gradle_build_manage_templates->set_ok_button_text(TTRC(\"Manage Templates\"));",
    "gradle_build_manage_templates->add_button(TTRC(\"Install from file\"))->connect(SceneStringName(pressed), callable_mp(this, &EditorNode::_android_install_build_template));",
    "file_android_build_source->set_title(TTRC(\"Select Android sources file\"));",
    "install_android_build_template->set_ok_button_text(TTRC(\"Install\"));",
    "file_templates->set_title(TTRC(\"Import Templates From ZIP File\"));",
    "file_templates->add_filter(\"*.tpz\", TTRC(\"Template Package\"));",
    "file_export_lib->set_title(TTRC(\"Export Library\"));",
    "file_export_lib->add_option(TTRC(\"Merge With Existing\"), Vector<String>(), true);",
    "file_export_lib->add_option(TTRC(\"Apply MeshInstance Transforms\"), Vector<String>(), false);",
    "file_pack_zip->set_title(TTRC(\"Pack Project as ZIP...\"));",
    "disk_changed->set_title(TTRC(\"Files have been modified outside Godot\"));",
    "dl->set_text(TTRC(\"The following files are newer on disk:\"));",
    "what_action_label->set_text(TTRC(\"What action should be taken?\"));",
    "disk_changed->set_ok_button_text(TTRC(\"Reload from disk\"));",
    "disk_changed->add_button(TTRC(\"Ignore external changes\"), !DisplayServer::get_singleton()->get_swap_cancel_ok(), \"resave\");",
    "open_imported->set_ok_button_text(TTRC(\"Open Anyway\"));",
    "new_inherited_button = open_imported->add_button(TTRC(\"New Inherited\"), !DisplayServer::get_singleton()->get_swap_cancel_ok(), \"inherit\");",
    "load_error_dialog->set_title(TTRC(\"Load Errors\"));",
    "pick_main_scene->set_ok_button_text(TTRC(\"Select\"));",
    "select_current_scene_button = pick_main_scene->add_button(TTRC(\"Select Current\"), true, \"select_current\");",
]


class EditorTranslationCacheBackportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = EDITOR.read_text(encoding="utf-8")
        cls.lines = {line.strip() for line in cls.source.splitlines()}

    def test_all_upstream_cached_translation_calls(self):
        for expected in REQUIRED_LINES:
            with self.subTest(label=expected):
                self.assertIn(expected, self.lines)

    def test_export_option_keys_match_dialog_definitions(self):
        for name in ("Merge With Existing", "Apply MeshInstance Transforms"):
            with self.subTest(option=name):
                self.assertIn(f'file_export_lib->add_option(TTRC("{name}")', self.source)
                self.assertIn(f'fd_options.get(TTRC("{name}")', self.source)

    def test_save_and_open_titles(self):
        for name in ("Save Resource As...", "Save Scene As...", "Open Scene",
                     "Save new main scene...", "Pick a Main Scene"):
            with self.subTest(name=name):
                self.assertIn(f'TTRC("{name}")', self.source)

    def test_confirmation_buttons_and_prompts(self):
        for name in ("Stop & Quit", "Stop & Reload", "Save & Quit",
                     "Save & Reload", "Save & Close"):
            with self.subTest(name=name):
                self.assertIn(f'TTRC("{name}")', self.source)

    def test_android_template_dialog_labels(self):
        for name in ("Manage Templates", "Install from file",
                     "Select Android sources file", "Import Templates From ZIP File"):
            with self.subTest(name=name):
                self.assertIn(f'TTRC("{name}")', self.source)

    def test_external_disk_change_dialog_labels(self):
        for name in ("Files have been modified outside Godot", "Reload from disk",
                     "Ignore external changes", "What action should be taken?"):
            with self.subTest(name=name):
                self.assertIn(f'TTRC("{name}")', self.source)

    def test_editor_dynamic_tooltips_and_palette(self):
        for name in ("Command Palette", "All scenes are already saved."):
            with self.subTest(name=name):
                self.assertIn(f'TTRC("{name}")', self.source)

    def test_critical_dialog_titles_no_longer_use_uncached_macro(self):
        for name in ("Save Resource As...", "Save Scene As...", "Export Mesh Library",
                     "Command Palette", "Load Errors"):
            with self.subTest(name=name):
                self.assertNotIn(f'TTR("{name}")', self.source)


if __name__ == "__main__":
    unittest.main()
