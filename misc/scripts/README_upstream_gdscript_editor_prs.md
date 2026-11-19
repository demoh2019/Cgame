# Selected upstream Godot editor fixes in Cgame develop

This change integrates three small editor PRs from [godotengine/godot](https://github.com/godotengine/godot/pulls) into Cgame's `develop`. **AI Game Builder** remains the product priority: these fixes support script navigation, correct diagnostic actions, and predictable editor state.

| Source PR | User-visible outcome | File |
| --- | --- | --- |
| [#125356](https://github.com/godotengine/godot/pull/125356) | GDScript "Lookup Symbol" on a node's script can navigate to the script in another file rather than only jumping to a line number | `modules/gdscript/gdscript_editor.cpp` |
| [#125132](https://github.com/godotengine/godot/pull/125132) | Clicking a GDScript warning doesn't append `@warning_ignore` inside a comment mistaken for an annotation | `editor/script/script_text_editor.cpp` |
| [#125125](https://github.com/godotengine/godot/pull/125125) | The Animation editor remembers its grouped-tracks toggle per project | `editor/animation/animation_track_editor.cpp` |

All three changes are intentionally small and applied to the existing engine source. No new AI service is invoked, no plugin API is changed, and no upstream PR is claimed merged into Cgame just because its patch is under review.

**Skipped:** upstream #125621 (GDScript translation parser uninitialization) was already integrated in `develop` while this review was underway. Previously integrated upstream fixes such as #125444, #125488, #125459 and #125563 were similarly left untouched.

## Verification

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_upstream_gdscript_editor_prs.py' -v
```

The Python suite checks source-level safety and state-persistence invariants. It **does not prove the engine builds** or that all GUI interactions work. The dedicated GitHub Actions workflow also builds the Cgame editor from **this fork's source** and opens/closes a minimal project to exercise native startup/shutdown.

Manual editor acceptance checks:

1. Attach a different GDScript to a scene node; use Lookup Symbol on a member accessed through a `get_node` expression, and verify that the editor navigates to the defining script file and line.
2. Place a GDScript comment containing the literal text `@warning_ignore` before a warning. Click that warning; verify the comment stays unchanged and a real annotation is inserted. Repeat with an existing real `@warning_ignore` annotation to verify the warning identifier is appended there.
3. Toggle grouping in the Animation editor; close and reopen the same project and verify the toggle state persists, while a new project starts with its default state.

Upstream PRs were open when selected on 2026-11-19. They can evolve. Follow their review and keep regression behavior when later synchronizing Godot master.
