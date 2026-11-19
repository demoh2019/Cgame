"""Source contracts for cached C# localization symbols (upstream Godot #125113)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "editor/translations/editor_translation_parser.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "editor/translations/editor_translation_parser.h").read_text(encoding="utf-8")
TEMPLATE = (ROOT / "editor/translations/template_generator.cpp").read_text(encoding="utf-8")
CS = (ROOT / "modules/mono/editor/GodotTools/GodotTools/CsTranslationParserPlugin.cs").read_text(encoding="utf-8")
DOC = (ROOT / "doc/classes/EditorTranslationParserPlugin.xml").read_text(encoding="utf-8")


class CachedCSharpTranslationSymbols(unittest.TestCase):
    def test_hook_exposed_to_all_editor_translation_plugins(self):
        self.assertIn("GDVIRTUAL0(_begin_parse)", HEADER)
        self.assertIn("void begin_parse();", HEADER)
        self.assertIn("GDVIRTUAL_BIND(_begin_parse)", CPP)

    def test_hook_invoked_on_both_standard_and_custom_parsers(self):
        self.assertIn("for (const Ref<EditorTranslationParserPlugin> &parser : standard_parsers)", CPP)
        self.assertIn("for (const Ref<EditorTranslationParserPlugin> &parser : custom_parsers)", CPP)
        self.assertEqual(CPP.count("parser->begin_parse();"), 2)

    def test_translation_generation_invokes_hook_once_before_files(self):
        self.assertEqual(TEMPLATE.count("EditorTranslationParser::get_singleton()->begin_parse();"), 1)
        self.assertLess(TEMPLATE.index("EditorTranslationParser::get_singleton()->begin_parse();"),
                        TEMPLATE.index("for (const String &path : p_sources)"))

    def test_symbol_cache_is_per_plugin_instance(self):
        self.assertIn("private readonly List<string[]> _projectDefineConstants", CS)

    def test_each_generation_clears_symbol_cache(self):
        self.assertIn("public override void _BeginParse()", CS)
        self.assertIn("_projectDefineConstants.Clear();", CS)

    def test_msbuild_symbols_computed_only_for_first_file(self):
        self.assertIn("if (_projectDefineConstants.Count == 0)", CS)
        self.assertIn("GetProjectDefineConstants(GodotSharpDirs.ProjectCsProjPath", CS)
        start = CS.index("if (_projectDefineConstants.Count == 0)")
        end = CS.index("foreach (string[] symbols in _projectDefineConstants)", start)
        self.assertIn("_projectDefineConstants.Add(", CS[start:end])

    def test_each_file_uses_every_cached_symbol_set(self):
        self.assertIn("foreach (string[] symbols in _projectDefineConstants)", CS)
        self.assertIn("ParseCode(text, symbols, _projectReferences);", CS)

    def test_empty_symbol_output_is_not_split(self):
        self.assertIn("if (!string.IsNullOrEmpty(defineConstantsOutput))", CS)
        self.assertNotIn("if (string.IsNullOrEmpty(defineConstantsOutput))", CS)

    def test_api_documentation_mentions_begin_parse(self):
        self.assertIn('<method name="_begin_parse" qualifiers="virtual">', DOC)


if __name__ == "__main__":
    unittest.main()
