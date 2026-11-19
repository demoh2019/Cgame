# Publish a Godot game in a web browser

The existing Godot Web exporter produces a WebAssembly game for browsers with
WebGL 2. This helper automates export validation, local preview, and packaging.
It does **not** convert arbitrary desktop binaries, C#/.NET Godot 4 projects,
or native GDExtensions into browser applications.

## Requirements

- A Godot editor executable built with the Web export platform enabled.
- Matching **Web export templates** installed in the editor (Editor > Manage
  Export Templates). A .NET/C# build of Godot 4 does not support Web export.
- A Godot project containing `project.godot`, ideally using GDScript and
  the Compatibility renderer if targeting a wide range of browsers.
- Python 3.9+ for the helper. No third-party Python packages are required.

## One-command export

Run from this repository's root:

```sh
python platform/web/publish.py export /path/to/game --godot /path/to/godot \
    --out /tmp/my-game-web --zip /tmp/my-game-web.zip
```

The output directory contains `index.html`, `index.js`, `index.wasm`,
`index.pck`, and other files the game requires. Upload **all** files together.
The ZIP has `index.html` at its root, suitable for HTML5 game hosting platforms
such as itch.io. Use HTTPS when publishing the game.

If the project has no `export_presets.cfg`, the helper temporarily creates a
single-threaded `Web` preset and removes it after export. It preserves a preset
file changed while exporting. If presets already exist, create a Web preset in
**Project > Export** and select it with `--preset "Your Web Preset"`. Existing
presets are never overwritten. `--pwa` enables PWA only when a temporary preset
is generated.

To enable offline installation of the auto-created export:

```sh
python platform/web/publish.py export /path/to/game --out /tmp/my-game-pwa --pwa
```

## Preview, check, and package separately

```sh
python platform/web/publish.py check /tmp/my-game-web
python platform/web/publish.py serve /tmp/my-game-web --port 8060
python platform/web/publish.py zip /tmp/my-game-web /tmp/my-game-upload.zip
```

Open `http://127.0.0.1:8060` to test the exported game. The preview server sends
COOP and COEP headers and is only for local development, **not production**.
`check` catches missing, empty, or malformed core export files, not runtime
issues such as unsupported shaders, browser-specific APIs, or CORS failures.
Always test the game in real target browsers before release.

## Hosting and compatibility

- Godot Web exports require a browser supporting WebAssembly and WebGL 2.
- Default single-threaded Web exports are most compatible with typical static
  hosts, itch.io, and mobile browsers.
- If you enable threads or web GDExtensions in your own preset, production
  hosting may require `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp`, or Godot's enabled PWA isolation
  workaround. HTTPS is required outside localhost.
- Serve `.wasm` with MIME type `application/wasm` and keep all generated files
  together. Enable Brotli/gzip on your production host to reduce transfer size.
- Browser saves (`user://`) need browser storage permission; embedded games
  might face third-party storage restrictions.

Full compatibility guidance:
<https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html>

## Regression tests

```sh
python -m unittest discover -s platform/web/tests -p 'test_publish.py' -v
```

The unit tests cover export presets, crash-safe staging, integrity checks,
threading warnings, ZIP packaging, and CLI error handling. To smoke-test the
real exporter, additionally run the `export` command with a Godot executable
that has matching Web templates installed.
