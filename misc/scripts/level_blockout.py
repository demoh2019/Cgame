#!/usr/bin/env python3
"""Render an offline JSON 3D level blockout into a Godot 4 text scene."""

import argparse
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile

MAX_BLOCKS = 128
IDENTIFIER = re.compile(r"[A-Za-z][A-Za-z0-9_]{0,47}\Z")
HEX = re.compile(r"#[0-9a-fA-F]{6}\Z")


class LevelError(ValueError):
    pass


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise LevelError("Duplicate JSON key: " + key)
        result[key] = value
    return result


def _number(value, positive=False):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise LevelError("Non-finite or non-numeric vector component")
    if positive and not 0.05 <= value <= 1024:
        raise LevelError("Block sizes must be from 0.05 to 1024")
    if not positive and abs(value) > 10000:
        raise LevelError("Position is out of range")
    return float(value)


def _vector(value, positive=False):
    if type(value) is not list or len(value) != 3:
        raise LevelError("Expected a three-component vector")
    return [_number(component, positive) for component in value]


def _fmt(value):
    text = format(value, ".10g")
    return text if "." in text or "e" in text else text + ".0"


def _vec(value):
    return "Vector3(" + ", ".join(_fmt(item) for item in value) + ")"


def _material(value):
    return "Color(" + ", ".join(_fmt(int(value[offset:offset+2], 16) / 255.0)
                                  for offset in (1, 3, 5)) + ", 1.0)"


def validate(spec):
    if type(spec) is not dict or set(spec) != {"version", "name", "blocks"}:
        raise LevelError("Root must have exactly version, name and blocks")
    if type(spec["version"]) is not int or spec["version"] != 1:
        raise LevelError("Unsupported level format")
    name = spec["name"]
    if type(name) is not str or not IDENTIFIER.fullmatch(name):
        raise LevelError("Invalid scene name")
    blocks = spec["blocks"]
    if type(blocks) is not list or not 1 <= len(blocks) <= MAX_BLOCKS:
        raise LevelError("Specify 1 to 128 blocks")
    normalized = []
    names = {name.casefold(), "camera", "sun"}
    for item in blocks:
        if type(item) is not dict or not {"name", "position", "size"} <= set(item) or set(item) - {"name", "position", "size", "color"}:
            raise LevelError("Invalid block fields")
        label = item["name"]
        if type(label) is not str or not IDENTIFIER.fullmatch(label) or label.casefold() in names:
            raise LevelError("Invalid or duplicate block name")
        names.add(label.casefold())
        color = item.get("color", "#718096")
        if type(color) is not str or not HEX.fullmatch(color):
            raise LevelError("Color must be #RRGGBB")
        normalized.append((label, _vector(item["position"]), _vector(item["size"], True), color))
    return name, normalized


def make_scene(spec):
    """All generated nodes/resources are engine built-ins. Never execute source data."""
    name, blocks = validate(spec)
    lines = ["[gd_scene load_steps={} format=3]".format(3 * len(blocks) + 1), ""]
    for index, (_, _, size, color) in enumerate(blocks, 1):
        suffix = "{:03}".format(index)
        lines.extend([
            '[sub_resource type="BoxMesh" id="mesh_{}"]'.format(suffix),
            "size = " + _vec(size), "",
            '[sub_resource type="BoxShape3D" id="shape_{}"]'.format(suffix),
            "size = " + _vec(size), "",
            '[sub_resource type="StandardMaterial3D" id="mat_{}"]'.format(suffix),
            "albedo_color = " + _material(color), "",
        ])
    lines.extend([
        '[node name="{}" type="Node3D"]'.format(name), "",
        '[node name="Camera" type="Camera3D" parent="."]',
        "position = Vector3(0.0, 12.0, 20.0)",
        "rotation_degrees = Vector3(-30.0, 0.0, 0.0)",
        "current = true", "",
        '[node name="Sun" type="DirectionalLight3D" parent="."]',
        "rotation_degrees = Vector3(-55.0, -30.0, 0.0)", "",
    ])
    for index, (label, position, _, _) in enumerate(blocks, 1):
        suffix = "{:03}".format(index)
        lines.extend([
            '[node name="{}" type="StaticBody3D" parent="."]'.format(label),
            "position = " + _vec(position), "",
            '[node name="Visual" type="MeshInstance3D" parent="{}"]'.format(label),
            'mesh = SubResource("mesh_{}")'.format(suffix),
            'material_override = SubResource("mat_{}")'.format(suffix), "",
            '[node name="Collision" type="CollisionShape3D" parent="{}"]'.format(label),
            'shape = SubResource("shape_{}")'.format(suffix), "",
        ])
    return "\n".join(lines)


def read_spec(path):
    if path.is_symlink() or not path.is_file():
        raise LevelError("Input must be a regular JSON file")
    if path.stat().st_size > 512 * 1024:
        raise LevelError("Input must not exceed 512 KiB")
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream, object_pairs_hook=_unique)
    except (ValueError, UnicodeError) as exc:
        raise LevelError("Invalid JSON: {}".format(exc)) from exc


def write_scene(path, text, overwrite=False):
    if path.suffix.lower() != ".tscn" or not path.parent.is_dir():
        raise LevelError("Output must be .tscn in an existing directory")
    if any(segment.is_symlink() for segment in (path, *path.parents)):
        raise LevelError("Symlink in output path")
    if path.exists() and (not overwrite or not path.is_file()):
        raise LevelError("Output exists or is not a regular file")
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".blockout-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        if not overwrite:
            # Hard linking provides no-clobber behavior even when another process creates path.
            os.link(temporary, path)
        else:
            os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args(argv)
    try:
        scene = make_scene(read_spec(args.spec))
        write_scene(args.output, scene, args.overwrite)
        print(json.dumps({"blocks": scene.count('type="StaticBody3D"'), "output": str(args.output)}, sort_keys=True))
        return 0
    except (LevelError, OSError) as exc:
        print("level_blockout: {}".format(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
