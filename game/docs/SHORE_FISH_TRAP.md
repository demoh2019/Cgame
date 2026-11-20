# Shoreline fish trap

Craft a Shore Fish Trap at the workbench from 2 planks T1, 3 fiber T1,
and 1 scrap. Carry an actual fishing rod and place the net from a dry
shore outside the settlement. The server chooses a true water tile; no
client may invent a site or high-tier catch.

Return after **120 seconds** to collect **2 fish**. The maximum fish tier
is capped by the coast zone, your equipped/carried rod tier, and fishing
profession. Normal fishing XP is credited only on successful collection.

Only the account owner or original guest session may collect their trap,
within 4.5 metres from land and with enough inventory space. A net lasts
at most 600 seconds, cannot be claimed twice, and never persists with
world/base saves. Limits: one live trap per owner, 80 worldwide, no overlapping
buoys. Neighboring players see water buoy, readiness and tier, but no
private owner/account identifiers. Nets do not block movement, combat or PvP.

Controls: Deploy fish trap F10 / Collect nearest F12 in online and offline,
also available from online Inventory.

Run: godot --headless --path game --script res://tests/run_all.gd
