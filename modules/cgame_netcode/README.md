# Cgame netcode (native)

Native, engine-level netcode primitives ported from the GDScript reference in `game/scripts/shared/`
(`net_schema.gd`, `net_quantization.gd`, `snapshot_delta.gd`, `replication_graph.gd`). All classes are `RefCounted`.

| Class | Purpose |
| --- | --- |
| `CgameBitWriter` / `CgameBitReader` | LSB-first bit packing, varints (LEB128 + zigzag), quantized float / angle / Vector3, smallest-three quaternion, strings, raw float32 |
| `CgameNetSchema` | Field schema from a Dictionary, changed-field mask, `always` / `on_change` / `initial_only` / `owner_only` conditions, schema hash, versioned packets |
| `CgameReplicationGraph` | Grid relevancy, always-relevant / owner-only, dormancy + wake, class priority and frequency, bandwidth budget with starvation |
| `CgameSnapshotDelta` | Static `diff` / `apply` / `is_empty` over `{id: {field: value}}` snapshots |

## Compatibility with the GDScript implementation

- `CgameNetSchema` wire format is byte-compatible with `net_schema.gd`: one mask bit per field, then present fields
  in schema order, LSB-first, same quantization (round-half-away), same string layout (8-bit length + UTF-8, max 255).
- `get_schema_hash()` equals `schema_hash()` (djb2-style `String.hash()` over the same descriptor text).
  Versioned packets use a little-endian u32 hash prefix.
- `CgameBitWriter.write_bits` / `CgameBitReader.read_bits` use the same bit order as the GDScript `BitWriter`/`BitReader`.
- `CgameReplicationGraph.gather_for` has the same selection, scoring (`priority * proximity * (1 + starvation)`,
  `+1000` on wake) and ordering (priority desc, id asc) as `replication_graph.gd`.
- `CgameSnapshotDelta` produces the same delta layout (`changed` / `added` / `removed` / `dropped`).

### Intentional differences

- `set_schema` validates input: unknown field `type` or `condition` is rejected (returns `false`) instead of
  being tolerated at serialize time. Missing `bits` / `min` / `max` default to 0, `condition` to `on_change`.
- The reader reports truncation through `is_overflowed()`; the GDScript reader silently returned partial values.
- `remove_entity` also drops per-connection send history for that id (GDScript left stale entries).
- `set_cell_size` rebuilds the grid; it must be greater than zero.
- Large view radii walk occupied cells instead of the whole cell range, so results are identical but cost is bounded.
- Extras not in GDScript: `write/read_varint`, `signed_varint`, `write/read_quaternion` (smallest-three, 2 + 3*bits),
  `write/read_float32`, `CgameSnapshotDelta.is_empty`, `CgameReplicationGraph.clear/get_position/is_dormant`.

## Usage

See the class reference in `doc_classes/` and the GDScript facade `game_facade/cgame_netcode_facade.gd`,
which uses these classes when present and otherwise falls back to the GDScript scripts.

## Tests

`tests/test_cgame_netcode.h` (doctest): bit and varint round trips, quantization error bounds, schema round trip and
changed-only size, replication relevance / dormancy / budget / starvation, snapshot delta round trip.
Run with `--test --test-case="*CgameNetcode*"` after a build with `tests=yes`.
