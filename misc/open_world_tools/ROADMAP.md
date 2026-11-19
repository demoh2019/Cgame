# Godot fork capability roadmap (48 requests)

**Status:** `Prototype` means only an experimental, self-contained initial implementation exists in this branch; not a shipping or feature-complete engine feature. `Not started` does not mean no community plugin exists.

| # | Capability | Status | Next concrete engineering milestone |
|---|---|---|---|
| 1 | Terrain Editor | Prototype | Incremental chunk edits, undo deltas, sculpt gizmo, terrain resource |
| 2 | Terrain Painting | Prototype | Editable image splatmaps, layer asset UI, GPU weight textures |
| 3 | Foliage System | Prototype | Paint/erase foliage masks, cell-local MultiMeshes, culling |
| 4 | PCG Graph | Not started | Typed graph resource and deterministic node evaluator |
| 5 | World Partition | Prototype | Background cell loading, streaming budget, serialization |
| 6 | HLOD Builder | Not started | Offline mesh reduction and cell hierarchy builder |
| 7 | Terrain Erosion | Prototype | Hydraulic erosion, masks, GPU compute path |
| 8 | Water System | Not started | Reusable water shading and river spline primitives |
| 9 | Volumetric Clouds | Not started | Cloud density volume resources and weather data model |
| 10 | Procedural Vegetation | Not started | L-system/grammar-based tree resource and editor tool |
| 11 | Nanite-like virtual geometry | Not started | Mesh cluster format, GPU culling and streaming design |
| 12 | Lumen-like dynamic GI | Not started | GI requirements and renderer integration benchmark |
| 13 | Hardware Ray Tracing | Not started | Capability probing and RT acceleration structure abstraction |
| 14 | MegaLights | Not started | GPU light list and clustered shading stress benchmark |
| 15 | Niagara / VFX Graph | Not started | Reusable typed effects graph and particle back-end |
| 16 | Virtual Texturing | Not started | Sparse page table, residency manager and shader sampling |
| 17 | Advanced Cinematic Rendering | Not started | Render presets, sampling and offline accumulation API |
| 18 | GPU-driven Open World Rendering | Not started | Indirect draw architecture and GPU culling benchmarks |
| 19 | Rendering Debugging Tools | Not started | Frame, pass and resource GPU instrumentation |
| 20 | Material Layering | Not started | Shared layer stack resources and material editor UI |
| 21 | Motion Matching | Not started | Pose feature database, nearest-pose search |
| 22 | Control Rig | Not started | Constraint graph and editable rig handles |
| 23 | Motion Warping | Not started | Root motion target adjustment node |
| 24 | IK Retargeting | Not started | Skeleton mapping and batch retarget editor |
| 25 | Motion Capture Pipeline | Not started | Import/cleanup/reconstruction plugin interface |
| 26 | Procedural Character Animation | Not started | Motion modification library and procedural graph |
| 27 | Cinematic Sequencer | Not started | Camera/audio/event track extension of AnimationPlayer |
| 28 | Cloth Authoring | Not started | Cloth mesh weights and constraint authoring tool |
| 29 | Blueprints-like Visual Scripting | Not started | Typed visual logic graph with debugger and codegen |
| 30 | DOTS / ECS | Not started | Benchmark-driven ECS interoperability API |
| 31 | Burst-like Compiler | Not started | Investigate C# AOT and native SIMD workflow |
| 32 | Behavior Trees | Not started | Typed behavior resources and runtime executor |
| 33 | StateTree | Not started | Hierarchical state machine resources and inspector |
| 34 | AI Perception | Not started | Vision/hearing query components and event bus |
| 35 | Environment Query System | Not started | EQS scoring resources and spatial samples |
| 36 | Gameplay Ability System | Not started | Ability, attribute, modifier and cooldown resources |
| 37 | Mass Entity | Not started | Batched entity updates and crowd benchmark |
| 38 | Graph Toolkit | Not started | Shared graph editing, validation and serialization API |
| 39 | Client Prediction | Not started | Fixed-tick input buffering and reconciliation hooks |
| 40 | Rollback & Reconciliation | Not started | Deterministic state snapshots and replay harness |
| 41 | Replication Graph | Not started | Spatial relevancy layers and bandwidth budget |
| 42 | Multiplayer Debugger | Not started | Packet latency/loss simulator and replication timeline |
| 43 | Content Delivery | Not started | Signed manifest/download/cache/rollback specification |
| 44 | Advanced Editor Testing | Not started | Headless editor UI fixtures and deterministic input tests |
| 45 | Large Team Collaboration | Not started | Scene conflict reduction and component-level serialization |
| 46 | Asset Pipeline Automation | Not started | Asset import rules, validation and batch integration |
| 47 | Integrated AI Assistant | Not started | Optional sandboxed tool API with explicit user permission |
| 48 | Console Toolchain | Not started | Abstract export provider interface, no closed SDK bundling |

## Suggested implementation order

**Phase A — tested editor foundations:** (1, 2, 3, 5, 7, then 4, 6, 10, 44). Focus on stable resource formats, incremental editing, and testable world generation. Avoid touching renderer core until requirements are measured.

**Phase B — reusable tooling:** (38, 32, 33, 34, 35, 36, 29, 46). One graph framework should support multiple workflows instead of proliferating incompatible graph editors.

**Phase C — large-world performance:** (16, 18, 19, 20, 11, 14). Benchmark Vulkan/Mobile/Compatibility separately and use fallback paths.

**Phase D — specialized systems:** (8, 9, 12, 13, 15, 17, 21–28, 30, 31, 37, 39–43, 45, 47, 48). Each requires independent design review, prototypes, tests, cross-platform CI and migration notes.

The roadmap is a **technical plan**, not an assertion that all 48 features are implemented.