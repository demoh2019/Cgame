# Upstream Godot backports: AI asset preference and export logging

This incremental Cgame `develop` backport adapts two **open** PRs from upstream Godot (status checked on 2026-11-19). The changes support AI Game Builder content discovery and keep normal game-export output focused on actionable warnings.

| Upstream | Backported behavior | Files |
| --- | --- | --- |
| [godotengine/godot#125409](https://github.com/godotengine/godot/pull/125409) | Add an optional **Uses AI** filter to the built-in Asset Library. Options: **No Preference** (default, leaves query unchanged), **Uses AI** (sends `uses_ai=True`), **No AI** (`uses_ai=False`). Changing selection triggers a new search. | `editor/asset_library/asset_library_editor_plugin.{cpp,h}` |
| [godotengine/godot#125447](https://github.com/godotengine/godot/pull/125447) | Log Windows/Linux PC and macOS export executable/symbol build IDs only at verbose level, while **retaining build-ID mismatch warnings** in the normal export output. | `editor/export/editor_export_platform_pc.cpp`, `platform/macos/export/export_plugin.cpp` |

The Asset Library `uses_ai` flag only requests the upstream Asset Store filtering API; its behavior depends on the selected repository implementing/supporting that query. This is **not** an asset provenance guarantee, a model classifier, or a replacement for checking asset licenses and sources. It performs no AI generation and requires no AI API key.

The export change only affects debug-ID logging verbosity, not export decisions or the existing mismatch warning. Use the engine's verbose logging mode to inspect these IDs when diagnosing symbol packages.

## Regression coverage

```sh
python3 -m unittest discover -s misc/scripts/tests \
  -p test_upstream_asset_ai_export_logging.py -v
```

32 Python *source-contract* tests verify all three filter choices, metadata/query coupling, search wiring, the default unfiltered case, and preservation of export mismatch warnings on both export paths. The CI workflow also builds the **actual Cgame editor** and runs a minimal-project import smoke check.

These tests **do not** establish that the Godot GUI, remote Asset Store endpoint, Windows/macOS exporters or full AI Game Builder flow work in all environments. Manual acceptance tests are still required:

1. In **Asset Library**, select each of the three AI preference choices; observe the resulting request and verify the selected repository supports `uses_ai`. Switch back to No Preference and verify the query contains no `uses_ai` parameter.
2. Change AI preference while searching or filtering categories: ensure the new search retains text, sort and compatibility constraints.
3. Run PC and macOS exports with symbols; verify normal logs omit raw build IDs while an intentional ID mismatch still raises a warning. Turn on verbose logging and check that IDs become visible.

### Existing Cgame code not duplicated

The `develop` branch already contains upstream [#125134](https://github.com/godotengine/godot/pull/125134) (restore Game dock focus on resume) and [#125575](https://github.com/godotengine/godot/pull/125575) (Undo/Redo for instance placeholder). These were reviewed but not re-applied.

Upstream PRs may change before merge. Treat this as a controlled backport, not a blanket cherry-pick of all unreviewed patches.
