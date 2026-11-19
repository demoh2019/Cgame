# Web platform port

This folder contains the C++ and JavaScript code for the Web platform port,
compiled using [Emscripten](https://emscripten.org/).

It also contains a ESLint linting setup (see [`package.json`](package.json)).

See also [`misc/dist/html`](/misc/dist/html) folder for additional files used by
this platform such as the html shell (web page).

## Publishing games in a browser

Use [`publish.py`](publish.py) to export a Godot project with the installed
Web export templates, verify the resulting WebAssembly bundle, preview it
locally, and optionally create a ZIP for static hosting.

```sh
python platform/web/publish.py export /path/to/game --out /tmp/game-web --zip /tmp/game-web.zip
python platform/web/publish.py serve /tmp/game-web
```

See [the browser publishing guide](PUBLISHING.md) for requirements, PWA
options, HTTPS headers, and regression tests.

## Documentation

- [Compiling for the Web](https://docs.godotengine.org/en/latest/engine_details/development/compiling/compiling_for_web.html)
  - Instructions on building this platform port from source.
- [Exporting for the Web](https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_web.html)
  - Instructions on using the compiled export templates to export a project.

## Artwork license

[`logo.svg`](export/logo.svg) and [`run_icon.svg`](export/run_icon.svg) are licensed under
[Creative Commons Attribution 3.0 Unported](https://www.w3.org/html/logo/faq.html#how-licenced)
per the HTML5 logo usage guidelines.
