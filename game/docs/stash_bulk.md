# Bulk resource banking at the protected stash

At the hub workbench, open **Inventory (I / Tab)** and press
**BANK ALL: resources + crafting materials** under the protected stash.
This sends one authenticated, server-rate-limited command to deposit all
carried items whose item kind is `resource` or `material`.

- Raw gathered wood, stone, ore and fiber are deposited.
- Refined cloth, metal bars, planks and other crafting resources are deposited.
- Food, water, medicines, equipment, tools and **silver** are never included.
- If the bank is almost full, only units that actually fit are moved. The
  HUD reports moved count and units still carried.
- A full bank or an empty material bag changes nothing.
- Resource stacks and item IDs come from **server-owned inventory**, not
  from untrusted client input. Both containers are staged and committed
  together after capacity checks.
- The normal protected bank still uses 48 account-bound slots, persists
  across logins, and is not dropped on character death.

The previous per-item right-click deposit and withdrawal are unchanged.
No Godot engine change is required.

Regression: `res://tests/test_stash_bulk.gd` is part of
`game/tests/run_all.gd`. To verify locally:

```bash
godot --headless --path game --script res://tests/run_all.gd
```
