# PCG Graph Editor

Editor-only (`TOOLS_ENABLED`) tooling for `modules/pcg_graph`, in `editor/`.
Registered from `register_types.cpp` via `EditorPlugins::add_by_type<PCGGraphEditorPlugin>()`.

## Opening

* Select a `PCGComponent3D` in the scene tree, or open a `PCGGraph` resource in the Inspector / FileSystem.
  The **PCG Graph** bottom-panel tab appears.
* A component without a graph shows a **New Graph** button (undoable).

## Features (Unreal PCG equivalents)

| Feature | Unreal equivalent |
| --- | --- |
| GraphEdit panel, one GraphNode per `PCGNode`, header color by category, one input port per `get_input_count()`, one output port | PCG Graph Editor |
| **Add Node** button / right click menu: every `PCGNode` subclass from ClassDB plus global script classes extending `PCGNode`, grouped by `get_category()` | Node palette / context menu |
| Connect, disconnect (drag from the input), delete (Del), duplicate (Ctrl+D), move; all undo/redo via `EditorUndoRedoManager`; cyclic links raise an error toast | Graph editing |
| Click a node: the `PCGNode` resource shows in the Inspector | Details panel |
| **Live Preview**: any graph/node change regenerates the edited `PCGComponent3D` after 0.25 s (3D viewport updates). A bare `PCGGraph` runs `PCGGraphExecutor` on a 64x64 preview context without samplers | Editor PCG preview / generate on change |
| **Debug**: runs with `context.debug = true`; nodes show an output point count badge; selecting a node draws its output points (density-colored crosses, splines as lines) in the 3D viewport via an internal `MeshInstance3D` under the component | PCG Debug / Inspection |
| **Profile** side panel (`PCGGraphExecutor.format_profile`), per-node microseconds on each node, cache hits/misses in the header line, **Clear Cache** | PCG Profiler |
| Status line: `PCGGraph.validate()` messages and output point count | Graph warnings |
| Inspector bar on `PCGComponent3D`: **Generate** / **Clear** | Generate / Cleanup buttons |

## Files

* `editor/pcg_graph_editor_plugin.h/.cpp` - plugin, bottom panel, inspector plugin.
* `editor/pcg_editor_logic.h` - UI-free helpers (category sort/grouping, colors, formatting).
* `tests/test_pcg_editor_logic.h` - unit tests for those helpers (`--test-case="*PCGEditor*"`).

## Notes / limits

* Dragging a connection onto empty space does not open the palette yet.
* Each node has one output port; multi-output nodes are not part of the runtime model.
* The debug mesh is an internal child of the component (never saved) and is removed when the panel hides.
