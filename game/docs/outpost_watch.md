# Fortified outpost watch signals

At **fortification tier 1+**, a captured outpost emits a private defensive
warning when any *living hostile survivor* enters its 12-metre capture circle.
The notification is a meaningful advantage for teams investing actual wood
and stone into fortifications; it is not a free minimap radar.

- Alert recipients: current owning party and backend-verified members
  of the same homogeneous Nakama guild, including those in remote parties.
- The server uses live occupancy-side rules and considers **unopposed
  infiltration** hostile even when the ordinary public `contested` flag is
  false because no defender is present.
- A location sends at most one alarm every **90 server seconds** while
  occupied by enemies. Ordinary group members and verified guildmates
  do not trigger alarms.
- Alarm payload: known outpost ID and flag coordinates, owner-party ID
  and fortification tier. No attacker IDs, health, headcount, equipment
  or secret presence details are disclosed. The network filters each
  recipient against current authoritative group/guild membership.
- Capturing a new flag or its expiry resets the per-capture cooldown.
  Losing fortification below tier 1 suppresses further private alerts.
- No special RPC is exposed to clients: signals derive exclusively from
  the existing authoritative `TerritoryControl.tick` and are delivered
  by the existing private event channel.
- Clients see the warning in the HUD. All current siege, crafting,
  provisioning and reward rules remain unchanged; no engine patch needed.

Regression: `game/tests/test_outpost_watch.gd`, in `run_all.gd`.
