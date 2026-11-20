# Portable tarp shelter

Craft a temporary outdoor shelter from 2 cloth T1, 2 fiber T1 and
1 plank T1. Pitch the tarp 1.7–4 metres away on dry, open, level terrain
outside the safe settlement. A living unmounted player may create one
shelter, and the server caps total shelters at 64.

For 4 minutes, the tarp reduces cold/storm exposure intensity by **75%**
for everyone within **3.5 metres**. Shelter never grants PvP immunity,
free healing, protection from infection/spores, or zombie stealth.
Campfires, weather armor and temporary heat packs still work normally.

The server verifies placement, money-free real inventory costs, neighbors,
infected, temporary ownership and expiry. Nearby peers receive only
public coordinates and remaining duration; account names stay private.
Tents are ephemeral and do not enter character/world saves. Owners can
pack nearby tents without any refund.

Online inventory buttons: Pitch field tarp / Pack nearest tarp.
Offline: F6 pitch, F7 pack.

Tests: godot --headless --path game --script res://tests/run_all.gd
