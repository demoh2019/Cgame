# Node exact-name lookup performance

## Scope

The existing `Node::find_child`, `find_children`, and `find_parent` methods
always used `String::match` on child or parent names, even when the pattern
was a fixed literal without wildcards.

The literal fast path now interns the target name once as `StringName` and
compares the engine's already-interned node names. For nonrecursive
`find_child` and `find_children`, it uses the existing
`data.children` hash table via `_get_child_by_name`: average-case O(1)
lookup rather than scanning all direct children.

For recursive fixed-name `find_child`, a local recursive walker shares
one interned target name, preserving *depth-first* search and excluding
unowned subtrees when requested. Wildcard patterns containing `*` or
`?` keep the original matching path; the `?` rule in `String::match`
is intentionally untouched. Type-filter behavior in `find_children`
and parent lookup also remain unchanged.

No new persistent index or allocation-per-child is introduced; the
existing per-parent name hash table already exists in Node.

## Coverage and limits

Six engine-native regression cases added to
`tests/scene/test_node_find_children_fast.cpp` and 19 source contracts
in `misc/scripts/tests/test_node_exact_lookup_perf.py`. Native Linux
editor tests run via `.github/workflows/node-exact-lookup-perf.yml`.

The fast path changes the theoretical complexity for nonrecursive exact
lookup from O(number of children) to average O(1). This does **not**
establish a particular FPS, CPU percentage, heap usage reduction, or
speedup in a real game. Obtain comparable profiles before and after on
representative scene trees, including searches with wildcard patterns.
