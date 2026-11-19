#!/usr/bin/env python3
"""Stress Cgame's asset importer with an isolated deterministic synthetic project.

Measures separately cold and warm editor-import startup, process CPU and peak RSS.
Never edits any files in the real source checkout.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import struct
import sys
import tempfile
import zlib

from run import run_once


def make_png(width: int, height: int, seed: int) -> bytes:
    """Generate an uncompressed-in-memory RGBA image without image packages."""
    rng = random.Random(seed)
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # PNG filter: None
        for x in range(width):
            raw.extend((rng.randrange(256), (x + y + seed) & 255, (x * 7 + seed) & 255, 255))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, level=6))
        + chunk(b"IEND", b"")
    )


def make_project(project: Path, textures: int, scenes: int, seed: int) -> dict[str, int]:
    if textures < 1 or scenes < 1:
        raise ValueError("textures and scenes must be positive")
    (project / "textures").mkdir(parents=True)
    (project / "scripts").mkdir(parents=True)
    (project / "scenes").mkdir(parents=True)
    (project / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="Cgame Import Stress"\n'
        '\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',
        encoding="utf-8",
    )
    for i in range(textures):
        (project / "textures" / ("texture_%05d.png" % i)).write_bytes(
            make_png(96, 96, seed + i))
    for i in range(scenes):
        (project / "scripts" / ("script_%05d.gd" % i)).write_text(
            "extends Node2D\n"
            "var value: int = %d\n"
            "func update_value(delta: int) -> int:\n"
            "\tvalue += delta\n"
            "\treturn value\n" % i,
            encoding="utf-8",
        )
        name = "texture_%05d.png" % (i % textures)
        (project / "scenes" / ("scene_%05d.tscn" % i)).write_text(
            '[gd_scene load_steps=3 format=3]\n\n'
            '[ext_resource type="Texture2D" path="res://textures/%s" id="1"]\n'
            '[ext_resource type="Script" path="res://scripts/script_%05d.gd" id="2"]\n\n'
            '[node name="Root" type="Node2D"]\n'
            'script = ExtResource("2")\n\n'
            '[node name="Sprite" type="Sprite2D" parent="."]\n'
            'texture = ExtResource("1")\n' % (name, i),
            encoding="utf-8",
        )
    return {"textures": textures, "scripts": scenes, "scenes": scenes}


def run_import(binary: str, project: Path, timeout: float, rss: float,
               label: str) -> dict:
    # Render API isn't exercised; the real asset import and editor paths are.
    cmd = [binary, "--headless", "--path", str(project), "--editor", "--import", "--no-header"]
    stats = run_once(cmd, timeout, rss, label, 1, 1, 0, require_marker=False)
    stats["stage"] = label
    return stats


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--godot", default=os.environ.get("GODOT_BIN", "./bin/godot.linuxbsd.editor.dev.x86_64"))
    p.add_argument("--textures", type=int, default=128)
    p.add_argument("--scenes", type=int, default=512)
    p.add_argument("--repeats", type=int, default=3, help="Warm runs after one cold run")
    p.add_argument("--seed", type=int, default=12345)
    p.add_argument("--timeout", type=float, default=600.)
    p.add_argument("--rss-limit-mib", type=float, default=4096.)
    p.add_argument("--output", type=Path, default=Path("import-stress.json"))
    p.add_argument("--keep-project", type=Path, help="Instead of a temporary folder, write the synthetic project here")
    args = p.parse_args(argv)
    if (args.textures < 1 or args.textures > 10000 or args.scenes < 1 or args.scenes > 100000
            or args.repeats < 0 or args.repeats > 100 or args.timeout <= 0 or args.rss_limit_mib <= 0):
        p.error("Invalid generation or safety bounds")
    if args.keep_project is not None and args.keep_project.exists() and any(args.keep_project.iterdir()):
        p.error("--keep-project must point to a new or empty directory")
    binary = str(Path(args.godot).resolve()) if "/" in args.godot or "\\" in args.godot else args.godot
    holder = tempfile.TemporaryDirectory(prefix="cgame-import-stress-") if args.keep_project is None else None
    project = Path(holder.name) if holder is not None else args.keep_project.resolve()
    try:
        print("Generating synthetic project: %s" % project, flush=True)
        fixtures = make_project(project, args.textures, args.scenes, args.seed)
        report = {
            "schema_version": 1,
            "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "host": {"platform": platform.platform(), "logical_cpus": os.cpu_count()},
            "binary": binary,
            "fixtures": fixtures,
            "seed": args.seed,
            "runs": [],
        }
        for label in (["cold"] + ["warm_%d" % i for i in range(1, args.repeats + 1)]):
            print("Benchmarking import stage: %s" % label, flush=True)
            run = run_import(binary, project, args.timeout, args.rss_limit_mib, label)
            report["runs"].append(run)
            print("%s: %s %.3f s, peak RSS %s MiB" %
                  (label, run["status"], run["wall_seconds"], run["peak_rss_mib"]), flush=True)
            if run["status"] != "passed":
                break
        successful = [r for r in report["runs"] if r["status"] == "passed"]
        warm = [r["wall_seconds"] for r in successful if r["stage"].startswith("warm_")]
        report["metrics"] = {
            "cold_wall_seconds": successful[0]["wall_seconds"] if successful else None,
            "warm_median_wall_seconds": statistics.median(warm) if warm else None,
            "peak_rss_mib": max(
                (r["peak_rss_mib"] for r in successful if r["peak_rss_mib"] is not None),
                default=None),
        }
        report["status"] = ("passed" if len(successful) == args.repeats + 1 else "failed")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temp = args.output.with_name(args.output.name + ".tmp")
        temp.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temp.replace(args.output)
        print("Import results: %s (%s)" % (args.output, report["status"]), flush=True)
        return 0 if report["status"] == "passed" else 1
    finally:
        if holder is not None:
            holder.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
