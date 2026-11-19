# Autoload registration when running scripts

This regression fixture covers upstream issue fixed by godotengine/godot#125567.

From the repository root, with an editor binary in `bin/`, run:

```sh
GODOT=./bin/godot.linuxbsd.editor.dev.x86_64
"$GODOT" --headless --path tests/data/cli_autoload --check-only --script res://run_scene_tree.gd
"$GODOT" --headless --path tests/data/cli_autoload --check-only --script res://run_main_loop.gd
"$GODOT" --headless --path tests/data/cli_autoload --script res://run_scene_tree.gd
```

All three commands must exit with status zero. The last command must also print
`CLI_AUTOLOAD_SCENE_TREE_OK`. The preloaded script `consumer.gd` references
`TestAutoload`, so both direct and transitive script loading are covered.
The plain `MainLoop` script is checked for compilation but does not expect
an instantiated autoload node.
