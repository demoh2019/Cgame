# Cgame editor theme

Two new color presets, selectable under Editor Settings > Interface > Theme > Color Preset. They run through the existing "Modern" style pipeline (base color, accent color, contrast). All other presets remain available; "Cgame" is the default for new installs. Existing users keep their saved preset.

Design follows general dark-IDE conventions (neutral surface ladder, accent for selection). No third-party assets, icons, fonts or exact proprietary values are used; Godot's own icons and fonts are kept.

## Palette

| Preset | Base | Accent | Contrast | Extra borders | Icon saturation |
|---|---|---|---|---|---|
| Cgame | rgb(0.150, 0.153, 0.160) ~ #262729 | rgb(0.27, 0.56, 1.0) ~ #458FFF | 0.32 | no | 1.6 |
| Cgame High Contrast | rgb(0.085, 0.088, 0.095) ~ #161618 | rgb(0.42, 0.74, 1.0) ~ #6BBDFF | 0.50 | yes | 1.4 |

The surface ladder (popup, lowest ... highest, buttons, borders) is derived from the base color by the Modern theme builder, so hover/pressed/focus states stay consistent across all controls.

## Rationale (pain points from editor-ux-research.md section 6)

- Not too dark: base is lighter than a near-black UE panel, so derived text/surface pairs retain readable contrast. Intended: primary text at least 4.5:1 (WCAG AA) on panel surfaces; the High Contrast variant targets 7:1. Needs measurement on the built editor.
- Consistent states: hover, selected and focused states all come from the shared accent plus derived surface steps.
- Tabs: selected tab gets a 2 px accent top edge and about 24% more vertical padding (larger hit target).
- Splitters: separation raised from 0.75x to 1x base margin for Cgame presets.
- High Contrast: darker surfaces, stronger contrast factor, visible borders, brighter accent.
- Scaling: all additions use EDSCALE_RND, so they scale with the editor scale (laptop and 4K); density is still controlled by the spacing preset (Compact/Default/Spacious).

## Implementation

- `editor/themes/editor_theme_manager.cpp`: preset values; follow-system dark theme now maps to "Cgame".
- `editor/themes/theme_modern.cpp`: tab and splitter tweaks gated on preset names starting with "Cgame".
- `editor/settings/editor_settings.cpp`: preset enum list and default value.

## Needs visual verification

Contrast measurements, tab/splitter sizes at 100% and 200% scale, High Contrast borders, light-mode follow-system fallback, and that user-edited ("Custom") presets drop the tab/splitter tweaks.
