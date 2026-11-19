# SoftBody3D gas leakage: pressure-driven deflation of closed shells

## Gap vs existing Cgame and references

Cgame already has optional sealed-shell gas pressure:
`P(V) = P_rest * (|V_rest| / |V|)^gamma`.
At rest volume, however, that law assumes **constant gas charge forever**.
It cannot model a balloon losing gas through a small vent, an inflatable
object gradually deflating, or pressure-sensitive discharge when compressed.

Other engines implement related *but not identical* capabilities:
Bullet SoftBody has an internal pressure/volume coefficient, and Jolt
supports internal pressure and volume constraints as part of its soft
body feature set. More detailed PBD balloon research explicitly tracks the
number of moles during venting and updates internal pressure using the
ideal-gas law. The Cgame implementation is its own bounded, simplified
pressure-driven discharge model; no third-party implementation was copied.

## Opt-in configuration

```ini
# The preexisting EOS: gamma=1 isothermal, around 1.4 adiabatic air
physics/3d/solver/soft_body_gas_pressure_gamma=1.4
# NEW: characteristic loss rate at rest pressure (1/s); default 0
physics/3d/solver/soft_body_gas_leak_rate=1.0
```

In addition, set a **positive** SoftBody3D pressure coefficient and use a
closed, consistently wound triangle mesh. The setting is cached on space
creation: recreate the space after changing the rate in ProjectSettings.

With the leak rate at 0, the existing sealed gas solver's result is
mathematically identical (default mass fraction 1). Legacy pressure,
open cloth and ordinary rigid bodies remain untouched.

## Mass and pressure evolution

Store one persistent double-precision mass fraction `m ∈ [0,1]` per soft
body, initially 1. No per-vertex or per-contact buffer is added.

```text
P_sealed = P_rest * [ |V_rest| / max(|V|, 0.05*|V_rest|) ] ^ gamma
P_before = P_sealed * m ^ gamma

dm/dt ≈ -k * m * sqrt(P_before / P_rest)
m_next = m * exp[-min(k*dt*sqrt(P_before/P_rest), 750)]
P_next = P_sealed * m_next ^ gamma
```

The gas loss increases under compression and slows as the shell
depressurizes. A bounded exponential update keeps charge nonnegative even
at coarse timesteps or very high leak rate; unlike explicit Euler, it
cannot remove more gas than remains.

**Model scope:** This is a *phenomenological*, pressure-dependent gauge
pressure discharge law, not a calibrated compressible flow equation. There
is no explicit ambient pressure, nozzle throat, choked/subsonic transition,
temperature evolution or fluid mass transfer between bodies. The adiabatic
exponent is reused as a game-physics approximation to entropy of the
remaining gas. For real engineering, use a compressible flow model and
physical vent area/discharge coefficient instead.

## Integration and performance

The update happens in the existing force-integration pass, immediately
after the signed closed-shell volume is calculated. All force application
and pinning logic stays unchanged.

- Invalid, inverted, open or collapsed shells do not lose charge and do
  not receive the sealed gas force that step.
- Reset charge to one when the volume rest shell is reinitialized or the
  mesh is destroyed. There is no charging/inflation API yet.
- Default `k=0` skips all exponential discharge work. Ordinary scenes
  do not allocate memory or run any extra gas-volume traversal.
- Both gas mass and pressure outputs are validated and committed together,
  so non-finite inputs cannot partially mutate a body's gas charge.
- At `m=0`, pressure is exactly zero and never becomes negative.

## Verification

Independent Python numerical/source checks:

```bash
python3 -m unittest discover -s tests/stress \
  -p test_physics_softbody_gas_leak.py -v
```

Native C++ (`tests=yes` binary):

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="*[PhysicsGasLeak]*" --success=true --no-colors
```

Actual soft-body integration:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_softbody_gas_leak_3d_regression.gd
```

The headless test creates two identically pressurized closed tetrahedral
SoftBody3D meshes, one sealed (`k=0`) and one vented (`k=25`).
After 90 physics frames, both positions must remain finite and the
sealed body's volume should be measurably larger than the vented body's.
The headless test is qualitative; full-scale validation should include
spheres and complex manifold mesh topology, pinned vertices, 30/60/120Hz,
small/large volume, and long-running repeated destruction/re-creation.

## Limitations and next engineering steps

This patch does **not** introduce actual tearing topology or open
holes: the shell must remain closed for the internal-pressure calculation
to work. A future version could tie vent parameters to a mesh tear
event or physical outlet geometry, with mass/energy transfer and explicit
temperature. Air-flow sound, conservation across linked gas chambers,
net buoyancy of the trapped gas, and the surrounding fluid field remain
unmodelled.

Native compilation, full engine CI, scene success and performance impact
must be measured independently; source and numerical contracts alone do
not establish production readiness.
