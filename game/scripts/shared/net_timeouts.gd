extends RefCounted
## ENet link timeouts for one game connection.
##
## ENet's defaults drop a peer after ~5 s without acknowledgements. A first launch
## compiles shaders and builds the world around the survivor; on an M1 that froze
## the client ~6 s and the server ~4.5 s, so the connection died right after the
## welcome. Both sides now tolerate stalls of up to 15 s (and wait at most 45 s
## before declaring a link dead), which still detects a real disconnect quickly
## enough for combat-logout and save rules.

const LIMIT := 32 # ENet's default retry scaling.
const MIN_MS := 15000
const MAX_MS := 45000


## Applies the timeouts to the ENet link to `peer_id` (1 = the server, from a client). False if there is none.
static func apply(peer: ENetMultiplayerPeer, peer_id: int) -> bool:
	if peer == null:
		return false
	var link: ENetPacketPeer = peer.get_peer(peer_id)
	if link == null:
		return false
	link.set_timeout(LIMIT, MIN_MS, MAX_MS)
	return true
