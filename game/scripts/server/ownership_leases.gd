extends RefCounted
## Expiring ownership leases with monotonic fencing tokens.
##
## Original GDScript implementation. Concept references only (no code copied):
##   - Gray & Cheriton, "Leases: An Efficient Fault-Tolerant Mechanism for Distributed File Cache
##     Consistency", SOSP 1989 (time-bounded grants; the holder stops acting before expiry,
##     the server waits out expiry before re-granting; allowance for clock drift).
##   - Kleppmann, "How to do distributed locking" (2016): a lease alone cannot stop a paused/zombie
##     holder, so every grant carries a monotonically increasing fencing token that the protected
##     resource checks and uses to reject writes from stale holders.
## License of this file: same as the project; no third-party code included.
##
## Time is passed in explicitly (`now`, seconds or ticks) so the table is deterministic.

## The protected resource: remembers the highest token seen per key, rejects anything lower.
class FencedStore extends RefCounted:
	var max_token: Dictionary = {}   ## key -> highest accepted token
	var values: Dictionary = {}
	var rejected: int = 0

	func write(key: String, token: int, value: Variant) -> bool:
		if token < int(max_token.get(key, 0)):
			rejected += 1
			return false
		max_token[key] = token
		values[key] = value
		return true

	func read(key: String) -> Variant:
		return values.get(key)


var leases: Dictionary = {}        ## key -> {holder, token, expires}
var _tokens: Dictionary = {}       ## key -> last token ever issued (survives release/expiry)


## Grants (or re-confirms) the lease. {"ok", "token", "expires"}. A different holder is refused
## until the current lease has expired; a new grant always gets a strictly higher token.
func acquire(key: String, holder: String, now: float, ttl: float) -> Dictionary:
	if leases.has(key):
		var cur: Dictionary = leases[key]
		if float(cur["expires"]) > now:
			if String(cur["holder"]) == holder:
				cur["expires"] = now + ttl
				return {"ok": true, "token": int(cur["token"]), "expires": now + ttl}
			return {"ok": false, "token": 0, "expires": float(cur["expires"])}
	var token := int(_tokens.get(key, 0)) + 1
	_tokens[key] = token
	leases[key] = {"holder": holder, "token": token, "expires": now + ttl}
	return {"ok": true, "token": token, "expires": now + ttl}


## Extends the lease. Refused once expired (the holder must re-acquire and get a new token) or when
## the token/holder does not match the current grant.
func renew(key: String, holder: String, token: int, now: float, ttl: float) -> bool:
	if not leases.has(key):
		return false
	var cur: Dictionary = leases[key]
	if String(cur["holder"]) != holder or int(cur["token"]) != token or float(cur["expires"]) <= now:
		return false
	cur["expires"] = now + ttl
	return true


func release(key: String, holder: String, token: int) -> bool:
	if not leases.has(key):
		return false
	var cur: Dictionary = leases[key]
	if String(cur["holder"]) != holder or int(cur["token"]) != token:
		return false
	leases.erase(key)
	return true


## Current holder or "" when free/expired.
func holder_of(key: String, now: float) -> String:
	if not leases.has(key):
		return ""
	var cur: Dictionary = leases[key]
	if float(cur["expires"]) <= now:
		return ""
	return String(cur["holder"])


func token_of(key: String) -> int:
	return int(_tokens.get(key, 0))


func is_valid(key: String, holder: String, token: int, now: float) -> bool:
	return holder_of(key, now) == holder and int((leases[key] as Dictionary)["token"]) == token


## Holder-side check with a drift allowance: stop acting `drift` before the server-side expiry.
static func client_valid(expires: float, now: float, drift: float) -> bool:
	return now < expires - drift


## Drops expired leases; returns their keys (tokens are kept so the next grant is higher).
func reap(now: float) -> Array:
	var gone: Array = []
	for key in leases.keys():
		var cur: Dictionary = leases[key]
		if float(cur["expires"]) <= now:
			gone.append(key)
	for key in gone:
		leases.erase(key)
	return gone
