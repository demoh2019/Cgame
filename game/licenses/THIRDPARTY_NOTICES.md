# Third-party notices (game scripts)

## RVO2 Library — reciprocal collision avoidance

- Used in: `scripts/shared/crowd_avoidance.gd` (GDScript port of the ORCA linear programs)
- Source: https://github.com/snape/RVO2
- Copyright: University of North Carolina at Chapel Hill — Jur van den Berg, Stephen J. Guy, Jamie Snape, Ming C. Lin, Dinesh Manocha
- License: Apache License 2.0 — full text in `licenses/Apache-2.0.txt`
- Changes: rewritten in GDScript; the k-d tree neighbour search is replaced by a uniform spatial hash.

All other systems added alongside it (planners, navigation, erosion, water, netcode,
animation, fracture, acoustics, cinematics, VFX graph, tracing, procedural generation)
are original implementations of published algorithms; the papers are cited in each file header.
