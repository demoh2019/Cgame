# Raid boss ground-slam telegraph (online client)

The existing group raid boss already sends a 2-second `raid_warning`
event with an authoritative ground position, radius and boss ID, followed
by `raid_slam`, `raid_defeated` or `raid_expired`.

The online game now presents that warning as a large, translucent red
ground circle at the server-specified position, with a live countdown.
Players can move or dodge before the server resolves the damage.
Stale boss events cannot clear a newer warning. Visuals automatically
disappear when the impact happens, the boss dies, the raid expires, or
the warning timeout elapses. All input fields are finite and bounded.

The circle is **visual feedback only**; no collision, hit or dodge
authority moved to the client. The existing PvE/PvP protections and server
interest-filtered raid notifications are unchanged. Tests run in
`game/tests/test_raid_telegraph.gd`.
