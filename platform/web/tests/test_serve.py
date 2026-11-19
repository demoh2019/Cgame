"""Regression tests for the Python Web export preview helper.

Run without a Godot build:
python3 -m unittest discover -s platform/web/tests -p test_serve.py -v
"""

import importlib.util
import io
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, call, patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "serve.py"
SPEC = importlib.util.spec_from_file_location("godot_web_serve", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
web_serve = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(web_serve)


class ResponseHeaderTests(unittest.TestCase):
    def test_isolation_and_cors_headers(self):
        handler = object.__new__(web_serve.CORSRequestHandler)
        with patch.object(web_serve.CORSRequestHandler, "send_header") as headers:
            with patch.object(web_serve.SimpleHTTPRequestHandler, "end_headers") as finish:
                handler.end_headers()
        self.assertEqual(
            headers.call_args_list,
            [
                call("Cross-Origin-Opener-Policy", "same-origin"),
                call("Cross-Origin-Embedder-Policy", "require-corp"),
                call("Access-Control-Allow-Origin", "*"),
            ],
        )
        finish.assert_called_once_with()


class BrowserOpenerTests(unittest.TestCase):
    def test_linux_uses_xdg_open(self):
        with patch.object(web_serve.sys, "platform", "linux"):
            with patch.object(web_serve.subprocess, "call") as run:
                web_serve.shell_open("http://127.0.0.1:8080")
        run.assert_called_once_with(["xdg-open", "http://127.0.0.1:8080"])

    def test_macos_uses_open(self):
        with patch.object(web_serve.sys, "platform", "darwin"):
            with patch.object(web_serve.subprocess, "call") as run:
                web_serve.shell_open("https://localhost:8443")
        run.assert_called_once_with(["open", "https://localhost:8443"])

    def test_windows_uses_startfile(self):
        with patch.object(web_serve.sys, "platform", "win32"):
            with patch.object(web_serve.os, "startfile", create=True) as start:
                web_serve.shell_open("http://127.0.0.1:8060")
        start.assert_called_once_with("http://127.0.0.1:8060")


class CertificateTests(unittest.TestCase):
    def test_provided_certificate_does_not_generate_new_one(self):
        original_socket = object()
        server = SimpleNamespace(socket=original_socket)
        ssl_context = MagicMock()
        with patch.object(web_serve.ssl, "SSLContext", return_value=ssl_context):
            with patch.object(web_serve, "generate_snakeoil") as generate:
                web_serve.ssl_wrap_socket(server, "key.pem", "cert.pem")
        generate.assert_not_called()
        ssl_context.load_cert_chain.assert_called_once_with(certfile="cert.pem", keyfile="key.pem")
        ssl_context.wrap_socket.assert_called_once_with(original_socket, server_side=True)
        self.assertIs(server.socket, ssl_context.wrap_socket.return_value)

    def test_generated_certificate_files_removed_after_loading(self):
        server = SimpleNamespace(socket=object())
        ssl_context = MagicMock()
        paths = []

        def verify_chain(*, certfile, keyfile):
            paths.extend([Path(certfile), Path(keyfile)])
            self.assertEqual(Path(certfile).read_bytes(), b"FAKE CERT")
            self.assertEqual(Path(keyfile).read_bytes(), b"FAKE KEY")

        ssl_context.load_cert_chain.side_effect = verify_chain
        with patch.object(web_serve.ssl, "SSLContext", return_value=ssl_context):
            with patch.object(web_serve, "generate_snakeoil", return_value=(b"FAKE KEY", b"FAKE CERT")):
                web_serve.ssl_wrap_socket(server, "", "")
        self.assertEqual(len(paths), 2)
        self.assertTrue(all(not path.exists() for path in paths))

    def test_failed_certificate_loading_removes_temporary_secrets(self):
        server = SimpleNamespace(socket=object())
        ssl_context = MagicMock()
        paths = []

        def fail_chain(*, certfile, keyfile):
            paths.extend([Path(certfile), Path(keyfile)])
            self.assertTrue(all(path.is_file() for path in paths))
            raise ValueError("invalid generated certificate")

        ssl_context.load_cert_chain.side_effect = fail_chain
        with patch.object(web_serve.ssl, "SSLContext", return_value=ssl_context):
            with patch.object(web_serve, "generate_snakeoil", return_value=(b"KEY", b"CERT")):
                with self.assertRaisesRegex(ValueError, "invalid generated certificate"):
                    web_serve.ssl_wrap_socket(server, "", "")
        self.assertEqual(len(paths), 2)
        self.assertTrue(all(not path.exists() for path in paths))

    def test_partial_key_or_cert_uses_ephemeral_pair(self):
        for key, cert in [("custom.key", ""), ("", "custom.pem")]:
            with self.subTest(key=key, cert=cert):
                server = SimpleNamespace(socket=object())
                ssl_context = MagicMock()
                with patch.object(web_serve.ssl, "SSLContext", return_value=ssl_context):
                    with patch.object(web_serve, "generate_snakeoil", return_value=(b"KEY", b"CERT")):
                        web_serve.ssl_wrap_socket(server, key, cert)
                ssl_context.load_cert_chain.assert_called_once()


class ServerLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.server = MagicMock()
        self.server.server_port = 8061
        self.server.socket = object()
        self.server_factory = patch.object(web_serve, "DualStackServer", return_value=self.server)
        self.chdir_patch = patch.object(web_serve.os, "chdir")
        self.factory = self.server_factory.start()
        self.chdir = self.chdir_patch.start()
        self.addCleanup(self.server_factory.stop)
        self.addCleanup(self.chdir_patch.stop)

    def test_http_does_not_invoke_tls(self):
        with patch.object(web_serve, "ssl_wrap_socket") as wrap:
            with patch.object(web_serve, "shell_open") as browser:
                web_serve.serve("/game", 8061, False, False)
        wrap.assert_not_called()
        browser.assert_not_called()
        self.chdir.assert_called_once_with("/game")
        self.factory.assert_called_once_with(("", 8061), web_serve.CORSRequestHandler)
        self.server.serve_forever.assert_called_once_with()
        self.server.server_close.assert_called_once_with()

    def test_https_uses_provided_certificate(self):
        with patch.object(web_serve, "ssl_wrap_socket") as wrap:
            web_serve.serve("/game", 8443, True, False, key="key.pem", cert="cert.pem")
        wrap.assert_called_once_with(self.server, "key.pem", "cert.pem")
        self.server.server_close.assert_called_once_with()

    def test_http_browser_uses_loopback(self):
        with patch.object(web_serve, "shell_open") as browser:
            web_serve.serve("/game", 8061, False, True)
        browser.assert_called_once_with("http://127.0.0.1:8061")

    def test_https_browser_uses_https_scheme(self):
        with patch.object(web_serve, "ssl_wrap_socket"):
            with patch.object(web_serve, "shell_open") as browser:
                web_serve.serve("/game", 8061, True, True)
        browser.assert_called_once_with("https://127.0.0.1:8061")

    def test_port_zero_uses_actual_bound_port_in_url(self):
        with patch.object(web_serve, "shell_open") as browser:
            web_serve.serve("/game", 0, False, True)
        browser.assert_called_once_with("http://127.0.0.1:8061")

    def test_keyboard_interrupt_closes_server(self):
        self.server.serve_forever.side_effect = KeyboardInterrupt()
        with redirect_stdout(io.StringIO()):
            web_serve.serve("/game", 8061, False, False)
        self.server.server_close.assert_called_once_with()

    def test_server_exception_still_closes_server(self):
        self.server.serve_forever.side_effect = RuntimeError("server error")
        with self.assertRaisesRegex(RuntimeError, "server error"):
            web_serve.serve("/game", 8061, False, False)
        self.server.server_close.assert_called_once_with()

    def test_tls_setup_failure_closes_server(self):
        with patch.object(web_serve, "ssl_wrap_socket", side_effect=ValueError("bad certificate")):
            with self.assertRaisesRegex(ValueError, "bad certificate"):
                web_serve.serve("/game", 8061, True, False)
        self.server.server_close.assert_called_once_with()

    def test_browser_start_failure_closes_server(self):
        with patch.object(web_serve, "shell_open", side_effect=OSError("browser missing")):
            with self.assertRaisesRegex(OSError, "browser missing"):
                web_serve.serve("/game", 8061, False, True)
        self.server.server_close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
