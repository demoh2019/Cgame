# GPU vertex shader FMA optimization

This is a **selective** backport of Godot upstream PR #125255.

For the Forward+ vertex shader it replaces selected matrix-vector and affine
matrix multiplication expressions with explicitly ordered GLSL FMA operations.
The Forward+ `invariant gl_Position` qualifier is retained to preserve
consistent positions between depth/color passes. The instance-data loading
path is unchanged: no extra subgroup feature requirement is introduced.

For the Mobile vertex shader, the redundant `invariant gl_Position` qualifier
is removed, as Mobile has no separate depth prepass for opaque geometry.

## Verification

The included Python regression suite checks source integration and numeric
matrix equivalence on deterministic inputs. It **does not** prove real GPU
speedups, full shader compilation, visual precision or cross-device support.

Performance and rendering correctness should be evaluated on NVIDIA, AMD,
Intel integrated GPUs, Apple GPUs and Android devices, including multiview,
motion vectors, shadows, lightmaps and double-precision coordinates.
Any visual mismatch warrants reverting the affected shader optimization.

The upstream PR reports a GPU-specific performance reduction in frame time
on one NVIDIA desktop test, but **no corresponding Cgame measurements exist yet**.
