# Backport upstream #115981: CanvasLayer / Window workspace routing

This backport carries the editor behavior fix from
[godotengine/godot#115981](https://github.com/godotengine/godot/pull/115981)
into Cgame. The CanvasItemEditorPlugin::handles method now accepts CanvasItem,
CanvasLayer, and Window selections (instead of just CanvasItem). Selecting a
CanvasLayer should therefore activate the 2D workspace automatically.

The change intentionally leaves CanvasItemEditorPlugin::edit untouched; it
continues to receive a CanvasItem pointer (or null for CanvasLayer/Window)
as in the upstream implementation.

The integration also adds source-level regression contracts for the existing
Shift-click selection fix upstream #125500 (already in Cgame develop), so
the new CanvasLayer behavior cannot silently revert that adjacent code.

## Tests

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_upstream_canvas_workspace.py' -v
```

16 lightweight source-level tests run under Python 3.10 and 3.13 on Linux,
Windows and macOS in CI. They verify supported node types, boolean routing,
existing edit behavior, and Shift-selection invariants. These tests do NOT
compile the engine or simulate real editor input. Native editor startup and
manual 2D workspace smoke testing are still needed.

Source PR was open when evaluated; this is a targeted backport, not a
claim that upstream changes are merged or universally stable.
