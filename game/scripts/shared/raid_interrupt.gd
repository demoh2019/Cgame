extends RefCounted
## Coordinated raid counterplay: two real party members can stop a telegraphed
## slam by landing attacks during its windup. All values are server-owned.
## One fighter's damage is capped so a solo burst never fakes teamwork.

const MAX_DISTANCE := 12.0
const CREDIT_PER_PLAYER := 16.0
const REQUIRED_DAMAGE := 26.0
const MIN_ATTACKERS := 2
const MAX_ATTACKERS := 8


## Mutates only this warning's ephemeral server-side contribution ledger.
## True means the current warning has been interrupted; caller clears it.
static func record_hit(warning: Dictionary, boss, peer_id: int, party_id: int,
		damage: float, now: float) -> bool:
	if boss == null or not boss.raid_boss or not boss.is_alive():
		return false
	if warning.is_empty() or int(warning.get("id", -1)) != boss.id:
		return false
	var deadline: float = float(warning.get("at", -1.0))
	if not is_finite(now) or not is_finite(deadline) or now >= deadline:
		return false
	if not is_finite(damage) or damage <= 0.0 or peer_id <= 0 or party_id <= 0:
		return false
	var owner_party: int = int(warning.get("party", 0))
	if owner_party != 0 and owner_party != party_id:
		return false
	var contributors: Dictionary = warning.get("contributors", {})
	if not contributors.has(peer_id) and contributors.size() >= MAX_ATTACKERS:
		return false
	var prior: float = float(contributors.get(peer_id, 0.0))
	var credit: float = minf(CREDIT_PER_PLAYER, prior + damage)
	if credit <= prior:
		return false
	contributors[peer_id] = credit
	warning["party"] = party_id
	warning["contributors"] = contributors
	var total: float = 0.0
	for amount in contributors.values():
		total += float(amount)
	return contributors.size() >= MIN_ATTACKERS and total >= REQUIRED_DAMAGE
