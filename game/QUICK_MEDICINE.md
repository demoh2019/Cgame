# Smart Field Medicine

**Ctrl+3** selects a useful medical treatment in both the local and
online clients. **3** still uses a bandage; **Shift+3** still uses the
expedition trauma kit.

The authoritative server chooses one real, carried item from current wounds:

1. Splint for fractures.
2. Bandage, poultice or antiseptic for bleeding.
3. Infection medicine sized to the severity.
4. HP healing when at least 10 HP is missing.

No item is created, and the normal `cmd_use` rules apply: health, inventory
consumption, restrictions on mounts and recall, skill progression and saving.
Minor scratches alone do not automatically consume medicine.

Regression test: `godot --headless --path game --script res://tests/run_all.gd`
