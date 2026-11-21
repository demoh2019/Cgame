# Cgame Editor UX (UE-style layout)

The Cgame editor ships an Unreal-Engine-5-style layout and workflow on top of the Godot docking system.
It uses Godot icons and theme only; no Epic assets, icons or fonts are used. Visual theming (colors,
spacing, fonts) is handled separately in `editor/themes/`.

Status: implemented but not yet verified in a built editor (see "Verification checklist").

## Default layout

| Area | Content |
|---|---|
| Right column, top | Scene tree (Outliner), Import dock as a second tab |
| Right column, bottom | Inspector (Details); tabs: Node (Signals), Groups, History (undo history) |
| Center | Viewport / main screens (2D, 3D, Script, Game, AssetLib) |
| Bottom panel | Output, Debugger, Animation, Shader, ... (unchanged Godot bottom panel) |
| Content Drawer | FileSystem dock, slides up over the editor with `Ctrl+Space` |
| Main toolbar row | Save, Add menu (left); Play / Play Scene / Pause / Stop (center); Platforms, Quick Settings (right) |
| Status bar | Content Drawer, Output Log, Undo History buttons; background task progress; source-control branch |

Only the **defaults** changed. A project that already has a saved layout (`editor_layout.cfg`) keeps it.
New projects start with the Cgame layout.

Editor > Editor Layout menu:

- **Default**: the Cgame layout (or your overridden "Default" if you saved one).
- **Cgame (UE-style)**: apply the Cgame layout.
- **Godot Classic**: the upstream Godot layout (Scene + Import left, FileSystem + History bottom-left, Inspector right).
- **Reset to Cgame Layout**: re-apply the Cgame layout including split sizes (also in Quick Settings and the command palette).

Implementation: dock default slots (`set_default_slot`) in the dock constructors, and the layout configs
built in `EditorNode::_build_default_layouts()` (`editor/editor_node.cpp`).

## Content Drawer

`editor/gui/content_drawer.{h,cpp}`. A transient overlay that hosts the FileSystem dock.

- `Ctrl+Space` toggles it (macOS: `Cmd+Shift+Space`, because `Cmd+Space` is Spotlight). Command palette: "Toggle Content Drawer".
- Slides up with a short animation (setting `interface/cgame_ux/content_drawer_animation`); height is `interface/cgame_ux/content_drawer_height` (fraction of the window).
- The search field is focused on open. `Esc` or a click outside closes it. Starting a drag (for example an asset onto the viewport or Scene tree) lets the drop reach the target and closes the drawer when the drag ends.
- **Dock in Layout** (pin button) moves the FileSystem dock into the bottom-left dock slot, where it behaves like a normal dock. Command palette: "Content Drawer: Remove from Layout" returns it to the drawer.
- While the FileSystem dock is not pinned, "show in FileSystem" style requests open the drawer instead of docking it.
- If the dock is pinned, `Ctrl+Space` just focuses it.

The dock manager got three small APIs for this: `host_dock`, `unhost_dock`, `pin_dock` (plus `set_focus_override`).

## Main toolbar

`editor/gui/editor_ue_toolbar.{h,cpp}`, a row below the title bar. It forwards to existing actions and mirrors the run bar
state, so the original run bar in the title bar keeps working.

- Save: current scene. Add: Node... and Instantiate Scene...
- Play (main scene), Play Current Scene, Pause, Stop.
- Platforms: Export..., Manage Export Templates...
- Quick Settings: 3D snapping, 3D grid, Game View, visible collision shapes / paths / navigation (the Debug menu items), save before running, update continuously, Editor Settings, Project Settings, Reset layout.

Hide with `interface/cgame_ux/show_main_toolbar` (restart).

## Status bar

`editor/gui/editor_status_bar.{h,cpp}`: Content Drawer / Output Log / Undo History buttons, background task progress
(`EditorNode::progress_add_task_bg` etc. are forwarded to it) and the source-control branch (from the VCS plugin when
active, otherwise read from `.git/HEAD`, polled every 5 seconds). Hide with `interface/cgame_ux/show_status_bar` (restart).

## Shortcuts

Godot defaults are unchanged unless the preset is on. Setting: `interface/cgame_ux/shortcut_preset` = `Godot` (default) or
`Unreal-style` (restart required). The preset only changes shortcuts you have not customized.

| Action | Godot default | Unreal-style preset |
|---|---|---|
| Select tool | V | Q |
| Transform tool (Godot's combined gizmo) | Q | Shift+Q |
| Move / Rotate / Scale | W / E / R | W / E / R (same) |
| Focus selection | F | F (same) |
| Game View (hide grid and origin) | none | G |
| Immersive viewport (hide docks) | Ctrl+Shift+F11 | F11 |
| Content Drawer | Ctrl+Space (Cmd+Shift+Space on macOS) | same |
| Play | F5 | F5 and Alt+P |
| Browse to asset in Content Drawer | none | Ctrl+B (Control key on all platforms) |
| Snap selection to floor | PageDown | End |
| Save All / Save As | Ctrl+Shift+Alt+S / Ctrl+Shift+S | Ctrl+Shift+S / Ctrl+Shift+Alt+S |
| 2D pan mode | G | H (G is Game View) |

Game View is a new item in the 3D View menu (`spatial_editor/game_view`), unbound by default.
"Browse to Asset" (`editor/browse_to_asset`) opens the Content Drawer on the Inspector's resource or the edited scene file.
Implementation: `editor/settings/editor_cgame_ux.{h,cpp}`.

## Beyond Unreal

| Pain point in UE | Cgame |
|---|---|
| No command palette; scattered search | The command palette (`Ctrl+Shift+P`) also searches nodes of the edited scene, project files and editor/project settings. Prefix with `cmd:`, `node:`, `file:` or `setting:` to narrow. Dynamic results need at least 2 characters and are capped. |
| Undo history hidden | The History dock is a visible tab next to the Inspector by default and in the status bar. |
| Details rebuild stalls on large selections | Selecting 32+ nodes coalesces the Inspector rebuild into the next frame (`EditorInspector::edit`). |
| No background-task visibility | Status bar shows background task progress and the VCS branch. |
| Fragile layouts | Named layouts plus one-click "Reset to Cgame Layout". |

## What differs from Unreal

- The Content Drawer hosts Godot's FileSystem dock, not a thumbnail-based Content Browser; there are no asset filter chips or collections yet.
- No Modes panel (Landscape / Foliage / Modeling); main screens (2D, 3D, Script, Game) take that role.
- The viewport toolbar is Godot's; it was not regrouped into UE's five sections and has no overflow menu yet.
- Outliner columns (visibility, type) and multiple Outliner instances are not implemented.
- The Scene tree is a normal dock and does not auto-hide; the Content Drawer closes on Esc, outside click or drag end, not on every focus loss.
- Platforms is a small menu around Export; it does not list per-platform cook/deploy targets.

## Settings

All under Editor Settings > Interface > Cgame UX (`interface/cgame_ux/*`): `shortcut_preset`, `show_main_toolbar`,
`show_status_bar`, `content_drawer_height`, `content_drawer_animation`.

## Verification checklist (needs a built editor)

1. Fresh project: Scene tree top-right, Inspector below with Node/Groups/History tabs, no FileSystem dock; `Ctrl+Space` slides the drawer up and focuses the filter.
2. Esc, outside click and the close button close the drawer; "Dock in Layout" docks FileSystem bottom-left; Remove from Layout returns it to the drawer.
3. Drag a file from the drawer onto the viewport or Scene tree: drop works, drawer closes afterwards.
4. Existing project with a saved layout opens unchanged; Editor Layout menu has the new entries and Reset works.
5. Toolbar Play / Pause / Stop mirror the title bar run bar; Quick Settings toggles reflect and change state.
6. Command palette: `node:`, `file:`, `setting:` results; project/editor settings entries open the right dialog (the filter text for project settings may need a check).
7. With the Unreal-style preset: Q/Shift+Q, G, F11, Alt+P, End, Ctrl+B; with the preset off nothing changed.
8. Status bar shows the branch and background tasks; hiding settings work after restart.
9. Selecting 40+ nodes: Inspector updates once, no stall.
