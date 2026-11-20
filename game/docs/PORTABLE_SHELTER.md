# Portable tarp shelter

Craft a temporary outdoor shelter from 2 cloth T1, 2 fiber T1 and
1 plank T1. Pitch the tarp 1.7–4 metres away on dry, open, level terrain
outside the safe settlement. A living unmounted player may create one
shelter, and the server caps total shelters at 64.

For 4 minutes, the tarp reduces cold/storm exposure intensity by **75%**
for everyone within **3.5 metres**. A quiet, crouched survivor under an
active canopy also gets a 25% reduction to visual detection by idle infected.
Existing armor and stance bonuses still apply, with a hard visibility floor.

Standing, noise, leaving the canopy or its expiration immediately remove the
vision bonus. The tarp never blocks NPC hearing, blood scent, campfire light,
existing aggro or PvP targeting, nor does it grant immunity, free healing,
infection or spore protection. Campfires and weather equipment still work.

The server verifies placement, money-free real inventory costs, neighbors,
infected, temporary ownership and expiry. Nearby peers receive only
public coordinates and remaining duration; account names stay private.
Tents are ephemeral and do not enter character/world saves. Owners can
pack nearby tents without any refund. The server alone determines camouflage
from position, stance and real sound. The owner UI shows the effective bonus.

Online inventory buttons: Pitch field tarp / Pack nearest tarp.
Offline: F6 pitch, F7 pack.

Tests: godot --headless --path game --script res://tests/run_all.gd
