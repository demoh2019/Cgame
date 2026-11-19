#!/usr/bin/env python3
"""A reproducible, bounded UDP network-condition proxy for Godot multiplayer tests.

Uses only the Python standard library. This is a transport-level testing tool,
not a replacement for Godot's multiplayer debugger or a production relay.
"""

from __future__ import annotations

import argparse
import heapq
import json
import random
import selectors
import signal
import socket
import sys
import threading
import time
from dataclasses import asdict, dataclass, field
from typing import Callable

from network_sim_presets import PRESETS, resolve_preset


@dataclass(frozen=True)
class Impairment:
    latency_ms: float = 0.0
    jitter_ms: float = 0.0
    loss_percent: float = 0.0
    duplicate_percent: float = 0.0

    def __post_init__(self) -> None:
        import math

        for key in ("latency_ms", "jitter_ms"):
            val = getattr(self, key)
            if not math.isfinite(val) or not (0 <= val <= 120000):
                raise ValueError(f"{key} must be finite and between 0 and 120000")
        for key in ("loss_percent", "duplicate_percent"):
            val = getattr(self, key)
            if not math.isfinite(val) or not (0 <= val <= 100):
                raise ValueError(f"{key} must be finite and between 0 and 100")

    def schedule(self, now: float, rng: random.Random) -> list[float]:
        """Return delivery times (zero, one or two) for a single datagram."""
        if self.loss_percent and rng.random() * 100 < self.loss_percent:
            return []
        copies = 1 + int(bool(self.duplicate_percent and rng.random() * 100 < self.duplicate_percent))
        times = []
        for _ in range(copies):
            jitter = rng.uniform(-self.jitter_ms, self.jitter_ms) if self.jitter_ms else 0.0
            times.append(now + max(0.0, self.latency_ms + jitter) / 1000.0)
        return times


def policy_from_args(args: argparse.Namespace, direction: str) -> Impairment:
    """Resolve the selected profile with optional per-direction CLI overrides."""
    if direction not in ("up", "down"):
        raise ValueError(f"Unknown traffic direction: {direction!r}")
    overrides = {
        "latency_ms": getattr(args, f"{direction}_latency_ms"),
        "jitter_ms": getattr(args, f"{direction}_jitter_ms"),
        "loss_percent": getattr(args, f"{direction}_loss"),
        "duplicate_percent": getattr(args, f"{direction}_duplicate"),
    }
    return Impairment(**resolve_preset(args.preset, overrides))


@dataclass
class DirectionStats:
    received: int = 0
    scheduled: int = 0
    dropped: int = 0
    duplicated: int = 0
    delivered: int = 0
    bytes_delivered: int = 0
    send_errors: int = 0


@dataclass
class Session:
    address: tuple[str, int]
    upstream: socket.socket
    last_seen: float


@dataclass(order=True)
class Pending:
    deadline: float
    sequence: int
    direction: str = field(compare=False)
    address: tuple[str, int] = field(compare=False)
    payload: bytes = field(compare=False)
    upstream: socket.socket = field(compare=False)


class UDPNetworkSimulator:
    """Multiplex one UDP socket per client, so server replies cannot mix clients."""

    def __init__(
        self,
        target: tuple[str, int],
        listen: tuple[str, int] = ("127.0.0.1", 0),
        upstream: Impairment = Impairment(),
        downstream: Impairment = Impairment(),
        seed: int = 0,
        max_clients: int = 64,
        session_timeout: float = 60.0,
        now: Callable[[], float] = time.monotonic,
        max_pending: int = 10000,
    ) -> None:
        if not (1 <= max_pending <= 1000000):
            raise ValueError("max_pending must be between 1 and 1000000")
        if not (1 <= max_clients <= 10000):
            raise ValueError("max_clients must be between 1 and 10000")
        if not (0.1 <= session_timeout <= 86400):
            raise ValueError("session_timeout must be between 0.1 and 86400 seconds")
        if not 1 <= target[1] <= 65535:
            raise ValueError("target port must be between 1 and 65535")
        if not 0 <= listen[1] <= 65535:
            raise ValueError("listen port must be between 0 and 65535")
        # Initial scope: IPv4 only. getaddrinfo also supports hostname targets.
        infos = socket.getaddrinfo(target[0], target[1], socket.AF_INET, socket.SOCK_DGRAM)
        if not infos:
            raise ValueError("Could not resolve IPv4 target")
        self.target = infos[0][4]
        self.now = now
        self.policies = {"up": upstream, "down": downstream}
        self.stats = {"up": DirectionStats(), "down": DirectionStats()}
        self.rejected_clients = 0
        self.rng = random.Random(seed)
        self.max_clients = max_clients
        self.max_pending = max_pending
        self.session_timeout = session_timeout
        self.sessions: dict[tuple[str, int], Session] = {}
        self.pending: list[Pending] = []
        self.sequence = 0
        self.selector = selectors.DefaultSelector()
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.listener.bind(listen)
            if self.listener.getsockname()[1] == self.target[1] and (
                self.listener.getsockname()[0] == self.target[0]
                or self.listener.getsockname()[0] == "0.0.0.0"
            ):
                raise ValueError("Target and listener must not use the same local endpoint")
            self.listener.setblocking(False)
            self.selector.register(self.listener, selectors.EVENT_READ, data=None)
        except BaseException:
            self.listener.close()
            self.selector.close()
            raise
        self.closed = False

    @property
    def listen_address(self) -> tuple[str, int]:
        return self.listener.getsockname()

    def __enter__(self) -> UDPNetworkSimulator:
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        self.close()

    def _get_session(self, address: tuple[str, int], now: float) -> Session | None:
        session = self.sessions.get(address)
        if session is not None:
            session.last_seen = now
            return session
        if len(self.sessions) >= self.max_clients:
            self.rejected_clients += 1
            return None
        try:
            upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        except OSError:
            self.rejected_clients += 1
            return None
        try:
            upstream.connect(self.target)
            upstream.setblocking(False)
            session = Session(address, upstream, now)
            self.selector.register(upstream, selectors.EVENT_READ, session)
            self.sessions[address] = session
        except (OSError, ValueError):
            upstream.close()
            self.rejected_clients += 1
            return None
        return session

    def _enqueue(self, direction: str, session: Session, data: bytes, now: float) -> None:
        stats = self.stats[direction]
        stats.received += 1
        deadlines = self.policies[direction].schedule(now, self.rng)
        if not deadlines:
            stats.dropped += 1
            return
        for index, deadline in enumerate(deadlines):
            if len(self.pending) >= self.max_pending:
                stats.dropped += 1
                continue
            stats.scheduled += 1
            if index > 0:
                stats.duplicated += 1
            self.sequence += 1
            heapq.heappush(self.pending, Pending(deadline, self.sequence, direction, session.address, data, session.upstream))

    def _deliver_due(self, now: float) -> None:
        while self.pending and self.pending[0].deadline <= now:
            packet = heapq.heappop(self.pending)
            stats = self.stats[packet.direction]
            session = self.sessions.get(packet.address)
            # Do not leak late packets into a new session reusing a UDP address.
            if session is None or session.upstream is not packet.upstream:
                stats.dropped += 1
                continue
            try:
                if packet.direction == "up":
                    sent = session.upstream.send(packet.payload)
                else:
                    sent = self.listener.sendto(packet.payload, packet.address)
                if sent != len(packet.payload):
                    stats.send_errors += 1
                else:
                    stats.delivered += 1
                    stats.bytes_delivered += sent
            except (OSError, BlockingIOError):
                stats.send_errors += 1

    def _expire(self, now: float) -> None:
        busy = {packet.upstream for packet in self.pending}
        for address, session in list(self.sessions.items()):
            if now - session.last_seen >= self.session_timeout and session.upstream not in busy:
                self.sessions.pop(address)
                try:
                    self.selector.unregister(session.upstream)
                except (OSError, KeyError, ValueError):
                    pass
                session.upstream.close()

    def run_once(self, max_wait: float = 0.05) -> None:
        if self.closed:
            raise RuntimeError("proxy has been closed")
        if max_wait < 0:
            raise ValueError("max_wait must not be negative")
        now = self.now()
        self._deliver_due(now)
        self._expire(now)
        timeout = min(max_wait, 0.1, max(0.0, self.pending[0].deadline - now) if self.pending else max_wait)
        for key, _ in self.selector.select(timeout):
            try:
                data, address = key.fileobj.recvfrom(65535)
            except (BlockingIOError, OSError):
                continue
            timestamp = self.now()
            if key.data is None:
                session = self._get_session(address, timestamp)
                if session is not None:
                    self._enqueue("up", session, data, timestamp)
            else:
                session = key.data
                if self.sessions.get(session.address) is session:
                    session.last_seen = timestamp
                    self._enqueue("down", session, data, timestamp)
        self._deliver_due(self.now())

    def serve(self, stop: threading.Event) -> None:
        while not stop.is_set():
            self.run_once()

    def snapshot(self) -> dict[str, object]:
        return {
            "listen": list(self.listen_address) if not self.closed else None,
            "target": list(self.target),
            "active_clients": len(self.sessions),
            "rejected_clients": self.rejected_clients,
            "queued_datagrams": len(self.pending),
            "up": asdict(self.stats["up"]),
            "down": asdict(self.stats["down"]),
        }

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        for session in list(self.sessions.values()):
            session.upstream.close()
        self.sessions.clear()
        self.pending.clear()
        self.selector.close()
        self.listener.close()


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-host", default="127.0.0.1", help="Godot ENet server IPv4/hostname")
    parser.add_argument("--target-port", required=True, type=int)
    parser.add_argument("--listen-host", default="127.0.0.1", help="Default loopback only")
    parser.add_argument("--listen-port", type=int, default=2457)
    parser.add_argument("--preset", choices=sorted(PRESETS), default="clean",
                        help="Synthetic one-way connection profile, defaults to clean")
    for name in ("up", "down"):
        parser.add_argument(f"--{name}-latency-ms", type=float, default=None)
        parser.add_argument(f"--{name}-jitter-ms", type=float, default=None)
        parser.add_argument(f"--{name}-loss", type=float, default=None)
        parser.add_argument(f"--{name}-duplicate", type=float, default=None)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--max-clients", type=int, default=64)
    parser.add_argument("--max-pending", type=int, default=10000, help="Cap queued copies per proxy")
    parser.add_argument("--session-timeout", type=float, default=60.0)
    parser.add_argument("--stats-file", type=str, help="Optional JSON report path written at exit")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    try:
        with UDPNetworkSimulator(
            (args.target_host, args.target_port), (args.listen_host, args.listen_port),
            policy_from_args(args, "up"), policy_from_args(args, "down"), args.seed, args.max_clients, args.session_timeout,
            max_pending=args.max_pending,
        ) as proxy:
            stop = threading.Event()
            previous = {}
            if threading.current_thread() is threading.main_thread():
                for sig in (signal.SIGINT, signal.SIGTERM):
                    previous[sig] = signal.getsignal(sig)
                    signal.signal(sig, lambda signum, frame: stop.set())
            try:
                print(json.dumps({"event": "listening", **proxy.snapshot()}), flush=True)
                proxy.serve(stop)
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
                report = json.dumps(proxy.snapshot(), sort_keys=True)
                print(report, flush=True)
                if args.stats_file:
                    from pathlib import Path
                    Path(args.stats_file).write_text(report + "\n", encoding="utf-8")
        return 0
    except (OSError, ValueError) as exc:
        print(f"multiplayer_network_sim: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
