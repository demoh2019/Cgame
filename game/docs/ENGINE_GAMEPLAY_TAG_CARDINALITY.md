# Native gameplay-tag cardinality — Albion After

Cgame's GameplayTagContainer now provides `count_matching_queries(queries, exact=false)`.
It counts **distinct query strings**, not raw tags or stack magnitudes. A query
`Runtime.Status` matches a descendant in hierarchical mode, while `exact=true`
only matches an identical full tag. Duplicate query strings do not inflate the
count. An empty list returns zero.

`GameplayTagQuery.min_any_matches` is a serializable, validated threshold
in the 1–64 range (default 1). It composes with existing all/none rules and
only applies if `any_tags` is not empty. This is a small subset of the richer
nested FGameplayTagQuery model in Unreal Engine: **no general boolean query AST**.

## Game usage

The client synchronizes server-provided runtime tags on actor snapshots.
`EngineFeatures.zombie_control_count()` then reads the native store (when
available) or the same authoritative snapshot timers in stock Godot.

Stagger, snare and sunder each contribute at most one active status.
When two or more overlap, infected receive a slight magenta additive tint
on top of existing status priorities. The effect is visual-only; it does
not alter damage, crowd control, AI, replication, persistence or PvP rules.
Older custom binaries safely use the fallback.

## Verify

```sh
scons platform=linuxbsd target=editor tests=yes module_gameplay_tags_enabled=yes -j2
bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[GameplayTags]*"
bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_all.gd
```

Never treat a source-level assertion as a successful native engine build.
