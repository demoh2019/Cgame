extends RefCounted
## Tessendorf FFT ocean heightfield ("Simulating Ocean Water", 2001), the
## technique behind the Sea of Thieves / Atlas oceans and Unreal's Water plugin
## far-field waves. A Phillips spectrum h0(k) is built once from a seed; each
## frame h(k,t) = h0(k) e^{iwt} + conj(h0(-k)) e^{-iwt} (w = sqrt(g|k|), deep
## water dispersion) is transformed by an inverse 2D FFT into a real, tileable
## height grid that can be sampled on the CPU (buoyancy) or uploaded as a
## shader texture (vertex displacement).

const GRAVITY: float = 9.81

var n: int = 0
var patch_size: float = 1.0
## Largest |imag| seen by the last evaluate() (should be ~0 for a real field).
var last_max_imag: float = 0.0

var _h0_re: PackedFloat32Array = PackedFloat32Array()
var _h0_im: PackedFloat32Array = PackedFloat32Array()
var _omega: PackedFloat32Array = PackedFloat32Array()


## Builds the Phillips spectrum deterministically. n must be a power of two.
func setup(grid: int, patch: float, wind: Vector2, amplitude: float, seed: int) -> void:
	assert(grid >= 4 and (grid & (grid - 1)) == 0, "n must be a power of two")
	n = grid
	patch_size = patch
	var count: int = n * n
	_h0_re.resize(count)
	_h0_im.resize(count)
	_omega.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wind_speed: float = wind.length()
	var wind_dir: Vector2 = wind.normalized() if wind_speed > 0.0001 else Vector2.RIGHT
	var largest: float = maxf(wind_speed * wind_speed / GRAVITY, 0.0001)
	var damp_len: float = largest * 0.001
	var half: int = n >> 1
	for j in n:
		var my: int = j if j < half else j - n
		for i in n:
			var mx: int = i if i < half else i - n
			var idx: int = j * n + i
			# Box-Muller pair is always drawn so the stream stays aligned.
			var u1: float = maxf(rng.randf(), 1e-7)
			var u2: float = rng.randf()
			var rad: float = sqrt(-2.0 * log(u1))
			var gr: float = rad * cos(TAU * u2)
			var gi: float = rad * sin(TAU * u2)
			var kv := Vector2(mx, my) * (TAU / patch_size)
			var k2: float = kv.length_squared()
			# Skip DC and the unpaired Nyquist row/column so -k always exists.
			if k2 < 1e-12 or mx == -half or my == -half:
				_h0_re[idx] = 0.0
				_h0_im[idx] = 0.0
				_omega[idx] = 0.0
				continue
			var k: float = sqrt(k2)
			var align: float = kv.dot(wind_dir) / k
			var phillips: float = amplitude * exp(-1.0 / (k2 * largest * largest)) / (k2 * k2) * align * align
			phillips *= exp(-k2 * damp_len * damp_len)
			var s: float = sqrt(phillips * 0.5)
			_h0_re[idx] = gr * s
			_h0_im[idx] = gi * s
			_omega[idx] = sqrt(GRAVITY * k)


## Returns n*n heights (row-major) at the given time.
func evaluate(time: float) -> PackedFloat32Array:
	var count: int = n * n
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(count)
	im.resize(count)
	for j in n:
		var nj: int = (n - j) % n
		for i in n:
			var ni: int = (n - i) % n
			var idx: int = j * n + i
			var midx: int = nj * n + ni
			var wt: float = _omega[idx] * time
			var c: float = cos(wt)
			var s: float = sin(wt)
			# h0(k) e^{iwt}
			var ar: float = _h0_re[idx] * c - _h0_im[idx] * s
			var ai: float = _h0_re[idx] * s + _h0_im[idx] * c
			# conj(h0(-k)) e^{-iwt}
			var br: float = _h0_re[midx] * c - _h0_im[midx] * s
			var bi: float = -_h0_re[midx] * s - _h0_im[midx] * c
			# conj(x) e^{-iwt} with x = (xr, xi): (xr - i xi)(c - i s)
			br = _h0_re[midx] * c - _h0_im[midx] * s
			bi = -(_h0_re[midx] * s + _h0_im[midx] * c)
			re[idx] = ar + br
			im[idx] = ai + bi
	_fft_2d_inverse(re, im)
	var scale: float = float(count)
	var out := PackedFloat32Array()
	out.resize(count)
	var max_im: float = 0.0
	for idx in count:
		out[idx] = re[idx] * scale
		max_im = maxf(max_im, absf(im[idx] * scale))
	last_max_imag = max_im
	return out


## Heights as a single-channel float image for a displacement shader.
func displacement_image(time: float) -> Image:
	var heights: PackedFloat32Array = evaluate(time)
	return Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())


func _fft_2d_inverse(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var row_re := PackedFloat32Array()
	var row_im := PackedFloat32Array()
	row_re.resize(n)
	row_im.resize(n)
	for j in n:
		var base: int = j * n
		for i in n:
			row_re[i] = re[base + i]
			row_im[i] = im[base + i]
		fft_1d(row_re, row_im, true)
		for i in n:
			re[base + i] = row_re[i]
			im[base + i] = row_im[i]
	for i in n:
		for j in n:
			row_re[j] = re[j * n + i]
			row_im[j] = im[j * n + i]
		fft_1d(row_re, row_im, true)
		for j in n:
			re[j * n + i] = row_re[j]
			im[j * n + i] = row_im[j]


## In-place radix-2 Cooley-Tukey FFT. Forward uses e^{-i...}; the inverse uses
## e^{+i...} and scales by 1/N so inverse(forward(x)) == x.
static func fft_1d(re: PackedFloat32Array, im: PackedFloat32Array, inverse: bool) -> void:
	var size: int = re.size()
	if size < 2:
		return
	assert((size & (size - 1)) == 0, "fft size must be a power of two")
	# Bit-reversal permutation.
	var j: int = 0
	for i in range(1, size):
		var bit: int = size >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var tr: float = re[i]
			re[i] = re[j]
			re[j] = tr
			var ti: float = im[i]
			im[i] = im[j]
			im[j] = ti
	var sign: float = 1.0 if inverse else -1.0
	var len: int = 2
	while len <= size:
		var ang: float = sign * TAU / float(len)
		var wr: float = cos(ang)
		var wi: float = sin(ang)
		var half_len: int = len >> 1
		var start: int = 0
		while start < size:
			var cr: float = 1.0
			var ci: float = 0.0
			for k in half_len:
				var a: int = start + k
				var b: int = a + half_len
				var xr: float = re[b] * cr - im[b] * ci
				var xi: float = re[b] * ci + im[b] * cr
				re[b] = re[a] - xr
				im[b] = im[a] - xi
				re[a] += xr
				im[a] += xi
				var ncr: float = cr * wr - ci * wi
				ci = cr * wi + ci * wr
				cr = ncr
			start += len
		len <<= 1
	if inverse:
		var inv: float = 1.0 / float(size)
		for i in size:
			re[i] *= inv
			im[i] *= inv
