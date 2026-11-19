"""Named, deterministic impairment baselines for Godot UDP multiplayer testing.

These are *synthetic test scenarios*, not claims about the speed of a real ISP.
All latency values describe one-way delay applied to each proxied datagram.
"""

from __future__ import annotations

import math
from typing import Mapping

# Exposed as names rather than modifying the transport's implementation.
# Keep names stable for CI and developer scripts that use --preset.
PRESETS: dict[str, dict[str, float]] = {
    "clean": dict(latency_ms=0.0, jitter_ms=0.0, loss_percent=0.0, duplicate_percent=0.0),
    "fiber": dict(latency_ms=10.0, jitter_ms=2.0, loss_percent=0.0, duplicate_percent=0.0),
    "wifi": dict(latency_ms=32.0, jitter_ms=12.0, loss_percent=2.0, duplicate_percent=0.0),
    "mobile": dict(latency_ms=100.0, jitter_ms=40.0, loss_percent=4.0, duplicate_percent=0.5),
    "satellite": dict(latency_ms=300.0, jitter_ms=50.0, loss_percent=1.0, duplicate_percent=0.0),
    "severe": dict(latency_ms=250.0, jitter_ms=100.0, loss_percent=12.0, duplicate_percent=2.0),
}

# Stable, public CLI option -> transport Impairment field.
FIELDS = ("latency_ms", "jitter_ms", "loss_percent", "duplicate_percent")


def resolve_preset(name: str, overrides: Mapping[str, float | None] | None = None) -> dict[str, float]:
    """Return an independent validated policy for one direction.

    None means retain a preset value; an explicit 0 disables it.
    Reject unknown fields instead of silently ignoring configuration errors.
    """
    try:
        values = dict(PRESETS[name])
    except (KeyError, TypeError) as exc:
        raise ValueError(f"Unknown network profile: {name!r}") from exc

    if overrides is not None:
        unknown = set(overrides) - set(FIELDS)
        if unknown:
            raise ValueError(f"Unknown network parameter(s): {', '.join(sorted(unknown))}")
        for key, value in overrides.items():
            if value is not None:
                values[key] = value

    for key in FIELDS:
        value = values[key]
        upper = 120000 if key.endswith("_ms") else 100
        if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or not 0 <= value <= upper:
            raise ValueError(f"{key} must be finite and between 0 and {upper}")
        values[key] = float(value)
    return values
