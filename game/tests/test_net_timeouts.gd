extends RefCounted
## ENet link timeouts survive first-launch stalls (see scripts/shared/net_timeouts.gd).

const NetTimeouts = preload("res://scripts/shared/net_timeouts.gd")


func run(t) -> void:
	t.current = "ENet stall tolerance"
	t.check(NetTimeouts.MIN_MS >= 10000, "tolerates a 10 s+ shader/world-build freeze (ENet default is 5 s)")
	t.check(NetTimeouts.MAX_MS > NetTimeouts.MIN_MS, "max timeout above min")
	t.check(NetTimeouts.MAX_MS <= 60000, "a truly dead link is still dropped within a minute")
	t.check(not NetTimeouts.apply(null, 1), "no peer, no-op")
	var unconnected := ENetMultiplayerPeer.new()
	t.check(not NetTimeouts.apply(unconnected, 1), "unknown link is reported, not crashed on")
	t.current = "live loopback link"
	var server := ENetMultiplayerPeer.new()
	if server.create_server(24899, 2) == OK:
		var client := ENetMultiplayerPeer.new()
		client.create_client("127.0.0.1", 24899)
		var linked := false
		for i in 200:
			server.poll()
			client.poll()
			if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				linked = true
				break
			OS.delay_msec(5)
		t.check(linked, "loopback client connects")
		if linked:
			t.check(NetTimeouts.apply(client, 1), "client applies timeouts to its server link")
		client.close()
		server.close()
