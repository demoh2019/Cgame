# Storm fuel consumption

During storms, deployed campfires burn **twice as fast**. The server calculates
weather from the campfire location, world seed and authoritative world time.
Clear weather and sheltered positions do not incur the extra fuel cost.
Once the fire runs out, warmth and field resting stop immediately.

Nearby players receive a campfire_doused event with the fire position but no
private owner/account ID. The existing shared refuel action can extend a live
fire for two T1 wood, with its normal distance and duration caps.

This session-only mechanic never modifies inventory, character saves or
permanent structures. The existing engine already supports it.

Regression test: res://tests/test_campfire_storm.gd
