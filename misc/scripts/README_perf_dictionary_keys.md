# Dictionary key-validation fast paths

Cgame's `Dictionary` already avoids key conversion in several lookup methods.
This extends the same optimization to the remaining common operations:

- `const operator[]` and non-const `getptr`: use the existing `Variant` key
  directly when the dictionary key type is untyped (`Variant::NIL`)
- `get_or_add`: check the existing map directly before attempting typed key
  validation; validate typed values on insertion
- `set` and `erase`: skip key validation on untyped dictionaries; still
  enforce `read_only` and typed-value constraints

Skipping the unnecessary validation reduces hot-path control flow and avoids
temporary `Variant` handling. It preserves hashing, the `String` / `StringName`
comparison behavior, typed keys, typed values, and read-only semantics.

This is a tailored continuation of upstream
[godotengine/godot#121081](https://github.com/godotengine/godot/pull/121081).
No API changes are required.

## Tests

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_dictionary_key_fastpath.py -v
```

Additionally build the Cgame editor with `tests=yes` and run the native
`[DictionaryFastPath]` tests. Regression tests cover heterogeneous keys,
`String`/`StringName` equivalence, insertion, deletion, `get_or_add`, pointer
lifetime, typed-key conversion, and read-only isolation.

**Performance verification:** compare native benchmark numbers under a release
build before and after with a representative mix of dictionary sizes and keys.
Source contracts do not establish a measured FPS or RAM gain. Faster
untyped-key access matters most where these operations are repeated frequently
in GDScript and engine code.
