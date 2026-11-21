# Native primary streaming readiness

Cgame `WorldStreamer.get_focus_streaming_status(require_visual_details=false)`
reports the World Partition-style completion of the *main observer's* current
load radius, independently from any optional waypoint source.

One bounded, read-only native query returns:

- `total`: eligible player-area grid cells (hard cap 16,384)
- `completed`: loaded and optionally visually complete, or intentionally empty
- `pending`: not completed and not failed
- `failed`: failed to load/generate
- `progress`: completed / total, 0–1
- `ready`: all cells settled without failures or truncation
- `truncated`: cap reached; readiness always false in this case

This API does **not** request chunks, change streaming priority, alter navigation,
unlock travel, or decide authoritative combat outcomes. Progress is only a
client presentation signal.

Albion After checks it twice per second (not every render frame) and displays
an unobtrusive line while terrain is loading or when a chunk fails. The
`require_visual_details=true` parameter waits for staged foliage/props,
which `ChunkView` acknowledges via `mark_visual_details_ready`. On older engine
builds, no synthetic/incorrect percentage is displayed.

Inspired by Unreal Engine World Partition streaming completion and streaming
source APIs. Test with `game/tests/run_world_streaming_focus_status.gd`;
the dedicated GitHub workflow also runs a native C++ regression.
