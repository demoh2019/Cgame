# Albion After: Settings menu

Open the same Settings window from the connection/title screen Settings
button, or Esc / gamepad Menu while playing. Multiplayer continues
running behind the window; opening Settings does not pause the server.

## Five settings categories

Gameplay: language (Russian/English), sprint/crouch toggle, FPS overlay,
first-person FOV, sensitivity, inverted vertical mouse and head bob.

Graphics: Performance, Balanced, High, Ultra, or Auto (GPU-aware 3D +
details). The quality picker on the title screen, the in-game Settings
window and the Ctrl+F11 shortcut all call the same online_main graphics
application pathway. Renderer settings, native render resolution,
adaptive resolution, and streamer detail budgets update immediately.

Graphics also has windowed/fullscreen mode, V-Sync Off/On and FPS cap
(Unlimited, 30, 60, 120, 144 or 240). These controls use Window.mode,
DisplayServer.window_set_vsync_mode and Engine.max_fps at runtime and
persist in the existing graphics preferences file under [display].
Headless testing skips window changes but verifies config and FPS cap.

Audio: five existing AudioMix buses (Master, Music, SFX, UI, Ambience),
0% to 100% in 5% increments, applied live. The reset button restores
100% on all five channels. The mixer saves on slider release, focus
loss, explicit reset, or closing Settings, not every frame while
dragging. Older Cgame and stock Godot use the existing standard buses.

Controls: remap keys, gamepad prompts, restore default bindings.

Accessibility: colorblind filters, interface scale, reduced shake and
flashes, high contrast and scalable closed captions.

Each sound slider now displays its exact percentage beside the control.
The Graphics tab has **Reset display settings**, which restores
Windowed mode, V-Sync On and Unlimited FPS while preserving quality,
interface preferences and key bindings. The menu refreshes selectors
when reopened, and its tab bar accepts keyboard and gamepad focus.

The content of every tab scrolls on small windows or when UI scale is
increased for legibility.

## Saving

Graphics quality and Auto mode stay in the rendering section of the
existing user://albion_after_graphics.cfg. Other UI settings and key
bindings retain their existing config sections. Volume uses the existing
user://albion_after_audio.cfg file, with validated finite 0..1 bus gain
and no duplicate settings storage.

This patch affects client presentation only; no server-owned movement,
combat, AI, networking, saves or authority were changed.

## Validation

Headless UI coverage: game/tests/test_ui_parity.gd including actual
menu controls, volume persistence and reset, graphics selection events
and title-screen integration. Focused:
godot --headless --path game --script res://tests/run_one.gd -- test_ui_parity test_audio_parity test_graphics_quality

Complete headless suite:
godot --headless --path game --script res://tests/run_all.gd
