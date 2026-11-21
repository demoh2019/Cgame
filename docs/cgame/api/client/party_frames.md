# party_frames.gd

> Compact party health frames for the networked HUD.

`res://scripts/client/party_frames.gd`

## Overview

Compact party health frames for the networked HUD.
Pure presentation of authoritative snapshot data; no guessed or client-
writable health, roster membership, roles or combat rewards.

## Constants

- `const MAX_VISIBLE_MEMBERS := 5`
- `const MAX_NAME_CHARS := 20`

## Functions

### `describe`

```gdscript
static func describe(raw: Variant, local_peer: int) -> String
```

