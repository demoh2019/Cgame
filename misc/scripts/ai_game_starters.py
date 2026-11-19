#!/usr/bin/env python3
"""Generate deterministic, dependency-free Godot 4 starter game projects offline."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
from textwrap import dedent


class StarterError(Exception):
    """Unsafe destination or failed project creation."""


TEMPLATES = ("platformer", "topdown", "fps3d")
DESTINATION_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}\Z")
RESERVED_NAMES = {"CON", "PRN", "AUX", "NUL"} | {f"COM{i}" for i in range(1, 10)} | {f"LPT{i}" for i in range(1, 10)}


def _text(content: str) -> str:
    return dedent(content).lstrip("\n").rstrip() + "\n"


PLATFORMER = _text('''
    extends Node2D

    const SPEED := 310.0
    const JUMP_SPEED := -560.0
    const GRAVITY := 1250.0
    var player: CharacterBody2D
    var status: Label
    var won := false
    var platforms: Array[Rect2] = []

    func _ready() -> void:
        player = CharacterBody2D.new()
        player.name = "Player"
        player.position = Vector2(100, 480)
        var collision := CollisionShape2D.new()
        var shape := RectangleShape2D.new()
        shape.size = Vector2(34, 48)
        collision.shape = shape
        player.add_child(collision)
        add_child(player)
        _add_platform(Vector2(576, 616), Vector2(1152, 112))
        _add_platform(Vector2(385, 466), Vector2(180, 24))
        _add_platform(Vector2(720, 400), Vector2(180, 24))
        var overlay := CanvasLayer.new()
        add_child(overlay)
        status = Label.new()
        status.position = Vector2(24, 18)
        status.text = "Platformer: arrows to move, Space/Enter to jump; reach the gold flag"
        overlay.add_child(status)

    func _add_platform(center: Vector2, size: Vector2) -> void:
        platforms.append(Rect2(center - size / 2.0, size))
        var body := StaticBody2D.new()
        body.position = center
        var collision := CollisionShape2D.new()
        var shape := RectangleShape2D.new()
        shape.size = size
        collision.shape = shape
        body.add_child(collision)
        add_child(body)

    func _physics_process(delta: float) -> void:
        if won:
            return
        var move_axis := Input.get_axis("ui_left", "ui_right")
        player.velocity.x = move_axis * SPEED
        if not player.is_on_floor():
            player.velocity.y += GRAVITY * delta
        elif Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up"):
            player.velocity.y = JUMP_SPEED
        player.move_and_slide()
        if player.position.y > 820:
            player.position = Vector2(100, 480)
            player.velocity = Vector2.ZERO
        if player.position.x > 1070 and player.position.y < 555:
            won = true
            status.text = "YOU WIN! Restart the scene to play again."
        queue_redraw()

    func _draw() -> void:
        draw_rect(Rect2(0, 0, 1152, 648), Color(0.07, 0.13, 0.22))
        for platform in platforms:
            draw_rect(platform, Color(0.25, 0.68, 0.43))
        draw_rect(Rect2(player.position - Vector2(17, 24), Vector2(34, 48)), Color(0.37, 0.72, 1.0))
        draw_rect(Rect2(1090, 470, 7, 90), Color.WHITE)
        draw_colored_polygon(PackedVector2Array([Vector2(1097, 470), Vector2(1130, 482), Vector2(1097, 495)]), Color(1.0, 0.83, 0.18))
''')

TOPDOWN = _text('''
    extends Node2D

    const SPEED := 260.0
    var player: CharacterBody2D
    var status: Label
    var walls: Array[Rect2] = []
    var pickups := [Vector2(280, 150), Vector2(620, 500), Vector2(880, 180)]
    var collected := [false, false, false]
    var won := false

    func _ready() -> void:
        player = CharacterBody2D.new()
        player.name = "Player"
        player.position = Vector2(90, 350)
        var collision := CollisionShape2D.new()
        var shape := CircleShape2D.new()
        shape.radius = 18.0
        collision.shape = shape
        player.add_child(collision)
        add_child(player)
        _wall(Vector2(575, 80), Vector2(1150, 24))
        _wall(Vector2(575, 635), Vector2(1150, 24))
        _wall(Vector2(12, 352), Vector2(24, 600))
        _wall(Vector2(1138, 352), Vector2(24, 600))
        _wall(Vector2(470, 305), Vector2(65, 300))
        _wall(Vector2(790, 400), Vector2(260, 45))
        var overlay := CanvasLayer.new()
        add_child(overlay)
        status = Label.new()
        status.position = Vector2(24, 18)
        status.text = "Top-down: arrows to move, collect 3 stars, reach the cyan exit"
        overlay.add_child(status)

    func _wall(center: Vector2, size: Vector2) -> void:
        walls.append(Rect2(center - size / 2.0, size))
        var body := StaticBody2D.new()
        body.position = center
        var collider := CollisionShape2D.new()
        var shape := RectangleShape2D.new()
        shape.size = size
        collider.shape = shape
        body.add_child(collider)
        add_child(body)

    func _physics_process(_delta: float) -> void:
        if won:
            return
        player.velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * SPEED
        player.move_and_slide()
        for i in range(pickups.size()):
            if not collected[i] and player.position.distance_to(pickups[i]) < 34.0:
                collected[i] = true
        if not collected.has(false) and player.position.distance_to(Vector2(1050, 540)) < 48.0:
            won = true
            status.text = "YOU WIN! Restart the scene to play again."
        queue_redraw()

    func _draw() -> void:
        draw_rect(Rect2(0, 0, 1152, 648), Color(0.08, 0.12, 0.17))
        for wall in walls:
            draw_rect(wall, Color(0.44, 0.47, 0.58))
        draw_circle(Vector2(1050, 540), 36.0, Color(0.15, 0.9, 0.85))
        for i in range(pickups.size()):
            if not collected[i]:
                draw_circle(pickups[i], 13.0, Color(1.0, 0.84, 0.2))
        draw_circle(player.position, 18.0, Color(0.35, 0.74, 1.0))
''')

FPS3D = _text('''
    extends Node3D

    const SPEED := 6.5
    const JUMP_SPEED := 5.0
    const GRAVITY := 15.0
    var player: CharacterBody3D
    var head: Node3D
    var status: Label
    var won := false

    func _ready() -> void:
        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-55, -35, 0)
        add_child(sun)
        _box(Vector3(0, -0.6, 0), Vector3(25, 1, 25), Color(0.22, 0.42, 0.36))
        _box(Vector3(-4, 1, -4), Vector3(2, 2, 2), Color(0.58, 0.45, 0.32))
        _box(Vector3(4, 1, -8), Vector3(3, 2, 2), Color(0.58, 0.45, 0.32))
        _box(Vector3(0, 1, -12), Vector3(25, 2, 0.4), Color(0.4, 0.44, 0.52))
        player = CharacterBody3D.new()
        player.name = "Player"
        player.position = Vector3(0, 1.2, 8)
        var collider := CollisionShape3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.35
        capsule.height = 1.8
        collider.shape = capsule
        player.add_child(collider)
        head = Node3D.new()
        head.position.y = 0.65
        player.add_child(head)
        var camera := Camera3D.new()
        camera.current = true
        head.add_child(camera)
        add_child(player)
        var goal := MeshInstance3D.new()
        goal.name = "Goal"
        goal.position = Vector3(0, 0.8, -10)
        var mesh := SphereMesh.new()
        mesh.radius = 0.8
        mesh.height = 1.6
        goal.mesh = mesh
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(0.25, 0.9, 0.7)
        goal.material_override = material
        add_child(goal)
        var overlay := CanvasLayer.new()
        add_child(overlay)
        status = Label.new()
        status.position = Vector2(24, 18)
        status.text = "FPS 3D: arrows move, Space jumps, click to look; reach the green orb"
        overlay.add_child(status)

    func _box(center: Vector3, size: Vector3, color: Color) -> void:
        var body := StaticBody3D.new()
        body.position = center
        var collider := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        collider.shape = shape
        body.add_child(collider)
        var visual := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = size
        visual.mesh = mesh
        var material := StandardMaterial3D.new()
        material.albedo_color = color
        visual.material_override = material
        body.add_child(visual)
        add_child(body)

    func _input(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.pressed:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
        elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            player.rotate_y(-event.relative.x * 0.002)
            head.rotate_x(-event.relative.y * 0.002)
            head.rotation.x = clamp(head.rotation.x, -1.25, 1.25)

    func _physics_process(delta: float) -> void:
        if won:
            return
        if not player.is_on_floor():
            player.velocity.y -= GRAVITY * delta
        elif Input.is_action_just_pressed("ui_accept"):
            player.velocity.y = JUMP_SPEED
        var axis := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        var direction := (player.transform.basis * Vector3(axis.x, 0, axis.y)).normalized()
        player.velocity.x = direction.x * SPEED
        player.velocity.z = direction.z * SPEED
        player.move_and_slide()
        if player.position.y < -10:
            player.position = Vector3(0, 1.2, 8)
            player.velocity = Vector3.ZERO
        if player.position.distance_to(Vector3(0, 1.2, -10)) < 1.8:
            won = true
            status.text = "YOU WIN! Restart the scene to play again."
''')


SCRIPTS = {"platformer": PLATFORMER, "topdown": TOPDOWN, "fps3d": FPS3D}
CONTROLS = {
    "platformer": ["ui_left", "ui_right", "ui_up", "ui_accept"],
    "topdown": ["ui_left", "ui_right", "ui_up", "ui_down"],
    "fps3d": ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept"],
}


def files_for(template: str, project_name: str) -> dict[str, str]:
    """Return reproducible UTF-8 text files without writing to the filesystem."""
    if template not in TEMPLATES:
        raise StarterError(f"unknown template: {template}")
    if not isinstance(project_name, str) or not 1 <= len(project_name) <= 80 or any(ord(c) < 32 or ord(c) == 127 for c in project_name):
        raise StarterError("project name must be 1-80 printable characters")
    name_literal = json.dumps(project_name, ensure_ascii=False)
    settings = _text(f'''
        config_version=5

        [application]

        config/name={name_literal}
        run/main_scene="res://main.tscn"

        [display]

        window/size/viewport_width=1152
        window/size/viewport_height=648

        [rendering]

        renderer/rendering_method="gl_compatibility"
        renderer/rendering_method.mobile="gl_compatibility"
    ''')
    scene_type = "Node3D" if template == "fps3d" else "Node2D"
    scene = _text(f'''
        [gd_scene load_steps=2 format=3]

        [ext_resource type="Script" path="res://game.gd" id="1"]

        [node name="Main" type="{scene_type}"]
        script = ExtResource("1")
    ''')
    guide = _text(f'''
        # {project_name}

        Generated offline from the Cgame AI Game Builder {template} starter.
        Open project.godot in Godot 4 and press F6 or F5 to play the main scene.
        The game is intentionally small, deterministic, and has no downloaded assets.
        It is a foundation for human-reviewed AI edits, not a completed game.
        Controls use Godot's built-in ui_* actions (arrow keys; Space/Enter to jump).
        FPS: click to capture the pointer, Escape to release it.
        Edit game.gd to change mechanics and main.tscn to change the entry scene.
    ''')
    files = {"project.godot": settings, "main.tscn": scene, "game.gd": SCRIPTS[template], "README.md": guide}
    recipe = {"schema_version": 1, "template": template, "main_scene": "res://main.tscn",
              "script": "res://game.gd", "controls": CONTROLS[template],
              "editable_files": ["main.tscn", "game.gd"],
              "sha256": {path: hashlib.sha256(value.encode("utf-8")).hexdigest() for path, value in sorted(files.items())}}
    files["ai_recipe.json"] = json.dumps(recipe, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    return files


def create_project(destination: Path, template: str, project_name: str) -> dict:
    """Create a *new* project directory; never overwrite an existing path."""
    destination = Path(destination)
    if (".." in destination.parts or not DESTINATION_NAME.fullmatch(destination.name)
            or destination.name.upper() in RESERVED_NAMES):
        raise StarterError("destination must have a portable ASCII folder name (letters, digits, _ and -)")
    parent = destination.parent
    if parent.is_symlink() or not parent.is_dir():
        raise StarterError("destination parent must be an existing real directory")
    files = files_for(template, project_name)
    # Atomic exclusive directory creation: fail safely if a project exists.
    try:
        destination.mkdir(mode=0o755, exist_ok=False)
    except FileExistsError as exc:
        raise StarterError("destination already exists; refusing to overwrite") from exc
    try:
        for filename, body in sorted(files.items()):
            with (destination / filename).open("x", encoding="utf-8", newline="\n") as output:
                output.write(body)
    except (OSError, UnicodeError):
        # Cleanup only a newly created directory; no preexisting files are modified.
        shutil.rmtree(destination)
        raise
    return {"template": template, "directory": str(destination), "files": sorted(files)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, choices=TEMPLATES)
    parser.add_argument("--output", type=Path, required=True, help="Nonexistent destination directory")
    parser.add_argument("--project-name", default="My AI Starter")
    args = parser.parse_args(argv)
    try:
        result = create_project(args.output, args.template, args.project_name)
    except (StarterError, OSError, UnicodeError) as error:
        print(f"ai_game_starters: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
