# Cgame Fluids

Native C++ ports of the hot GDScript simulation libraries in `game/scripts/shared/`. All classes extend `RefCounted` and keep the public API of their GDScript originals.

| Class | Replaces | Method |
| --- | --- | --- |
| `CgameSPHFluid` | `sph_fluid.gd` | 3D position-based fluids (Macklin & Müller 2013, kernels of Müller, Charypar & Gross 2003) |
| `CgameFLIPFluid` | `flip_fluid.gd` | 2D FLIP/PIC on a MAC grid (Zhu & Bridson 2005, Harlow & Welch 1965; structure after Ten Minute Physics #18, MIT, M. Müller) |
| `CgameSmokeSim` | `smoke_sim.gd` | Stable Fluids smoke and fire (Stam 1999, Fedkiw/Stam/Jensen 2001, GPU Gems 3 ch. 30) |
| `CgameShallowWater` | `shallow_water.gd` | Virtual pipes heightfield (Mei, Decaudin & Hu 2007) |
| `CgameFFTOcean` | `fft_ocean.gd` | Phillips spectrum + inverse FFT (Tessendorf 2001) |

## Differences from the GDScript API

- Objects are created with `.new()` and configured with `setup(...)` (the GDScript constructors took arguments). The default constructor of each class uses the same defaults as the GDScript one.
- Internal arrays are private. Use `positions()`, `particle_positions()`, `particle_velocities()`, `get_field(CgameSmokeSim.FIELD_*)`, `get_depth()`, `set_velocity()` etc.
- `CgameSmokeSim.sample(field, position)` takes a field enum instead of an array.
- `CgameFFTOcean.fft_1d(re, im, inverse)` is static and returns `[re, im]` (packed arrays are passed by value to native code).
- Additions: `CgameFLIPFluid.get_cell_types()`, `CgameShallowWater.depth_image()` / `surface_image()`, `CgameFFTOcean.sample_height()`, `CgameSPHFluid.clear_particles()`.

## Threading and determinism

Loops run on `WorkerThreadPool` through `CgameFluids::parallel_for` (`cgame_fluids_common.h`). A loop is only parallelised when every chunk writes memory that belongs to its own elements and reads only data produced by an earlier pass. Order-dependent work (FLIP Gauss-Seidel, push-apart, particle-to-grid scatter, SPH obstacle impulse accumulation, the random stream of the ocean spectrum) stays serial. Reductions are serial too, so results are bit-identical regardless of the thread count.

## Use from game code

`game_facade/cgame_fluids_facade.gd` creates the native class when available and falls back to the GDScript implementation otherwise.

## Tests

`tests/test_cgame_fluids.h` (doctest, built with `scons tests=yes`) mirrors `test_particle_fluids.gd`, `test_smoke_vfx.gd` and `test_water_simulation.gd`: SPH bounds and density, FLIP divergence reduction and dam release, smoke buoyancy and obstacles, shallow-water volume conservation, FFT round trip and determinism.
