# guild_bank.gd

> Albion-style guild bank: a shared hub vault per verified guild.

`res://scripts/shared/guild_bank.gd`

## Overview

Albion-style guild bank: a shared hub vault per verified guild. Any member can
deposit; only the leader and officers (Nakama rank 0-1) can withdraw. A short
ledger shows who moved what. Guild identity comes only from the server-side
Nakama check (GuildIdentity), never from a client command.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const MAX_KINDS := 96`
- `const MAX_COUNT := 1000000`
- `const LEDGER_SIZE := 20`
- `const OFFICER_MAX_RANK := 1`

## Functions

### `can_withdraw`

```gdscript
static func can_withdraw(rank: int) -> bool
```

### `deposit_refusal`

```gdscript
static func deposit_refusal(vault: Dictionary, item_id: String, count: int) -> String
```

Why a deposit of `count` x `item_id` into `vault` is refused ("" when allowed).

### `add_ledger`

```gdscript
static func add_ledger(ledger: Array, who: String, action: String, item_id: String, count: int, at: float) -> void
```

