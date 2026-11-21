# transaction_coordinator.gd

> Two-phase-commit coordinator with a durable decision log, plus a persistent order book.

`res://scripts/server/transaction_coordinator.gd`

## Overview

```text
Two-phase-commit coordinator with a durable decision log, plus a persistent order book.

Original GDScript implementation. Design references (concepts only, no code copied):
  - Gray & Lamport, "Consensus on Transaction Commit" / classic 2PC with presumed abort
    (Mohan, Lindsay, Obermarck, "Transaction Management in the R* Distributed DBMS").
  - Atomic write via temp file + rename (the standard POSIX durable-update idiom).
License of this file: same as the project; no third-party code included.

Protocol: begin() logs the intent and ops. run() asks every participant to prepare; if all
say yes the COMMIT decision is logged durably, otherwise ABORT. The decision is then delivered
to each participant; per-participant acks are logged so a restart never re-sends a finished
commit. recover() re-drives unfinished transactions: a logged decision is re-delivered
(participants must treat commit/abort as idempotent), no decision means presumed abort.
```

## Documented variables

- `var store_path: String = ""` - "" = in-memory only
- `var prepare_timeout_msec: int = 0` - 0 = no timeout; a slower prepare counts as a refusal
- `var crash_point: String = ""` - test hook: "before_decision" | "after_decision"
- `var txs: Dictionary = {}` - tx_id -> record
- `var persistent_orders: Dictionary = {}` - order_id(String) -> order record
- `var _participants: Dictionary = {}` - name -> {prepare, commit, abort}

## Functions

### `add_participant`

```gdscript
func add_participant(pname: String, prepare: Callable, commit: Callable, abort: Callable) -> void
```

### `set_path`

```gdscript
func set_path(path: String) -> void
```

### `load_store`

```gdscript
func load_store() -> bool
```

Loads the store (if any). Safe on missing/corrupt files (starts empty).

### `save_store`

```gdscript
func save_store() -> bool
```

### `begin`

```gdscript
func begin(ops_by_participant: Dictionary) -> String
```

### `status`

```gdscript
func status(tx_id: String) -> String
```

### `run`

```gdscript
func run(tx_id: String) -> String
```

Drives a transaction to completion. Returns "committed", "aborted" or "crashed" (test hook).

### `recover`

```gdscript
func recover() -> Dictionary
```

After a restart (new instance, load_store(), participants re-added): finish in-doubt txs.

### `abort_stale`

```gdscript
func abort_stale(now_unix: float, max_age_sec: float) -> int
```

Aborts undecided transactions older than max_age_sec.

### `place_order`

```gdscript
func place_order(owner: String, side: String, item: String, price: float, qty: int) -> String
```

side: "buy" | "sell". Returns order id.

### `cancel_order`

```gdscript
func cancel_order(order_id: String) -> bool
```

### `open_orders`

```gdscript
func open_orders(item: String, side: String) -> Array
```

### `match_orders`

```gdscript
func match_orders(item: String) -> Array
```

Price-time priority matching; trades execute at the resting (older) order's price.
Returns [{buyer, seller, item, price, qty, buy_id, sell_id}].

_1 private function(s) starting with `_` are not listed._
