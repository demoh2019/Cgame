# Godot multiplayer network conditions simulator (experimental)

This standalone Python 3.9+ tool proxies **UDP** traffic between a game client and
a Godot ENet server. It can introduce per-direction latency, uniform jitter, packet
loss, and duplication to reproduce and debug multiplayer bugs. Its output is
machine-readable JSON (session counts, packet delivery/drop stats and bytes).

This is **roadmap item 42, phase 1**: an external test tool, not yet an editor
Multiplayer Debugger panel, packet-content inspector, or production relay.

## Quick start

1. Run your Godot ENet multiplayer server normally on UDP port **2456**.
2. Start the proxy on a different port, e.g. **2457**:

   ```sh
   python3 misc/scripts/multiplayer_network_sim.py \
     --target-host 127.0.0.1 --target-port 2456 \
     --listen-port 2457 --seed 42 \
     --up-latency-ms 75 --down-latency-ms 75 \
     --up-jitter-ms 20 --down-jitter-ms 20 \
     --up-loss 2 --down-loss 2 \
     --up-duplicate 0.5 --down-duplicate 0.5 \
     --stats-file /tmp/godot-network-report.json
   ```

3. Connect the **Godot client** to `127.0.0.1:2457`, not `:2456`.
4. Stop the proxy with Ctrl+C (or SIGTERM). It prints final JSON counters and
   optionally writes the JSON report file.

Example in GDScript (client only; server is configured as usual):

```gdscript
var peer := ENetMultiplayerPeer.new()
var error := peer.create_client("127.0.0.1", 2457)
if error == OK:
    multiplayer.multiplayer_peer = peer
```

`--up-*` alters **client → server**, and `--down-*` alters **server → client**.
Loss and duplicate values are percentages between 0 and 100 (for example,
`2` means 2%). Jitter is a uniform random offset between `-jitter` and
`+jitter` milliseconds; negative total delay is clamped to zero. A fixed seed
reproduces the decisions **for the same packet arrival ordering**. Separate
clients get separate backend UDP sockets to preserve ENet session identities.

Use `--help` to see all options. Defaults are intentionally zero-impairment
and bound to `127.0.0.1` (loopback only). No packet payload is logged.

## Ready-made network profiles

Use `--preset` to reproduce a synthetic connection scenario with one command
(the default `clean` profile preserves the existing zero-impairment behavior):

```sh
python3 misc/scripts/multiplayer_network_sim.py \
  --target-host 127.0.0.1 --target-port 2456 --listen-port 2457 --preset mobile
```

| Preset | One-way delay | Jitter (+/-) | Loss | Duplicate |
| --- | ---: | ---: | ---: | ---: |
| clean | 0 ms | 0 ms | 0% | 0% |
| fiber | 10 ms | 2 ms | 0% | 0% |
| wifi | 32 ms | 12 ms | 2% | 0% |
| mobile | 100 ms | 40 ms | 4% | 0.5% |
| satellite | 300 ms | 50 ms | 1% | 0% |
| severe | 250 ms | 100 ms | 12% | 2% |

These are illustrative testing profiles, **not measurements of actual services**.
The profile is applied **independently in both directions**; a packet travelling
through the proxy receives the configured one-way delay at each hop.
Explicit CLI arguments override only the selected direction, including zero:

```sh
python3 misc/scripts/multiplayer_network_sim.py \
  --target-port 2456 --preset severe --up-loss 0 --down-latency-ms 30
```

Use `--help` to see available profiles. Both the UDP proxy suite and the
preset regression suite run as CI checks.

## Safety, limits and semantics

- Tests should run against **local test servers** with explicit permission.
  To accept other hosts, you must explicitly set `--listen-host`, which may
  expose the listening UDP port. This is not an authenticated Internet relay.
- A target equal to the listening endpoint is refused to prevent proxy loops.
- Memory is bounded by `--max-clients` (default 64) and `--max-pending`
  (default 10,000 queued packets). Overflow gets counted as dropped copies.
- Client sessions expire after `--session-timeout` seconds of inactivity;
  pending packets keep their associated session alive until delivered or
  discarded. A disconnected client may still count as active until expiry.
- A UDP datagram may be dropped, delayed, duplicated, or arrive out-of-order
  due to jitter. The proxy does **not** rewrite ENet sequence numbers or
  manipulate Godot RPC calls.
- UDP is best-effort: delivery counted by the proxy means the OS accepted
  the datagram, not that a peer application processed it.
- IPv4 is supported (including target IPv4 hostnames); IPv6, TCP, HTTP,
  WebRTC, DTLS interception, bandwidth throttling, GUI integration,
  real device routing and replay files are out of scope.
- Use this as a stress/repro tool, not for performance benchmarks or security
  testing. OS scheduling and packet arrival ordering affect exact timings.

## Run the tests

```sh
python3 -m unittest discover -s misc/scripts/tests \
  -p 'test_multiplayer_network_sim.py' -v
```

The suite covers 100% loss/duplication, injected delay and jitter,
multiple simultaneous clients, large and empty datagrams, session eviction,
queue caps, deterministic seeds, stats and graceful CLI shutdown. The tests
need only Python 3; they use local UDP sockets and subprocesses and do not
require compiling Godot. Godot-side gameplay tests remain necessary.

This feature is designed for the `demoh2019/godot` fork; it does not modify
upstream Godot's network protocol. MIT-licensed under the engine repository's
license. AI assistance was used in implementation and tests.
