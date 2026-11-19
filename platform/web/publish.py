#!/usr/bin/env python3
"""Export, validate, preview, and package Godot projects for web hosting.

Uses Godot's built-in Web exporter; the engine binary and Web export templates
must be installed separately. No external Python dependencies are required.
"""

import argparse
import contextlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


class PublishError(Exception):
    """A user-actionable publishing failure."""


# Matches the editor's export preset format. Do not attempt to parse arbitrary
# Godot Variant values as Python or INI syntax.
_PRESET_SECTION = re.compile(r"^\[preset\.(\d+)\]$")
_PRESET_FIELD = re.compile(r'^\s*(name|platform)\s*=\s*("(?:[^"\\]|\\.)*")\s*$')
_THREADS_ENABLED = re.compile(r"\bconst\s+GODOT_THREADS_ENABLED\s*=\s*(true|false)\b")


def find_web_preset(contents, name):
    """Return True only if a preset has the given name AND Web platform."""
    current = None
    presets = {}
    for line in contents.splitlines():
        line = line.strip()
        section = _PRESET_SECTION.fullmatch(line)
        if section:
            current = section.group(1)
            presets.setdefault(current, {})
            continue
        if line.startswith("[") and line.endswith("]"):
            current = None
            continue
        if current is not None:
            field = _PRESET_FIELD.fullmatch(line)
            if field:
                try:
                    presets[current][field.group(1)] = json.loads(field.group(2))
                except json.JSONDecodeError:
                    continue
    return any(p.get("name") == name and p.get("platform") == "Web" for p in presets.values())


def make_web_preset(name="Web", pwa=False):
    """A minimal, single-threaded export preset for a GDScript Godot 4 game."""
    return (
        "[preset.0]\n\n"
        f"name={json.dumps(name)}\n"
        'platform="Web"\n'
        "runnable=true\n"
        "advanced_options=false\n"
        'custom_features=""\n'
        'export_filter="all_resources"\n'
        'include_filter=""\n'
        'exclude_filter=""\n'
        'export_path=""\n\n'
        "[preset.0.options]\n\n"
        "variant/thread_support=false\n"
        "variant/extensions_support=false\n"
        f"progressive_web_app/enabled={'true' if pwa else 'false'}\n"
        "progressive_web_app/ensure_cross_origin_isolation_headers=true\n"
    )


@contextlib.contextmanager
def web_preset(project_dir, name, pwa=False):
    """Use an existing Web preset, or temporarily supply one without clobbering files."""
    preset_path = project_dir / "export_presets.cfg"
    if preset_path.exists():
        if not preset_path.is_file():
            raise PublishError(f"Not a file: {preset_path}")
        contents = preset_path.read_text(encoding="utf-8-sig")
        if not find_web_preset(contents, name):
            raise PublishError(
                f"Web preset {name!r} not found in {preset_path}. "
                "Create one in Project > Export or specify --preset."
            )
        yield
        return

    contents = make_web_preset(name, pwa).encode("utf-8")
    try:
        with preset_path.open("xb") as f:
            f.write(contents)
    except FileExistsError as exc:
        raise PublishError("export_presets.cfg was created concurrently; retry.") from exc
    try:
        yield
    finally:
        # Do not delete changes made by the editor or another process during export.
        if preset_path.is_file() and preset_path.read_bytes() == contents:
            preset_path.unlink()
        else:
            print(f"Note: preserved changed preset file at {preset_path}", file=sys.stderr)


def check_export(directory, entry="index.html"):
    """Validate essential Godot Web bundle files; return info and warnings."""
    directory = Path(directory)
    if Path(entry).name != entry or not entry.endswith(".html"):
        raise PublishError("Entry point must be a single .html filename.")
    if not directory.is_dir():
        raise PublishError(f"Web directory does not exist: {directory}")

    stem = Path(entry).stem
    required = [entry, f"{stem}.js", f"{stem}.wasm", f"{stem}.pck"]
    for filename in required:
        path = directory / filename
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise PublishError(f"Missing or empty Web export file: {path}")

    with (directory / f"{stem}.wasm").open("rb") as f:
        if f.read(4) != b"\0asm":
            raise PublishError(f"Invalid WebAssembly signature: {stem}.wasm")
    with (directory / f"{stem}.pck").open("rb") as f:
        if f.read(4) != b"GDPC":
            raise PublishError(f"Invalid Godot package signature: {stem}.pck")

    html = (directory / entry).read_text(encoding="utf-8")
    if "$GODOT_" in html:
        raise PublishError("The HTML shell contains unexpanded $GODOT_ placeholders.")
    warnings = []
    match = _THREADS_ENABLED.search(html)
    if match and match.group(1) == "true":
        warnings.append(
            "Threaded Web export: production hosting requires HTTPS and "
            "Cross-Origin-Opener-Policy: same-origin plus "
            "Cross-Origin-Embedder-Policy: require-corp "
            "(or the enabled PWA isolation workaround)."
        )
    if not match:
        warnings.append("Could not determine thread support from the HTML shell; check hosting requirements.")

    size = sum((directory / name).stat().st_size for name in required)
    return {"entry": entry, "required_files": required, "core_bytes": size, "warnings": warnings}


def package_export(directory, archive, entry="index.html"):
    """Create a ZIP suitable for static web hosting or upload to itch.io."""
    directory = Path(directory).resolve()
    archive = Path(archive).resolve()
    check_export(directory, entry)
    if archive == directory or directory in archive.parents:
        raise PublishError("The archive must be outside the exported directory.")
    if archive.exists():
        raise PublishError(f"Archive already exists: {archive}")
    files = sorted(path for path in directory.rglob("*") if path.is_file() or path.is_symlink())
    if not files:
        raise PublishError("No export files found.")
    if any(path.is_symlink() for path in files):
        raise PublishError("Export contains symbolic links; refusing to package external files.")
    archive.parent.mkdir(parents=True, exist_ok=True)
    try:
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for path in files:
                bundle.write(path, path.relative_to(directory).as_posix())
    except Exception:
        archive.unlink(missing_ok=True)
        raise
    return len(files)


def export_project(project, output, godot="godot", preset="Web", pwa=False):
    """Build into a staging directory and publish only a verified export."""
    project = Path(project).resolve()
    output = Path(output).resolve()
    if not (project / "project.godot").is_file():
        raise PublishError(f"No project.godot in {project}")
    if output.exists():
        raise PublishError(f"Output already exists; choose a new directory: {output}")

    executable = shutil.which(godot)
    if executable is None:
        raise PublishError(f"Godot executable not found: {godot}")
    output.parent.mkdir(parents=True, exist_ok=True)

    with web_preset(project, preset, pwa), tempfile.TemporaryDirectory(
        prefix="godot-web-", dir=output.parent
    ) as temp:
        stage = Path(temp) / "site"
        stage.mkdir()
        cmd = [executable, "--headless", "--path", str(project), "--export-release", preset, str(stage / "index.html")]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        except OSError as exc:
            raise PublishError(f"Could not run Godot: {exc}") from exc
        if result.returncode != 0:
            details = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
            raise PublishError(f"Godot Web export failed (exit {result.returncode}):\n{details[-6000:]}")
        info = check_export(stage)
        # Don't publish a partial export if Godot failed or output files are malformed.
        if output.exists():
            raise PublishError(f"Output was created concurrently: {output}")
        stage.rename(output)
        return info


def preview_export(directory, host="127.0.0.1", port=8060):
    """Serve using the development-only Godot COOP/COEP-aware HTTP handler."""
    from functools import partial
    from http.server import ThreadingHTTPServer

    from serve import CORSRequestHandler

    directory = Path(directory).resolve()
    check_export(directory)
    handler = partial(CORSRequestHandler, directory=str(directory))
    with ThreadingHTTPServer((host, port), handler) as server:
        print(f"Preview at http://{host}:{server.server_port}/ (Ctrl+C to stop)")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build and publish Godot games for browsers (Godot 4 GDScript).")
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("export", help="Headless Web export using installed Godot export templates")
    build.add_argument("project", type=Path, help="Folder containing project.godot")
    build.add_argument("--out", type=Path, required=True, help="New output directory for the static site")
    build.add_argument("--godot", default="godot", help="Godot editor executable (default: godot on PATH)")
    build.add_argument("--preset", default="Web", help="Name of an existing Web export preset")
    build.add_argument("--pwa", action="store_true", help="Enable PWA for auto-created presets only")
    build.add_argument("--zip", dest="archive", type=Path, help="Also create a hosting ZIP archive")

    validate = sub.add_parser("check", help="Verify a previously exported Web bundle")
    validate.add_argument("directory", type=Path)
    validate.add_argument("--entry", default="index.html")

    package = sub.add_parser("zip", help="Package an existing Web export into an uploadable ZIP")
    package.add_argument("directory", type=Path)
    package.add_argument("archive", type=Path)
    package.add_argument("--entry", default="index.html")

    preview = sub.add_parser("serve", help="Preview a Web export locally (not for production)")
    preview.add_argument("directory", type=Path)
    preview.add_argument("--host", default="127.0.0.1")
    preview.add_argument("--port", default=8060, type=int)

    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            info = export_project(args.project, args.out, args.godot, args.preset, args.pwa)
            print(f"Web game exported: {args.out / 'index.html'}")
            if args.archive:
                count = package_export(args.out, args.archive)
                print(f"Packaged {count} files: {args.archive}")
        elif args.command == "check":
            info = check_export(args.directory, args.entry)
            print(f"Web export OK: {info['entry']} ({info['core_bytes']} core bytes)")
        elif args.command == "zip":
            count = package_export(args.directory, args.archive, args.entry)
            print(f"Packaged {count} files: {args.archive}")
            info = {"warnings": []}
        else:
            preview_export(args.directory, args.host, args.port)
            return 0
        for warning in info["warnings"]:
            print(f"WARNING: {warning}", file=sys.stderr)
        return 0
    except (PublishError, OSError, UnicodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
