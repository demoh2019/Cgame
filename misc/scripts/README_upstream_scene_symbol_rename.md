# Godot upstream #125479: scene-aware exported-property rename

This Cgame `develop` backport adapts [godotengine/godot#125479](https://github.com/godotengine/godot/pull/125479) (open at time of review, 2026-11-19).

## Why

The **Rename Symbol** search in the editor previously searched only script source extensions, even when an exported GDScript property was serialized in `.tscn` scene files. AI Game Builder and developers refactoring generated games can rename a script member while leaving scene overrides behind.

## Change

- For `EditorLanguage::LookupResult::Type::CLASS_PROPERTY`, obtain the script property metadata and additionally search `tscn` when the matching property's usage includes `PROPERTY_USAGE_STORAGE`.
- Retain the current script-language extension, case-sensitive and whole-word symbol matching.
- During scene-file **rename** results, accept only a match at column zero, reducing accidental matches inside values or strings. Ordinary text searches are unaffected.
- Keep language-aware symbol validation for script matches.
- **Scene matches are not pre-checked for replacement**. Users must review/select scene entries before applying replacements; script matches retain the previous matching-definition logic.

The patch was applied to Cgame's existing `editor/script/find_in_files.cpp` without overwriting its earlier Find in Files rename-mode and file-filter fixes. The result differs from the upstream head because Cgame already carries other related patches.

### Safety limitations

Scene matches are based on text, not a full `.tscn` semantic parser. A property identifier used by several unrelated scripts in different scenes may yield extra results. **Review individual .tscn matches, inspect the replacement preview, and commit/backup projects before performing bulk changes.** Do not use the toolbar's file-wide Replace All blindly on mixed scenes. This feature does not independently validate the owning script of each `.tscn` property.

## Tests

```bash
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_scene_symbol_rename.py -v
```

The 35 Python regression contracts check editor-source behavior, search scope, exported-property gating, scene match filtering, unchecked scene hits, script language-aware checks, and preservation of existing Find in Files fixes.

A separate GitHub Actions job compiles the **actual Cgame editor** and imports a minimal Godot project; that is a build/smoke check, **not** a GUI rename end-to-end test.

### Manual acceptance

1. In a test project, create `player.gd` with `@export var movement_speed: float = 100.0` and set an overridden value on a scene instance.
2. Invoke Rename Symbol on `movement_speed`, change it to `walk_speed` and verify results include `.gd` and corresponding `.tscn` entries.
3. Verify scene hits are not checked by default. Select only the matching property overrides and apply the change. Reopen the scene and confirm exported values are preserved.
4. Confirm function/constant renames do not include `.tscn` files, and ordinary text search still finds non-column-zero text.
5. Confirm unrelated `.tscn` property keys with the same name can be excluded manually.
6. Test malformed/missing scripts and editor undo/redo, and verify that prior Find in Files filters and rename-mode search constraints still work.

Cgame issue #73 (AI Game Builder) remains the product priority.
