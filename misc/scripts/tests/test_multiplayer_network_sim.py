"""Offline transport and UDP loopback regression suite for multiplayer_network_sim."""

import contextlib
import importlib.util
import io
import json
import math
import os
import random
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "multiplayer_network_sim.py"
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location("multiplayer_network_sim", SCRIPT)
sim = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = sim
spec.loader.exec_module(sim)


class ImpairmentTests(unittest.TestCase):
    def test_default_is_immediate_single_delivery(self):
        self.assertEqual(sim.Impairment().schedule(2.0, random.Random(1)), [2.0])

    def test_100_percent_loss(self):
        p = sim.Impairment(loss_percent=100)
        self.assertTrue(all(not p.schedule(1, random.Random(s)) for s in range(100)))

    def test_100_percent_duplication(self):
        p = sim.Impairment(duplicate_percent=100)
        self.assertEqual(p.schedule(10, random.Random(0)), [10, 10])

    def test_loss_takes_precedence_over_duplication(self):
        self.assertEqual(sim.Impairment(loss_percent=100, duplicate_percent=100).schedule(0, random.Random()), [])

    def test_exact_latency(self):
        self.assertEqual(sim.Impairment(latency_ms=125).schedule(1, random.Random()), [1.125])

    def test_jitter_in_range(self):
        p = sim.Impairment(latency_ms=50, jitter_ms=25)
        r = random.Random(19)
        values = [p.schedule(7, r)[0] for _ in range(500)]
        self.assertGreater(max(values), 7.07)
        self.assertLess(min(values), 7.03)
        self.assertTrue(all(7.025 <= v <= 7.075 for v in values))

    def test_jitter_never_schedules_past(self):
        p = sim.Impairment(jitter_ms=15)
        self.assertTrue(all(p.schedule(5, random.Random(i))[0] >= 5 for i in range(200)))

    def test_independent_duplication_jitter(self):
        p = sim.Impairment(latency_ms=100, jitter_ms=100, duplicate_percent=100)
        d = p.schedule(0, random.Random(1))
        self.assertEqual(len(d), 2)
        self.assertNotEqual(d[0], d[1])

    def test_seed_is_reproducible(self):
        p = sim.Impairment(30, 20, 40, 20)
        r1 = random.Random(123)
        r2 = random.Random(123)
        self.assertEqual([p.schedule(0, r1) for _ in range(100)], [p.schedule(0, r2) for _ in range(100)])

    def test_not_all_seeds_have_same_outcome(self):
        p = sim.Impairment(loss_percent=50)
        self.assertGreater(len({bool(p.schedule(0, random.Random(i))) for i in range(100)}), 1)

    def test_nan_inf_negative_and_out_of_range_are_rejected(self):
        for field in ("latency_ms", "jitter_ms", "loss_percent", "duplicate_percent"):
            for bad in (float("nan"), float("inf"), -1, float("-inf"), 120001):
                with self.subTest(field=field, bad=bad), self.assertRaises(ValueError):
                    sim.Impairment(**{field: bad})

    def test_boundary_values_are_accepted(self):
        sim.Impairment(latency_ms=120000, jitter_ms=120000, loss_percent=100, duplicate_percent=100)
        sim.Impairment(loss_percent=0, duplicate_percent=0)


class LocalEchoServer:
    def __init__(self):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.socket.settimeout(0.03)
        self.address = self.socket.getsockname()
        self.stop = threading.Event()
        self.seen = []
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        while not self.stop.is_set():
            try:
                data, address = self.socket.recvfrom(65535)
                self.seen.append((address, data))
                self.socket.sendto(data, address)
            except socket.timeout:
                pass
            except OSError:
                break

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *ignored):
        self.stop.set()
        self.thread.join(timeout=2)
        self.socket.close()


@contextlib.contextmanager
def running_proxy(target, **kwargs):
    with sim.UDPNetworkSimulator(target, listen=("127.0.0.1", 0), **kwargs) as proxy:
        stop = threading.Event()
        thread = threading.Thread(target=proxy.serve, args=(stop,), daemon=True)
        thread.start()
        try:
            yield proxy
        finally:
            stop.set()
            thread.join(timeout=2)
            assert not thread.is_alive(), "proxy did not shut down promptly"


class ProxyTransportTests(unittest.TestCase):
    def _client(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("127.0.0.1", 0))
        sock.settimeout(0.6)
        self.addCleanup(sock.close)
        return sock

    def test_loopback_echo_exact_payload(self):
        with LocalEchoServer() as echo, running_proxy(echo.address) as proxy:
            client = self._client()
            content = bytes(range(256)) + b"\x00" * 32
            client.sendto(content, proxy.listen_address)
            self.assertEqual(client.recv(65535), content)
            report = proxy.snapshot()
            self.assertEqual(report["up"]["delivered"], 1)
            self.assertEqual(report["down"]["delivered"], 1)
            self.assertEqual(report["up"]["bytes_delivered"], len(content))
            self.assertEqual(report["down"]["bytes_delivered"], len(content))

    def test_empty_datagram_remains_empty(self):
        with LocalEchoServer() as echo, running_proxy(echo.address) as proxy:
            c = self._client()
            c.sendto(b"", proxy.listen_address)
            self.assertEqual(c.recv(5), b"")

    def test_multiple_clients_have_independent_server_endpoints(self):
        with LocalEchoServer() as echo, running_proxy(echo.address) as proxy:
            a, b = self._client(), self._client()
            a.sendto(b"from a", proxy.listen_address)
            b.sendto(b"from b", proxy.listen_address)
            self.assertEqual(a.recv(128), b"from a")
            self.assertEqual(b.recv(128), b"from b")
            self.assertEqual(len(proxy.sessions), 2)
            self.assertEqual(len({address for address, _ in echo.seen}), 2)

    def test_upstream_drop(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, upstream=sim.Impairment(loss_percent=100)) as proxy:
            c = self._client()
            c.settimeout(0.2)
            c.sendto(b"no", proxy.listen_address)
            with self.assertRaises(socket.timeout):
                c.recv(10)
            self.assertEqual(echo.seen, [])
            self.assertEqual(proxy.snapshot()["up"]["dropped"], 1)

    def test_downstream_drop(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, downstream=sim.Impairment(loss_percent=100)) as proxy:
            c = self._client()
            c.settimeout(0.2)
            c.sendto(b"hidden", proxy.listen_address)
            with self.assertRaises(socket.timeout):
                c.recv(10)
            self.assertEqual(len(echo.seen), 1)
            self.assertEqual(proxy.snapshot()["down"]["dropped"], 1)

    def test_upstream_duplicate(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, upstream=sim.Impairment(duplicate_percent=100)) as proxy:
            c = self._client()
            c.sendto(b"twice", proxy.listen_address)
            self.assertEqual(c.recv(10), b"twice")
            self.assertEqual(c.recv(10), b"twice")
            self.assertEqual(proxy.snapshot()["up"]["duplicated"], 1)
            self.assertEqual(len(echo.seen), 2)

    def test_downstream_duplicate(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, downstream=sim.Impairment(duplicate_percent=100)) as proxy:
            c = self._client()
            c.sendto(b"dup", proxy.listen_address)
            self.assertEqual(c.recv(10), b"dup")
            self.assertEqual(c.recv(10), b"dup")
            self.assertEqual(proxy.snapshot()["down"]["duplicated"], 1)

    def test_upstream_latency(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, upstream=sim.Impairment(latency_ms=80)) as proxy:
            c = self._client()
            start = time.monotonic()
            c.sendto(b"delayed", proxy.listen_address)
            self.assertEqual(c.recv(20), b"delayed")
            self.assertGreaterEqual(time.monotonic() - start, 0.06)

    def test_downstream_latency(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, downstream=sim.Impairment(latency_ms=80)) as proxy:
            c = self._client()
            start = time.monotonic()
            c.sendto(b"delayed", proxy.listen_address)
            self.assertEqual(c.recv(20), b"delayed")
            self.assertGreaterEqual(time.monotonic() - start, 0.06)

    def test_max_clients_limit_and_counter(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, max_clients=1) as proxy:
            a, b = self._client(), self._client()
            a.sendto(b"first", proxy.listen_address)
            self.assertEqual(a.recv(20), b"first")
            b.settimeout(0.2)
            b.sendto(b"rejected", proxy.listen_address)
            with self.assertRaises(socket.timeout):
                b.recv(20)
            self.assertEqual(proxy.snapshot()["rejected_clients"], 1)
            self.assertEqual(proxy.snapshot()["active_clients"], 1)

    def test_session_timeout_eviction_and_reuse(self):
        with LocalEchoServer() as echo, running_proxy(echo.address, max_clients=1, session_timeout=0.1) as proxy:
            a, b = self._client(), self._client()
            a.sendto(b"first", proxy.listen_address)
            self.assertEqual(a.recv(10), b"first")
            time.sleep(0.22)
            self.assertEqual(proxy.snapshot()["active_clients"], 0)
            b.sendto(b"second", proxy.listen_address)
            self.assertEqual(b.recv(10), b"second")

    def test_large_datagram_without_truncation(self):
        with LocalEchoServer() as echo, running_proxy(echo.address) as proxy:
            c = self._client()
            payload = (b"abcxyz!" * 9000)[:60000]
            c.sendto(payload, proxy.listen_address)
            self.assertEqual(c.recv(65000), payload)

    def test_rejected_session_parameters(self):
        for arg in ({"max_clients": 0}, {"max_clients": 10001}, {"session_timeout": 0}, {"session_timeout": 86401}):
            with self.subTest(arg=arg), self.assertRaises(ValueError):
                sim.UDPNetworkSimulator(("127.0.0.1", 1234), **arg)

    def test_invalid_ports(self):
        with self.assertRaises(ValueError):
            sim.UDPNetworkSimulator(("127.0.0.1", 0))
        with self.assertRaises(ValueError):
            sim.UDPNetworkSimulator(("127.0.0.1", 65536))
        with self.assertRaises(ValueError):
            sim.UDPNetworkSimulator(("127.0.0.1", 44), listen=("127.0.0.1", -1))

    def test_pending_limit_drops_excess_datagrams(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 12345), upstream=sim.Impairment(latency_ms=100), max_pending=1) as proxy:
            session = proxy._get_session(("127.0.0.1", 11111), proxy.now())
            proxy._enqueue("up", session, b"one", proxy.now())
            proxy._enqueue("up", session, b"two", proxy.now())
            self.assertEqual(proxy.snapshot()["up"]["dropped"], 1)
            self.assertEqual(proxy.snapshot()["queued_datagrams"], 1)

    def test_pending_limit_counts_partial_duplicate(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 12345), upstream=sim.Impairment(duplicate_percent=100), max_pending=1) as proxy:
            session = proxy._get_session(("127.0.0.1", 11111), proxy.now())
            proxy._enqueue("up", session, b"one", proxy.now())
            self.assertEqual(proxy.snapshot()["up"]["duplicated"], 0)
            self.assertEqual(proxy.snapshot()["up"]["scheduled"], 1)
            self.assertEqual(proxy.snapshot()["up"]["dropped"], 1)

    def test_timeout_does_not_expire_session_with_delayed_packet(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 12345), upstream=sim.Impairment(latency_ms=10000), session_timeout=0.1) as proxy:
            now = proxy.now()
            session = proxy._get_session(("127.0.0.1", 11111), now)
            proxy._enqueue("up", session, b"queued", now)
            proxy._expire(now + 0.5)
            self.assertEqual(proxy.snapshot()["active_clients"], 1)

    def test_bind_target_loop_is_rejected(self):
        c = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        c.bind(("127.0.0.1", 0))
        port = c.getsockname()[1]
        c.close()
        with self.assertRaises(ValueError):
            sim.UDPNetworkSimulator(("127.0.0.1", port), listen=("127.0.0.1", port))
        with self.assertRaises(ValueError):
            sim.UDPNetworkSimulator(("127.0.0.1", port), listen=("0.0.0.0", port))

    def test_max_pending_validation(self):
        for invalid in (-1, 0, 1000001):
            with self.assertRaises(ValueError):
                sim.UDPNetworkSimulator(("127.0.0.1", 12345), max_pending=invalid)


    def test_session_creation_socket_failure_is_not_fatal(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 20001)) as proxy:
            with patch.object(sim.socket, "socket", side_effect=OSError("no fds")):
                self.assertIsNone(proxy._get_session(("127.0.0.1", 20123), proxy.now()))
            self.assertEqual(proxy.rejected_clients, 1)
            self.assertEqual(proxy.snapshot()["active_clients"], 0)

    def test_session_connect_error_does_not_crash_proxy(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 20001)) as proxy:
            class FailingUpstream:
                closed = False

                def connect(self, target):
                    raise OSError("network down")

                def close(self):
                    self.closed = True

            upstream = FailingUpstream()
            with patch.object(sim.socket, "socket", return_value=upstream):
                self.assertIsNone(proxy._get_session(("127.0.0.1", 20123), proxy.now()))
            self.assertTrue(upstream.closed)
            self.assertEqual(proxy.rejected_clients, 1)
            self.assertEqual(proxy.snapshot()["active_clients"], 0)

    def test_snapshot_has_no_payloads(self):
        with LocalEchoServer() as echo, running_proxy(echo.address) as proxy:
            c = self._client()
            c.sendto(b"private-secret-data", proxy.listen_address)
            self.assertEqual(c.recv(50), b"private-secret-data")
            self.assertNotIn("private-secret-data", json.dumps(proxy.snapshot()))

    def test_context_manager_closes_and_run_once_rejects_closed(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 20001)) as proxy:
            addr = proxy.listen_address
        self.assertTrue(proxy.closed)
        self.assertEqual(proxy.snapshot()["listen"], None)
        with self.assertRaises(RuntimeError):
            proxy.run_once()
        proxy.close()

    def test_run_once_rejects_negative_wait(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 20001)) as proxy:
            with self.assertRaises(ValueError):
                proxy.run_once(-1)

    def test_queue_deadline_keeps_order(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 20001), upstream=sim.Impairment(latency_ms=200)) as proxy:
            session = proxy._get_session(("127.0.0.1", 10000), proxy.now())
            proxy._enqueue("up", session, b"one", proxy.now())
            proxy._enqueue("up", session, b"two", proxy.now())
            self.assertEqual([q.payload for q in proxy.pending], [b"one", b"two"])
            self.assertEqual(proxy.snapshot()["up"]["scheduled"], 2)

    def test_expired_queue_does_not_send_on_reused_address(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 20001), upstream=sim.Impairment(latency_ms=100)) as proxy:
            now = proxy.now()
            s = proxy._get_session(("127.0.0.1", 11111), now)
            proxy._enqueue("up", s, b"old", now)
            # Simulate an externally closed session while a delayed packet exists.
            proxy.sessions.pop(s.address)
            proxy.selector.unregister(s.upstream)
            s.upstream.close()
            replacement = proxy._get_session(("127.0.0.1", 11111), now + 101)
            self.assertIsNot(s, replacement)
            proxy._deliver_due(now + 102)
            self.assertEqual(proxy.snapshot()["up"]["dropped"], 1)

    def test_unknown_upstream_session_ignored(self):
        with sim.UDPNetworkSimulator(("127.0.0.1", 20001)) as proxy:
            self.assertEqual(proxy.snapshot()["down"]["received"], 0)


class CLITests(unittest.TestCase):

    def test_main_direct_zero_impairement_and_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = str(Path(tmp) / "stats.json")
            with patch.object(sim.UDPNetworkSimulator, "serve", lambda self, stop: None):
                with contextlib.redirect_stdout(io.StringIO()) as stdout:
                    status = sim.main(["--target-port", "12345", "--listen-port", "0", "--stats-file", report])
            self.assertEqual(status, 0)
            records = [json.loads(line) for line in stdout.getvalue().splitlines()]
            self.assertEqual(len(records), 2)
            self.assertEqual(records[0]["event"], "listening")
            self.assertEqual(records[1]["up"]["received"], 0)
            self.assertEqual(records[1], json.loads(Path(report).read_text()))

    def test_main_direct_invalid_options_return_two(self):
        with contextlib.redirect_stderr(io.StringIO()) as stderr:
            status = sim.main(["--target-port", "12345", "--max-pending", "0"])
        self.assertEqual(status, 2)
        self.assertIn("max_pending", stderr.getvalue())

    def test_main_direct_binding_failure_returns_two(self):
        a = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        a.bind(("127.0.0.1", 0))
        port = a.getsockname()[1]
        try:
            with contextlib.redirect_stderr(io.StringIO()) as stderr:
                status = sim.main(["--target-port", "12345", "--listen-port", str(port)])
            self.assertEqual(status, 2)
            self.assertIn("multiplayer_network_sim:", stderr.getvalue())
        finally:
            a.close()

    def test_help(self):
        res = subprocess.run([sys.executable, str(SCRIPT), "--help"], text=True, capture_output=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("--up-loss", res.stdout)
        self.assertIn("--down-jitter-ms", res.stdout)

    def test_missing_required_target_port(self):
        res = subprocess.run([sys.executable, str(SCRIPT)], text=True, capture_output=True)
        self.assertEqual(res.returncode, 2)
        self.assertIn("target-port", res.stderr)

    def test_invalid_loss_is_reported(self):
        res = subprocess.run([sys.executable, str(SCRIPT), "--target-port", "12345", "--up-loss", "101"], text=True, capture_output=True)
        self.assertEqual(res.returncode, 2)
        self.assertIn("loss_percent", res.stderr)

    def test_invalid_target_name_is_reported(self):
        res = subprocess.run([sys.executable, str(SCRIPT), "--target-port", "12345", "--target-host", "not-an-ip.invalid"], text=True, capture_output=True)
        self.assertEqual(res.returncode, 2)
        self.assertIn("multiplayer_network_sim", res.stderr)

    def test_main_runs_and_emits_json_statistics_after_sigterm(self):
        with LocalEchoServer() as echo, tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.json"
            p = subprocess.Popen([sys.executable, "-u", str(SCRIPT), "--target-port", str(echo.address[1]), "--listen-port", "0", "--stats-file", str(output)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                first = p.stdout.readline()
                record = json.loads(first)
                self.assertEqual(record["event"], "listening")
                c = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                c.settimeout(1)
                with c:
                    c.sendto(b"hello", tuple(record["listen"]))
                    self.assertEqual(c.recv(20), b"hello")
                p.terminate()
                tail, err = p.communicate(timeout=3)
                self.assertEqual(p.returncode, 0, err)
                report = json.loads(tail.strip())
                self.assertEqual(report["up"]["received"], 1)
                self.assertEqual(json.loads(output.read_text()), report)
            finally:
                if p.poll() is None:
                    p.kill()
                    p.communicate()



class ProfileCLITests(unittest.TestCase):
    def parse(self, *options):
        return sim.make_parser().parse_args(["--target-port", "2456", *options])

    def test_profile_selection_applies_to_both_directions(self):
        args = self.parse("--preset", "mobile")
        self.assertEqual(sim.policy_from_args(args, "up").latency_ms, 100)
        self.assertEqual(sim.policy_from_args(args, "down").latency_ms, 100)
        self.assertEqual(sim.policy_from_args(args, "up").loss_percent, 4)

    def test_explicit_upstream_override_preserves_downstream_preset(self):
        args = self.parse("--preset", "severe", "--up-loss", "0", "--up-latency-ms", "7")
        self.assertEqual(sim.policy_from_args(args, "up").loss_percent, 0)
        self.assertEqual(sim.policy_from_args(args, "up").latency_ms, 7)
        self.assertEqual(sim.policy_from_args(args, "down").loss_percent, 12)
        self.assertEqual(sim.policy_from_args(args, "down").latency_ms, 250)

    def test_default_profile_is_backwards_compatible(self):
        args = self.parse()
        self.assertEqual(sim.policy_from_args(args, "up"), sim.Impairment())
        self.assertEqual(sim.policy_from_args(args, "down"), sim.Impairment())

    def test_cli_rejects_misspelled_profile(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                self.parse("--preset", "wi-fi")
        self.assertEqual(error.exception.code, 2)

    def test_invalid_direction_fails(self):
        args = self.parse("--preset", "wifi")
        with self.assertRaises(ValueError):
            sim.policy_from_args(args, "invalid")

    def test_cli_invalid_override_fails_before_listening(self):
        args = self.parse("--preset", "wifi", "--up-jitter-ms", "-1")
        with self.assertRaises(ValueError):
            sim.policy_from_args(args, "up")

if __name__ == "__main__":
    unittest.main()
