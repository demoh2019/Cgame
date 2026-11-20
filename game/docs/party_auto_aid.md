# Automatic party first aid

In the Party panel choose a teammate (within 3.2 m and 2.5 m vertically)
and click **Aid**. The default option is **Auto (choose carried medicine)**.
You can still select a particular medicine from the complete shared item
catalog. A medical item must be in the healer's real inventory.

The server chooses the cheapest carried medicine capable of treating the
most urgent *existing* condition: bleeding, fracture, infection, then missing
health. Prices come from the actual item definitions; alphabetical item ID
breaks ties. The server checks range, party membership, life state, treatment
effect and the existing five-second cooldown before consuming one item.
No item is spent when no carried treatment has an effect, and clients cannot
forge a patient's injury state or override server-side selection.

All items with `kind = "medical"` are shown automatically, including herbal
poultices, field splints and spore antidotes. Equipment, food and multi-target
triage packs remain unavailable for single-target aid. Character-specific
maximum health is respected, so advanced characters can receive treatment
above the base 100 HP.

Run: `godot --headless --path game --script res://tests/run_all.gd`;
`test_party_aid.gd` covers the catalog, automatic selection, consumption,
party authorization and health cap.
