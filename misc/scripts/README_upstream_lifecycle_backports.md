# Upstream engine lifecycle fixes (#125620, #125621)

Two upstream Godot 4.x fixes were selected for Cgame `develop` after checking that
other candidates were already present and avoiding overlapping editor/terrain
feature branches.

- [godotengine/godot#125621](https://github.com/godotengine/godot/pull/125621):
  Registering the GDScript editor translation parser at the **SERVERS** init
  level must be paired with unregistering it at **SERVERS** shutdown, not
  **EDITOR** shutdown. GDScript editor language and language-server teardown
  stay at their original EDITOR stage. This also handles editor builds that
  do not reach editor-module initialization.
- [godotengine/godot#125620](https://github.com/godotengine/godot/pull/125620):
  If all display drivers fail during `Main::setup2`, release display/rendering/
  accessibility resources via `finalize_display()` and release navigation
  managers before unloading server-level extensions and modules. Both
  navigation cleanup calls retain their compile-time feature guards.

The implementation follows those upstream diffs; no upstream public API or
copyrighted assets were copied beyond Godot's own compatible, open-source
engine fixes. The selected changes are not a claim that every upstream PR is
safe or appropriate for this fork.

## Verification

Run the fast source-level lifecycle regression contracts:

```sh
python3 -m unittest discover -s misc/scripts/tests \
  -p 'test_upstream_lifecycle_backports.py' -v
```

The accompanying GitHub Actions workflow runs those contracts on Python 3.9
and 3.13, compiles the Linux editor using the repository's own Godot build
action, and performs headless editor startup/shutdown and import smoke checks.
These source checks are **not** functional C++ tests; successful compiler,
linker, runtime, and platform matrix results are required before considering
the fixes fully validated. In particular, macOS and Windows initialization
failure paths still require targeted platform testing.

These fixes intentionally do not alter the API of AI Game Builder or terrain
modules and should be integrated independently of their experimental PRs.
