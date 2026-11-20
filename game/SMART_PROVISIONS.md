# Smart Survival Provisions

The game automatically chooses **carried, safe** provisions while respecting
the original manual hotkeys:

- **Ctrl+1** — smart food when hunger is 85 or lower.
- **Ctrl+2** — smart drinking when thirst is 85 or lower.
- **1 / 2** — original canned food / water bottle; **Shift+1** still uses
  fish stew, **Shift+2** still fills the lake pouch, and **Alt+1** still
  allows manual risky raw fish.

The authoritative server reads real inventory and survival stats. It selects
food or drink based on how much is missing, the item's restore values, and the
resources used. When both hunger and thirst are low, one real camp fish stew
can replenish both. It does not choose raw fish, unboiled water or empty pouches.

The selected item is passed to the existing `cmd_use`, so ordinary item costs,
mount/recall limits, nutrition buffs, progress and persistence are unchanged.
Invalid or unnecessary requests do not consume supplies.

Regression tests:
```sh
godot --headless --path game --script res://tests/run_all.gd
```
