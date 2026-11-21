# Release and deployment

Version: `application/config/version` in `project.godot` (shown on the title screen). Bump it with every release.

## 1. Export templates

The game runs on this repository's own Godot fork, so export templates are built from it
(stock Godot templates will not have the engine features the game uses):

```bash
scons platform=macos target=template_release arch=universal
scons platform=windows target=template_release arch=x86_64
scons platform=linuxbsd target=template_release arch=x86_64
```

Point Godot at the resulting templates (Editor → Manage Export Templates → install from file, or
`~/Library/Application Support/Godot/export_templates/<version>/`).

## 2. Export

Presets live in `game/export_presets.cfg` (tests, tools, backend and docs are excluded):

```bash
godot --headless --path game --export-release "macOS" ../build/client/macos/AlbionAfter.zip
godot --headless --path game --export-release "Windows" ../build/client/windows/AlbionAfter.exe
godot --headless --path game --export-release "Linux Server" ../build/server/albion_after_server.x86_64
```

macOS builds must be signed and notarized before public distribution (fill the codesign/notarization
options of the macOS preset with your Apple Developer identity).

## 3. Accounts backend (Nakama)

```bash
cd game/backend && cp .env.example .env   # then change every value
docker compose up -d
```

Secrets come only from `.env` (git-ignored). The Nakama console (7351) is bound to localhost; reach it
over an SSH tunnel. Put the HTTP API (7350) behind TLS (a reverse proxy) for a public server.

## 4. Game server

```bash
docker build -f game/deploy/server.Dockerfile -t albion-after-server .
docker run -d --restart unless-stopped -p 24565:24565/udp -e NAKAMA=nakama-host:7350 --name world albion-after-server
```

Without `NAKAMA` the server runs an offline guest world (characters are not saved between sessions).
Watch `SERVER players=… tick_max=…` in the container log: sustained `tick_max` above ~50 ms means the
host is too small for the player count.

## Release checklist

- Run the full test suite: `godot --headless --path game --script res://tests/run_all.gd` — zero failures.
- One hour of play on the release build with an empty error log.
- Version bumped; changelog written; builds signed.
