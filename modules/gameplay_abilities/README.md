# Native Gameplay Ability System

This Godot C++ module is inspired by the reusable activation-policy concept of Unreal's Gameplay Ability System (not a port of Epic's implementation).

## Engine API

```gdscript
var abilities := GameplayAbilitySystem.new()
abilities.register_ability("fireball", {
    "cost": 20.0,
    "cooldown": 0.8,
    "required_tags": PackedStringArray(["class.mage"]),
    "blocked_tags": PackedStringArray(["status.stunned"]),
})
abilities.add_tag("class.mage.fire")
abilities.ability_activated.connect(_on_ability_activated)

func _physics_process(delta: float) -> void:
    abilities.tick(delta)

func cast_fireball() -> void:
    abilities.activate("fireball")

func _on_ability_activated(id: String) -> void:
    if id == "fireball":
        spawn_fireball()
```

The module provides **data-driven definitions**, **atomic cost/cooldown activation**, **hierarchical state tags**, **per-character independent state**, **signals**, and **transactional versioned save/load**. Game code remains responsible for damage, effects, animations and server authority.

Build the engine with the module enabled (default auto-discovery):
```sh
scons platform=linuxbsd target=editor
```

Run native doctests (build with `tests=yes`):
```sh
scons platform=linuxbsd target=editor tests=yes
./bin/godot.linuxbsd.editor.* --test --test-case="[GameplayAbilitySystem]*"
```

A playable game project is provided at `demos/gameplay_abilities_arena/`, and requires a Cgame binary built with this module. Run with `--path demos/gameplay_abilities_arena --editor` or open its `project.godot`.

### Guarantees and constraints

- Definitions are validated and deep-copied before registration.
- The runtime changes resource/cooldown only when every activation precondition passes.
- Tags match by complete dot-separated segment, not arbitrary substring.
- Restoring a state validates all values before mutating the instance.
- Snapshots intentionally omit ability definitions: register definitions before loading.
- No multiplayer prediction, authoritative replication, gameplay effect stacking or visual ability editor is included in this initial module.
