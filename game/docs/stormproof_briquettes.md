# Stormproof Ember Briquettes

A temporary, shared survival tool for storm expeditions.

Craft one **Stormproof Ember Briquette** in the field from 3 Wood T1,
2 Fiber T1, and 1 Scrap. Stand within 3.2 m of a burning field campfire,
then press **Shift+9** to weatherproof it (ordinary **9** still refuels
from two wood). The server chooses the nearby live fire, consumes one
briquette only after validating all requirements and adds 120 seconds
of normal fire fuel, capped by the original 600-second maximum.

For 90 seconds, storm weather does not impose extra fuel burn on that
fire. The normal one-second-per-second fuel consumption still applies.
A tick straddling the exact protection expiration burns extra fuel only
for its unprotected fraction. Reapplication during active protection is
refused without consuming another briquette.

Nearby players can see the remaining protection time, but not the
fire owner's identity. Ordinary light attraction of infected, proximity
checks, owner-only extinguishing, shared fire warmth, night detection,
weather exposure, and all existing campfire caps still apply.

Implementation: `scripts/shared/stormproof_briquette.gd`, authoritative
`scripts/server/game_server.gd`, and
`tests/test_stormproof_briquette.gd`.
No engine extension is needed.
