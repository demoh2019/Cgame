"""Resource::set_path and String::is_quoted performance and cache semantics checks."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class FastCoreTests(unittest.TestCase):
    def test_resource_path_avoids_refcounting_on_cache_lookup(self):
        code = (ROOT / "core/io/resource.cpp").read_text()
        method = code.split("void Resource::set_path(const String &p_path, bool p_take_over) {", 1)[1].split("\nString Resource::get_path()", 1)[0]
        self.assertIn("ResourceCache::resources.getptr(p_path)", method)
        self.assertIn("if (!p_path.is_empty())", method)
        self.assertIn("ResourceCache::resources[path_cache] = this;", method)
        self.assertIn("(*existing)->path_cache = String();", method)
        self.assertNotIn("ResourceCache::get_ref(p_path)", method)

    def test_inline_quoted_uses_characters_not_string_temporaries(self):
        header = (ROOT / "core/string/ustring.h").read_text()
        code = (ROOT / "core/string/ustring.cpp").read_text()
        self.assertIn("is_enclosed_in(char32_t p_left, char32_t p_right)", header)
        self.assertIn("return is_enclosed_in('\"', '\"') || is_enclosed_in(", header)
        self.assertIn("bool is_enclosed_in(const String &p_string) const;", header)
        self.assertNotIn("bool String::is_quoted() const", code)

if __name__ == "__main__":
    unittest.main()
