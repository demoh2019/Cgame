extends RefCounted
## Classic party-healer threat without client-defined targets or strength.
## Award threat only for actual server-applied HP, not cured infection, wound
## treatment, rejected actions or overheal. Combat threat remains ephemeral.

const HEAL_TO_THREAT := 0.75
const MAX_PER_ACTION := 75.0


## Multi-target healing is summed once per infected, then capped.
static func threat_for(actual_heal: float) -> float:
	if not is_finite(actual_heal) or actual_heal <= 0.0:
		return 0.0
	return minf(MAX_PER_ACTION, actual_heal * HEAL_TO_THREAT)


## Only an infected already fighting the patient can react to their medic.
## Neither silence nor an unrelated nearby enemy creates new aggro.
static func can_credit(infected, medic_position: Vector3, patient_position: Vector3,
		patient_peer: int) -> bool:
	if infected == null or not infected.is_alive() or patient_peer <= 0 or \
			not infected.position.is_finite() or not medic_position.is_finite() or \
			not patient_position.is_finite():
		return false
	if infected.target_id != patient_peer and not infected.threat.has(patient_peer):
		return false
	var leash: float = float(infected.data.get("lose", 0.0))
	if not is_finite(leash) or leash <= 0.0:
		return false
	var here := Vector2(infected.position.x, infected.position.z)
	var medic := Vector2(medic_position.x, medic_position.z)
	var patient := Vector2(patient_position.x, patient_position.z)
	return here.distance_squared_to(medic) <= leash * leash and \
		here.distance_squared_to(patient) <= leash * leash
