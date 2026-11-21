# Godot upstream: open issues and pull requests

Snapshot of every **open** issue (13426) and pull request (5661, 741 drafts) of
[godotengine/godot](https://github.com/godotengine/godot), fetched 2026-11-21 through the GitHub API.
Data: [`godot_open.json`](godot_open.json) (number, title, labels, milestone, author, comment count, dates; no bodies).
Nothing was created on GitHub. Look an item up at `https://github.com/godotengine/godot/issues/<number>`.

The code of every open pull request can be fetched into this repository on demand:

```bash
git fetch https://github.com/godotengine/godot.git refs/pull/<number>/head:refs/godot-pr/<number>
```

## Quick lists

- Open bugs: 9770; crash reports: 964.
- Non-draft pull requests on a 4.6-4.8 milestone (most likely to land upstream): 202.

## Issues by label (top 40)

| Label | Open issues |
|---|---|
| bug | 9770 |
| topic:editor | 4347 |
| needs testing | 2605 |
| topic:rendering | 2287 |
| confirmed | 2113 |
| discussion | 1905 |
| topic:3d | 1812 |
| topic:core | 1559 |
| topic:gui | 1322 |
| enhancement | 1140 |
| topic:2d | 1023 |
| topic:platforms | 989 |
| crash | 964 |
| documentation | 940 |
| topic:physics | 878 |
| usability | 837 |
| topic:gdscript | 818 |
| topic:input | 612 |
| topic:import | 541 |
| topic:animation | 534 |
| platform:windows | 517 |
| platform:linuxbsd | 501 |
| platform:android | 493 |
| topic:dotnet | 481 |
| regression | 432 |
| performance | 427 |
| platform:macos | 332 |
| topic:shaders | 308 |
| topic:export | 283 |
| platform:web | 261 |
| topic:thirdparty | 249 |
| topic:audio | 237 |
| topic:particles | 192 |
| topic:buildsystem | 163 |
| topic:gdextension | 159 |
| platform:ios | 157 |
| topic:plugin | 144 |
| topic:network | 136 |
| topic:xr | 117 |
| topic:multiplayer | 97 |

## Pull requests by label (top 40)

| Label | Open PRs |
|---|---|
| enhancement | 3633 |
| bug | 1842 |
| topic:editor | 1694 |
| topic:core | 960 |
| topic:3d | 738 |
| topic:rendering | 643 |
| topic:gui | 553 |
| usability | 465 |
| documentation | 335 |
| performance | 322 |
| topic:gdscript | 304 |
| topic:2d | 288 |
| topic:platforms | 288 |
| feature proposal | 250 |
| discussion | 230 |
| topic:physics | 219 |
| topic:buildsystem | 217 |
| topic:animation | 190 |
| topic:audio | 174 |
| topic:input | 159 |
| topic:import | 151 |
| platform:windows | 141 |
| topic:codestyle | 140 |
| needs work | 137 |
| platform:linuxbsd | 136 |
| needs testing | 133 |
| breaks compat | 132 |
| topic:dotnet | 130 |
| topic:shaders | 126 |
| platform:macos | 105 |
| topic:tests | 99 |
| crash | 97 |
| topic:export | 70 |
| topic:gdextension | 66 |
| topic:network | 59 |
| topic:particles | 58 |
| regression | 57 |
| platform:ios | 56 |
| platform:web | 53 |
| salvageable | 50 |

## Most discussed open crash reports

| # | Title | Comments |
|---|---|---|
| [75308](https://github.com/godotengine/godot/issues/75308) | [X11] Project or editor crashes randomly from xcb XInitThreads (Unknown sequence number wh | 77 |
| [26924](https://github.com/godotengine/godot/issues/26924) | Crash after splashscreen on Android with GLES2 if default_env.tres is present [Samsung Gal | 67 |
| [24702](https://github.com/godotengine/godot/issues/24702) | [3.x] Godot crashes on window resize on NVIDIA graphics cards (fixed in `master`) | 46 |
| [83762](https://github.com/godotengine/godot/issues/83762) | C# Game crashes randomly on changing scenes with USER ERROR: FATAL: Condition "gchandle.is | 44 |
| [24146](https://github.com/godotengine/godot/issues/24146) | export var PackedScene crash when having circular references | 34 |
| [115087](https://github.com/godotengine/godot/issues/115087) | Godot 4.6rc1 crashing frequently, sometimes freezing whole system (Windows 11, Vulkan, Nvi | 32 |
| [111028](https://github.com/godotengine/godot/issues/111028) | Edit Sun and Environment Settings button leads to engine crash due to Accesskit segfault. | 32 |
| [103249](https://github.com/godotengine/godot/issues/103249) | Linux version crashes with popups/dropdowns/tooltips | 29 |
| [93474](https://github.com/godotengine/godot/issues/93474) | 2D Physics Run on Seperate Thread Crash | 29 |
| [59505](https://github.com/godotengine/godot/issues/59505) | Godot 4.0 crashes when enabling use_xr on viewport | 29 |
| [107951](https://github.com/godotengine/godot/issues/107951) | Crash when using Jolt Physics and repeatedly adding and removing bodies while performing p | 27 |
| [106801](https://github.com/godotengine/godot/issues/106801) | Import/reimport gltf files causes kernel panic with `forward_plus` or `mobile` on macOS M2 | 27 |
| [76568](https://github.com/godotengine/godot/issues/76568) | Vulkan Mobile: Crash on Samsung Galaxy Tab S2 (SM-T813) | 25 |
| [95525](https://github.com/godotengine/godot/issues/95525) | Godot crashes after `Index p_index = 0 is out of bounds (size() = 0)` error. | 23 |
| [70050](https://github.com/godotengine/godot/issues/70050) | OpenXR game crashes when run | 23 |
| [48295](https://github.com/godotengine/godot/issues/48295) | Crash during engine shutdown if `get_tree()` is ever called from GDNative | 23 |
| [74850](https://github.com/godotengine/godot/issues/74850) | Godot window crashes and becomes unresponsive [Linux Gnome] | 22 |
| [48701](https://github.com/godotengine/godot/issues/48701) | App works on Xcode release mode, crashes on Testflight. | 22 |
| [34752](https://github.com/godotengine/godot/issues/34752) | Crash when connecting or disconnecting a signal from multiple threads | 22 |
| [119457](https://github.com/godotengine/godot/issues/119457) | Godot crashes when opening a project using Forward+ renderer | 21 |
| [116414](https://github.com/godotengine/godot/issues/116414) | System hard freeze when opening a project with Vulkan as renderer (Windows, Nvidia driver  | 21 |
| [106318](https://github.com/godotengine/godot/issues/106318) | Occlussion Culling under Wayland on 4.4.1 crashes Godot | 21 |
| [93587](https://github.com/godotengine/godot/issues/93587) | Import a large glb file (778MB) which contains 800 models will crash the editor. | 21 |
| [88502](https://github.com/godotengine/godot/issues/88502) | Vulkan API using incorrect Vulkan Device, using Intel Graphics instead of NVIDIA GPU | 21 |
| [86691](https://github.com/godotengine/godot/issues/86691) | Crash with adding/removing AnimationLibraries and trying to play an animation | 21 |
| [32470](https://github.com/godotengine/godot/issues/32470) | Multi-threading related crash during play in Label::regenerate_word_cache | 21 |
| [22589](https://github.com/godotengine/godot/issues/22589) | When removing a TileMap node (or its parent), remove_child method sometimes causes a crash | 21 |
| [58139](https://github.com/godotengine/godot/issues/58139) | Crashes on android devices | 20 |
| [117817](https://github.com/godotengine/godot/issues/117817) | Crash due to audio loop offset being larger than the length calculated from the beat count | 19 |
| [91373](https://github.com/godotengine/godot/issues/91373) | Error with the Vulkan-renderers Forward+ and Mobile: game window shows black and closes wi | 19 |
