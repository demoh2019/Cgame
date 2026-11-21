extends RefCounted
## Static L2 spherical-harmonics lighting helpers (9 coefficients, one Color per
## coefficient; only r/g/b are used, alpha is kept at 0 for coefficients).
##
## Credits (algorithms from published papers; no third-party code copied):
##  - Ramamoorthi & Hanrahan, "An Efficient Representation for Irradiance
##    Environment Maps" (SIGGRAPH 2001): real SH basis constants and the
##    cosine-lobe convolution factors A0=pi, A1=2pi/3, A2=pi/4.
##  - Peter-Pike Sloan, "Stupid Spherical Harmonics (SH) Tricks" (GDC 2008).
##  - Majercik, Guertin, Nowrouzezahrai, McGuire, "Dynamic Diffuse Global
##    Illumination with Ray-Traced Irradiance Fields" (JCGT 2019) for the use of
##    SH irradiance probes.
## The SH basis constants are mathematical facts (not copyrightable).
##
## Convention: evaluate_irradiance() returns irradiance divided by pi, so a
## uniform radiance L yields exactly L (multiply by albedo for diffuse light).
## Order: Y00, Y1-1(y), Y10(z), Y11(x), Y2-2(xy), Y2-1(yz), Y20, Y21(xz), Y22.

const COEFFS: int = 9
const C0: float = 0.282094792
const C1: float = 0.488602512
const C2: float = 1.092548431
const C3: float = 0.315391565
const C4: float = 0.546274215
const GOLDEN_ANGLE: float = 2.399963229728653
## Cosine convolution A_l / pi for bands 0, 1, 2.
const CONV0: float = 1.0
const CONV1: float = 2.0 / 3.0
const CONV2: float = 0.25


static func create() -> PackedColorArray:
	var sh := PackedColorArray()
	sh.resize(COEFFS)
	sh.fill(Color(0.0, 0.0, 0.0, 0.0))
	return sh


static func basis(d: Vector3) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(COEFFS)
	b[0] = C0
	b[1] = C1 * d.y
	b[2] = C1 * d.z
	b[3] = C1 * d.x
	b[4] = C2 * d.x * d.y
	b[5] = C2 * d.y * d.z
	b[6] = C3 * (3.0 * d.z * d.z - 1.0)
	b[7] = C2 * d.x * d.z
	b[8] = C4 * (d.x * d.x - d.y * d.y)
	return b


## Evenly distributed unit direction i of n on the sphere (Fibonacci lattice).
static func fibonacci_dir(i: int, n: int) -> Vector3:
	var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(n)
	var r: float = sqrt(maxf(0.0, 1.0 - y * y))
	var phi: float = float(i) * GOLDEN_ANGLE
	return Vector3(cos(phi) * r, y, sin(phi) * r)


## Adds a radiance sample (already weighted by its solid angle) in place; returns sh.
static func accumulate(sh: PackedColorArray, dir: Vector3, color: Color) -> PackedColorArray:
	var b := basis(dir.normalized())
	for i in COEFFS:
		var w: float = b[i]
		var c: Color = sh[i]
		sh[i] = Color(c.r + color.r * w, c.g + color.g * w, c.b + color.b * w, 0.0)
	return sh


## Projects a single weighted radiance sample coming from `dir`.
static func project_direction(dir: Vector3, color: Color) -> PackedColorArray:
	return accumulate(create(), dir, color)


static func add(a: PackedColorArray, b: PackedColorArray) -> PackedColorArray:
	var out := create()
	for i in COEFFS:
		var x: Color = a[i]
		var y: Color = b[i]
		out[i] = Color(x.r + y.r, x.g + y.g, x.b + y.b, 0.0)
	return out


static func scale(a: PackedColorArray, f: float) -> PackedColorArray:
	var out := create()
	for i in COEFFS:
		var x: Color = a[i]
		out[i] = Color(x.r * f, x.g * f, x.b * f, 0.0)
	return out


## Linear blend (named lerp_sh to avoid shadowing the global lerp).
static func lerp_sh(a: PackedColorArray, b: PackedColorArray, t: float) -> PackedColorArray:
	var out := create()
	for i in COEFFS:
		var x: Color = a[i]
		var y: Color = b[i]
		out[i] = Color(lerpf(x.r, y.r, t), lerpf(x.g, y.g, t), lerpf(x.b, y.b, t), 0.0)
	return out


## Reconstructs (band-limited) radiance in direction dir.
static func evaluate_radiance(sh: PackedColorArray, dir: Vector3) -> Color:
	var b := basis(dir.normalized())
	var r: float = 0.0
	var g: float = 0.0
	var bl: float = 0.0
	for i in COEFFS:
		var c: Color = sh[i]
		var w: float = b[i]
		r += c.r * w
		g += c.g * w
		bl += c.b * w
	return Color(r, g, bl, 1.0)


## Cosine-convolved irradiance / pi around `normal`, clamped to be non-negative.
static func evaluate_irradiance(sh: PackedColorArray, normal: Vector3) -> Color:
	var b := basis(normal.normalized())
	var r: float = 0.0
	var g: float = 0.0
	var bl: float = 0.0
	for i in COEFFS:
		var f: float = CONV0 if i == 0 else (CONV1 if i < 4 else CONV2)
		var c: Color = sh[i]
		var w: float = b[i] * f
		r += c.r * w
		g += c.g * w
		bl += c.b * w
	return Color(maxf(r, 0.0), maxf(g, 0.0), maxf(bl, 0.0), 1.0)


## Analytic sky: gradient ground->sky over the y axis plus a directional sun whose
## colour is the irradiance on a surface facing it.
static func from_sky(sun_dir: Vector3, sun_color: Color, sky_color: Color, ground_color: Color, samples: int) -> PackedColorArray:
	var sh := create()
	var n: int = maxi(samples, 16)
	var w: float = 4.0 * PI / float(n)
	for i in n:
		var d := fibonacci_dir(i, n)
		var rad := ground_color.lerp(sky_color, clampf(d.y * 0.5 + 0.5, 0.0, 1.0))
		sh = accumulate(sh, d, Color(rad.r * w, rad.g * w, rad.b * w, 0.0))
	if sun_dir.length_squared() > 0.0:
		sh = accumulate(sh, sun_dir, Color(sun_color.r * PI, sun_color.g * PI, sun_color.b * PI, 0.0))
	return sh


## Rotates the lighting function by `rot` via quadrature (error ~1e-2).
static func rotate(sh: PackedColorArray, rot: Basis) -> PackedColorArray:
	var out := create()
	var inv := rot.inverse()
	var n: int = 256
	var w: float = 4.0 * PI / float(n)
	for i in n:
		var d := fibonacci_dir(i, n)
		var rad := evaluate_radiance(sh, inv * d)
		out = accumulate(out, d, Color(rad.r * w, rad.g * w, rad.b * w, 0.0))
	return out
