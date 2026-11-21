# Console readiness (no NDA material)

**This document contains no confidential or NDA-covered content.** Console SDKs (PlayStation, Xbox, Nintendo) are
under NDA. Nothing here was taken from, or searched for in, those programs. Everything below uses public information
only: general industry practice, public conference talks, Godot's public statements, Valve's public Steam Deck
verification criteria and Microsoft's publicly available high-level requirements overview.

## What can be done without any SDK

Most of what makes a port painful is architecture, not SDK calls. Prepare these on desktop today:

| Area | Where it lives | Status |
|---|---|---|
| Platform abstraction (accounts, saves, achievements, presence, entitlements, controller pairing, suspend/resume, network, text input, parental controls) | `scripts/shared/platform_services.gd` | `DesktopBackend` and `MockConsoleBackend` |
| Save safety: atomic write (temp, verify, rename), backup copy, checksum envelope, quota errors | same file | tested |
| Failure rehearsal: quota exceeded, sign-out mid-session, controller loss, suspend during save | `MockConsoleBackend` + `tests/test_platform_services.gd` | tested |
| Certification-style self checks with a PASS/FAIL/MANUAL report | `scripts/tools/cert_checks.gd` | runnable |

Run the report (optionally feeding a soak result from `scripts/tools/soak_test.gd --out soak.json`):

```
godot --headless --path game --script res://scripts/tools/cert_checks.gd -- --out report.md --soak soak.json
```

Checks cover: save corruption resilience, interrupted and suspended saves, quota handling, controller-disconnect pause,
sign-out, offline handling, parental-control gating, text input fallback, achievement idempotency, minimum text size,
safe area, localization completeness (RU strings in `ui_localization.gd`), load-time budget, soak verdict, controller
glyphs and 1280x800 readability. These mirror public best practice (the kind of items public Steam Deck verification
and general platform requirement overviews describe). They are **not** a substitute for any platform holder's
certification and passing them certifies nothing.

## Current known gaps (from the report)

- Literal font sizes below 12 px in the HUD (readability at 1280x800 / TV distance).
- No safe-area handling in `scripts/client`.
- Only English and Russian exist; platform storefronts typically expect more languages.
- Gameplay code does not yet route saves, achievements or pause through `PlatformServices`; the abstraction is ready
  for adoption, and call sites should be migrated incrementally.

## Steam Deck (public route, available now)

Valve publishes the verification criteria openly: full controller support with correct glyphs, no launcher or
non-controller dialogs, default config legible at 1280x800, on-screen keyboard when text is needed. The desktop build
can target this today; use the glyph, text size and readability checks plus a hands-on pass on real hardware (MANUAL
items).

## Official route for PlayStation, Xbox, Nintendo

1. Apply to each platform holder's developer program (for example ID@Xbox, PlayStation Partners, Nintendo Developer
   Portal). Approval, devkits, SDK access and the real certification requirements come only through those programs,
   under NDA.
2. Godot does not ship console export support in the open-source project because of those NDAs. Publicly, Godot points
   to licensed third parties for console ports, notably W4 Games (founded by Godot maintainers) and other porting
   partners. Contact them for current offerings; this project makes no claim about their status or pricing.
3. A licensed port would add a new `PlatformServices.Backend` subclass implementing the same contract as
   `DesktopBackend`, written against the SDK inside the NDA boundary and kept out of this public repository.
4. Re-run `cert_checks.gd` against the ported build as an early smoke gate, then follow the platform holder's own
   certification documents for the real requirement list.

## Rules for contributors

- Do not add SDK headers, documentation excerpts, requirement checklists or leaked material from any console program.
- Keep any licensed backend in a private repository or private branch.
- Describe requirements only if they come from a public source, and cite it.
