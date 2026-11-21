# Native target-tag gated Gameplay Effects (Cgame / Albion After)

Inspired by Unreal Engine's Gameplay Ability System target tag requirements and
immunity, the native `GameplayEffectTimeline` now supports an opt-in guarded
application API. The existing `apply_effect()` and authoritative snapshot
workflows remain unchanged.

## Engine API

```gdscript
var timeline := GameplayEffectTimeline.new()
var actor_tags := PackedStringArray(["Runtime.Life.Alive", "Runtime.Status.Shielded"])
var applied := timeline.apply_effect_with_tag_requirements(
    "Local.Visual.RecentHit", 0.22,
    actor_tags,
    PackedStringArray(["Runtime.Life.Alive"]), # all required
    PackedStringArray(["Runtime.Life.Dead", "Runtime.Status.Immune.Hit"]), # none allowed
    1, 4, GameplayEffectTimeline.REAPPLY_REFRESH)
```

The active tag context must come from the **trusted target state**, not from a
client-provided RPC payload. A required tag is satisfied by an exact tag or a
dot-delimited descendant (for example, `Runtime.Life` matches
`Runtime.Life.Alive`). A blocked tag rejects any exact match or descendant.
A visually similar prefix (e.g. `ImmuneExtra`) is not a match for `Immune`.

The gate validates **all** tag arrays before updating any effect stack, timer
or periodic pulse phase. It accepts at most 128 active tags and 32 required /
32 blocked tags, rejects malformed dotted paths, and then delegates to the
normal duration/stack/reapply validation. Rejection is non-mutating. Empty
requirement lists skip their respective checks.

The engine deliberately does not depend on the optional `gameplay_tags`
module: callers pass packed strings, including when running a game without
the custom tag container. Only the caller can determine gameplay authority;
the helper is an admission rule, **not** a network authority or an immunity
system that discovers targets itself.

## Albion After

`game/scripts/client/engine_features.gd` uses the guarded native API for
the cosmetic `Local.Visual.RecentHit` stack, feeding active tags from the
node's native `GameplayTagContainer`. The server-confirmed
`Runtime.Life.Dead` or optional `Runtime.Status.Immune.Hit` prevents
new cosmetic recent-hit stacking. Live targets retain the normal rapid-hit
response and existing four-stack limit.

Older Cgame binaries with the timeline but without this method continue using
`apply_effect()`; stock Godot continues the existing no-native fallback.
Neither client visuals nor the new engine API changes authoritative damage,
target validation, network packets or persistent saves.

## Regression commands

On a machine with the Cgame native editor build:

```sh
scons platform=linuxbsd target=editor tests=yes module_gameplay_fx_enabled=yes
bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*timeline*"
bin/godot.linuxbsd.editor.x86_64 --headless --path game --editor --import --quit
bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_effect_timeline.gd
```

Relevant tests: `modules/gameplay_fx/tests/test_gameplay_fx.h` and
`game/tests/test_runtime_effect_timeline.gd`.

Reference: [Unreal Engine Gameplay Effects](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-effects-for-the-gameplay-ability-system-in-unreal-engine).
