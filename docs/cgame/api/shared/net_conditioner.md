# net_conditioner.gd

> Network condition simulator: latency, jitter, loss, duplication, reordering and a bandwidth cap (single FIFO link with a bounded queue), with a per-packet lo...

`res://scripts/shared/net_conditioner.gd`

## Overview

Network condition simulator: latency, jitter, loss, duplication, reordering and a
bandwidth cap (single FIFO link with a bounded queue), with a per-packet log and timeline.

Concepts (not code) from Linux netem (delay/jitter/loss/duplicate/reorder) and the
clumsy / Unity Network Simulator tools. Original GDScript; no third-party code copied, so no
license obligations.

Time unit: `now` and all *_at stamps are in SECONDS (float); latency/jitter are in ms.
Deterministic: the same seed + same send sequence always yields the same log.

Packet model: loss roll -> bandwidth queue (serialization delay, drop when the backlog
exceeds max_queue_ms) -> delay = latency + uniform jitter in [-jitter, +jitter] (>= 0)
-> optional reorder extra delay -> optional duplicate copy.

## Functions

### `configure`

```gdscript
func configure(cfg: Dictionary) -> void
```

### `send`

```gdscript
func send(channel: Variant, bytes: PackedByteArray, now: float) -> int
```

Submits a packet at time `now` (seconds). Returns its packet id.

### `receive`

```gdscript
func receive(now: float) -> Array
```

Returns packets due by `now`, ordered by delivery time: {channel, bytes, sent_at, delivered_at, id}.

### `packet_count`

```gdscript
func packet_count() -> int
```

### `packet`

```gdscript
func packet(id: int) -> Dictionary
```

### `pending_count`

```gdscript
func pending_count() -> int
```

### `timeline`

```gdscript
func timeline(t0: float, t1: float) -> Array
```

Log entries whose send or delivery time falls in [t0, t1], ordered by send time.

### `stats`

```gdscript
func stats() -> Dictionary
```

### `delay_cause`

```gdscript
func delay_cause(packet_id: int) -> String
```

Human-readable breakdown of why a packet took the time it did (or why it was dropped).

