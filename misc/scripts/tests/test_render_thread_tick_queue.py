"""Contracts for queueing RenderingServer tick/pre_draw on its own thread (Godot #125355)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "servers/rendering/rendering_server_default.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "servers/rendering/rendering_server_default.h").read_text(encoding="utf-8")


def body(name, next_name):
    start = SOURCE.index(name)
    end = SOURCE.index(next_name, start + len(name))
    return SOURCE[start:end]


class RendererThreadTickContracts(unittest.TestCase):
    def test_tick_dispatches_when_not_on_render_thread(self):
        tick = body("void RenderingServerDefault::tick()",
                    "void RenderingServerDefault::_tick()")
        self.assertIn("Thread::get_caller_id() != server_thread", tick)
        self.assertIn("command_queue.push(this, &RenderingServerDefault::_tick);", tick)
        self.assertIn("_tick();", tick)

    def test_pre_draw_dispatches_when_not_on_render_thread(self):
        function = body("void RenderingServerDefault::pre_draw(",
                        "void RenderingServerDefault::_pre_draw(")
        self.assertIn("Thread::get_caller_id() != server_thread", function)
        self.assertIn("command_queue.push(this, &RenderingServerDefault::_pre_draw, p_will_draw);", function)
        self.assertIn("_pre_draw(p_will_draw);", function)

    def test_private_methods_are_declared(self):
        self.assertIn("void _tick();", HEADER)
        self.assertIn("void _pre_draw(bool p_will_draw);", HEADER)

    def test_tick_updates_canvas_and_scene(self):
        function = body("void RenderingServerDefault::_tick()",
                        "void RenderingServerDefault::pre_draw(")
        self.assertIn("RSG::canvas->tick();", function)
        self.assertIn("RSG::scene->tick();", function)

    def test_pre_draw_updates_scene(self):
        function = body("void RenderingServerDefault::_pre_draw(",
                        "void RenderingServerDefault::",)
        self.assertIn("RSG::scene->pre_draw(p_will_draw);", function)

    def test_tick_does_not_directly_touch_scene_off_thread(self):
        tick = body("void RenderingServerDefault::tick()",
                    "void RenderingServerDefault::_tick()")
        self.assertNotIn("RSG::canvas->tick();", tick)
        self.assertNotIn("RSG::scene->tick();", tick)

    def test_pre_draw_does_not_touch_scene_off_thread(self):
        function = body("void RenderingServerDefault::pre_draw(",
                        "void RenderingServerDefault::_pre_draw(")
        self.assertNotIn("RSG::scene->pre_draw(", function)

    def test_legacy_public_api_remains(self):
        self.assertIn("void RenderingServerDefault::tick()", SOURCE)
        self.assertIn("void RenderingServerDefault::pre_draw(bool p_will_draw)", SOURCE)


if __name__ == "__main__":
    unittest.main()
