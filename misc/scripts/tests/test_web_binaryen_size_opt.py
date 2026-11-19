"""Web post-link wasm-opt regression tests; no Emscripten or SCons needed."""
from pathlib import Path
import ast
import subprocess
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]


class WebOptimizerContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helpers = (ROOT / "platform/web/emscripten_helpers.py").read_text()
        cls.detect = (ROOT / "platform/web/detect.py").read_text()
        cls.scsub = (ROOT / "platform/web/SCsub").read_text()

    def test_option_is_explicit_and_disabled_by_default(self):
        self.assertIn('BoolVariable("optimize_wasm"', self.detect)
        self.assertIn('after linking", False)', self.detect)
        self.assertIn('if env["optimize_wasm"]:', self.detect)
        self.assertIn('env.Append(BUILDERS={"OptimizeWASM":', self.detect)

    def test_packaging_uses_optimized_main_and_side_modules(self):
        self.assertIn('main_wasm = env.OptimizeWASM(main_wasm)', self.scsub)
        self.assertIn('side_wasm = env.OptimizeWASM(side_wasm)', self.scsub)
        self.assertIn('env.CreateTemplateZip(js_wrapped, main_wasm, side_wasm)', self.scsub)
        self.assertIn('if side_wasm is not None:', self.scsub)

    @staticmethod
    def load_function():
        src = (ROOT / "platform/web/emscripten_helpers.py").read_text()
        tree = ast.parse(src)
        fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "run_optimize_wasm")
        class UserError(Exception):
            pass
        namespace = {"UserError": UserError, "WhereIs": lambda name: "/usr/bin/wasm-opt", "subprocess": subprocess}
        exec(compile(ast.Module(body=[fn], type_ignores=[]), "<wasm-opt>", "exec"), namespace)
        return namespace, UserError

    def test_optimized_binary_does_not_overwrite_input(self):
        env, _ = self.load_function()
        with mock.patch.object(subprocess, "run") as runner:
            env["run_optimize_wasm"](["out.opt.wasm"], ["in.wasm"], {})
        runner.assert_called_once_with(
            ["/usr/bin/wasm-opt", "in.wasm", "--post-emscripten", "-Oz", "-o", "out.opt.wasm"],
            check=True,
        )

    def test_binaryen_is_required_and_errors_are_propagated(self):
        env, UserError = self.load_function()
        env["WhereIs"] = lambda _: None
        with self.assertRaises(UserError):
            env["run_optimize_wasm"](["out.opt.wasm"], ["in.wasm"], {})
        env["WhereIs"] = lambda _: "/usr/bin/wasm-opt"
        with mock.patch.object(subprocess, "run", side_effect=subprocess.CalledProcessError(1, "wasm-opt")):
            with self.assertRaises(subprocess.CalledProcessError):
                env["run_optimize_wasm"](["out.opt.wasm"], ["in.wasm"], {})

    def test_builder_rejects_ambiguous_outputs(self):
        env, UserError = self.load_function()
        with self.assertRaises(UserError):
            env["run_optimize_wasm"](["a.opt.wasm", "b.opt.wasm"], ["in.wasm"], {})


if __name__ == "__main__":
    unittest.main()
