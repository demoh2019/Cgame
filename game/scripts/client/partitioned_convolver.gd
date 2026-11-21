extends RefCounted
## Uniformly partitioned FFT convolution (overlap-save with a frequency-domain delay line).
##
## Method: the classic uniformly-partitioned overlap-save scheme (Stockham/Gardner
## partitioned convolution; see e.g. Wefers, "Partitioned convolution algorithms for
## real-time auralization", 2015). The IR is cut into partitions of `block_size`
## samples, each zero-padded to 2*block_size and transformed once. Every input block is
## transformed once, stored in a ring of past spectra, and multiplied/accumulated with
## the matching IR partition spectra; one inverse FFT per block yields the output.
##
## FFT: own iterative radix-2 Cooley-Tukey (public-domain algorithm, written from
## scratch for this project; no third-party code). Real-signal symmetry is exploited by
## keeping only bins 0..N/2 in the spectral accumulators.
##
## Latency: process() consumes one block and returns the output block aligned with it
## (y[n] = sum h[k] x[n-k]); the only latency is the block_size samples the caller must
## buffer before calling process(), i.e. constant latency = block_size.

var block_size: int = 0
var _n: int = 0
var _half: int = 0
var _parts: int = 0
var _head: int = 0

var _cos: PackedFloat64Array = PackedFloat64Array()
var _sin: PackedFloat64Array = PackedFloat64Array()
var _rev: PackedInt32Array = PackedInt32Array()

var _h_re: PackedFloat64Array = PackedFloat64Array()
var _h_im: PackedFloat64Array = PackedFloat64Array()
var _fdl_re: PackedFloat64Array = PackedFloat64Array()
var _fdl_im: PackedFloat64Array = PackedFloat64Array()
var _prev: PackedFloat64Array = PackedFloat64Array()
var _re: PackedFloat64Array = PackedFloat64Array()
var _im: PackedFloat64Array = PackedFloat64Array()
var _acc_re: PackedFloat64Array = PackedFloat64Array()
var _acc_im: PackedFloat64Array = PackedFloat64Array()


## Prepare for `ir` with `block_size` (rounded up to a power of two, minimum 2).
func setup(ir: PackedFloat32Array, new_block_size: int) -> void:
	var b: int = 2
	while b < new_block_size:
		b *= 2
	block_size = b
	_n = 2 * b
	_half = b
	_init_fft()
	var ir_len: int = maxi(ir.size(), 1)
	_parts = (ir_len + b - 1) / b
	_h_re.resize(_parts * (_half + 1))
	_h_im.resize(_parts * (_half + 1))
	for p in _parts:
		for i in _n:
			_re[i] = 0.0
			_im[i] = 0.0
		var base: int = p * b
		for i in b:
			var idx: int = base + i
			if idx < ir.size():
				_re[i] = ir[idx]
		_fft(false)
		var off: int = p * (_half + 1)
		for k in _half + 1:
			_h_re[off + k] = _re[k]
			_h_im[off + k] = _im[k]
	_fdl_re.resize(_parts * (_half + 1))
	_fdl_im.resize(_parts * (_half + 1))
	_prev.resize(b)
	_acc_re.resize(_half + 1)
	_acc_im.resize(_half + 1)
	reset()


## Clears all streaming state (input history and spectra), keeps the IR.
func reset() -> void:
	_fdl_re.fill(0.0)
	_fdl_im.fill(0.0)
	_prev.fill(0.0)
	_head = 0


## Number of IR partitions (tail length in blocks).
func partition_count() -> int:
	return _parts


## Convolves one block (size must equal block_size). Returns an empty array otherwise.
func process(block: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var b: int = block_size
	if b == 0 or block.size() != b:
		return out
	var stride: int = _half + 1
	for i in b:
		_re[i] = _prev[i]
		var s: float = block[i]
		_re[b + i] = s
		_prev[i] = s
	_im.fill(0.0)
	_fft(false)
	_head = (_head - 1 + _parts) % _parts
	var head_off: int = _head * stride
	for k in stride:
		_fdl_re[head_off + k] = _re[k]
		_fdl_im[head_off + k] = _im[k]
	_acc_re.fill(0.0)
	_acc_im.fill(0.0)
	for p in _parts:
		var slot: int = (_head + p) % _parts
		var xo: int = slot * stride
		var ho: int = p * stride
		for k in stride:
			var xr: float = _fdl_re[xo + k]
			var xi: float = _fdl_im[xo + k]
			var hr: float = _h_re[ho + k]
			var hi: float = _h_im[ho + k]
			_acc_re[k] += xr * hr - xi * hi
			_acc_im[k] += xr * hi + xi * hr
	for k in stride:
		_re[k] = _acc_re[k]
		_im[k] = _acc_im[k]
	for k in range(1, _half):
		_re[_n - k] = _acc_re[k]
		_im[_n - k] = -_acc_im[k]
	_fft(true)
	out.resize(b)
	for i in b:
		out[i] = _re[b + i]
	return out


## Reference O(N*M) convolution (full length n + m - 1), used for validation.
static func direct_convolve(x: PackedFloat32Array, h: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if x.is_empty() or h.is_empty():
		return out
	out.resize(x.size() + h.size() - 1)
	for i in x.size():
		var xi: float = x[i]
		if xi == 0.0:
			continue
		for j in h.size():
			out[i + j] += xi * h[j]
	return out


func _init_fft() -> void:
	var n: int = _n
	_cos.resize(n / 2)
	_sin.resize(n / 2)
	for i in n / 2:
		var a: float = TAU * float(i) / float(n)
		_cos[i] = cos(a)
		_sin[i] = sin(a)
	_rev.resize(n)
	var bits: int = 0
	while (1 << bits) < n:
		bits += 1
	for i in n:
		var r: int = 0
		for j in bits:
			if i & (1 << j):
				r |= 1 << (bits - 1 - j)
		_rev[i] = r
	_re.resize(n)
	_im.resize(n)


## In-place radix-2 FFT on _re/_im. Inverse is scaled by 1/N.
func _fft(inverse: bool) -> void:
	var n: int = _n
	for i in n:
		var j: int = _rev[i]
		if j > i:
			var tr: float = _re[i]
			_re[i] = _re[j]
			_re[j] = tr
			var ti: float = _im[i]
			_im[i] = _im[j]
			_im[j] = ti
	var sign: float = 1.0 if inverse else -1.0
	var size: int = 2
	while size <= n:
		var half_size: int = size / 2
		var step: int = n / size
		var start: int = 0
		while start < n:
			for k in half_size:
				var wr: float = _cos[k * step]
				var wi: float = sign * _sin[k * step]
				var a: int = start + k
				var c: int = a + half_size
				var xr: float = _re[c] * wr - _im[c] * wi
				var xi: float = _re[c] * wi + _im[c] * wr
				_re[c] = _re[a] - xr
				_im[c] = _im[a] - xi
				_re[a] += xr
				_im[a] += xi
			start += size
		size *= 2
	if inverse:
		var inv: float = 1.0 / float(n)
		for i in n:
			_re[i] *= inv
			_im[i] *= inv
