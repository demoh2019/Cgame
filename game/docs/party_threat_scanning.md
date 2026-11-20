# Party Threat Scanner Relay

A crafted **Field Threat Scanner** can now relay a detected elite infected or
raid boss to the scout's existing party. This extends the scanner already
available through the HUD inventory action; no new client command is required.

- Craft the scanner at a workbench (the same paid recipe as before), form a
  party of at least two living survivors, and activate it outside a safe zone
  while not mounted or fighting.
- One scanner is consumed per successful detection. The scout receives the
  normal magenta radar marker; eligible teammates see a **cyan** moving marker.
  HUD feedback says whether the scan was private or shared.
- Intel expires after 50 seconds, and is removed if the target dies or leaves
  the recipient's 170 m tracking range. A dead scout stops transmitting.
- The server binds the intel to the **exact party roster at scan time**.
  Inviting, kicking or losing members invalidates the old relay; a newly joined
  player cannot inherit previously purchased reconnaissance. The owner keeps
  their own mark until its normal expiry.
- Solo scans stay private even if the scout later forms a party. Other players
  never receive tracked targets in public actor snapshots.
- The target, time, party roster and permissions come exclusively from the
  authoritative server. Clients cannot request arbitrary enemy IDs or map
  positions, and nothing is persisted between sessions.

## Test

Run `godot --headless --path game --script res://tests/run_all.gd`.
`test_party_threat_scanner.gd` covers paid activation, party sharing, radar
parity, target limits, enemy/scout death, roster invalidation and expiry.
