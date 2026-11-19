# Image masked-blit hot path (RGBA8)

`Image::blit_rect_mask` historically converted a mask pixel into a `Color` per
output pixel and copied every selected source pixel byte-by-byte.

The new fast path is restricted to an **RGBA8 mask** and source / mask images
that do not alias the destination. RGBA8 alpha is the fourth byte and its
zero/nonzero test exactly matches `get_pixel(...).a != 0`; this does not require
normalizing that byte into a `Color`. Consecutive pixels with nonzero alpha are
copied as a contiguous byte span using `memcpy`. Fully transparent spans are
skipped, and the source/destination row strides remain independent. Other mask
formats and in-place/aliased operations continue through the original scalar
implementation, which retains its behavior for overlapping writes.

The branch allocates **no additional persistent state or temporary buffers**.
It is particularly useful for large editor painting masks, texture synthesis,
transparent shape masks, and atlas manipulation.

## Correctness checks

* 15,000 deterministic standalone C++ byte-exact comparisons across byte sizes
  1/2/3/4/8/16, transparent, opaque, alternating and mixed mask patterns,
  varying cropped source/destination positions and independent row strides.
* Four native Cgame Image tests comparing the RGBA8 optimized path against the
  existing RGBAF-mask scalar path, including clipping and image aliasing.
* 17 Python structural contracts.
* GitHub CI compiles the C++ harness under GCC and Clang and separately builds
  Cgame's native Linux editor to run its Image tests.

## Performance scope

On one local synthetic 1920x1080 RGBA8 test, 35 repeated masked transfers with
64-pixel contiguous runs, the standalone scalar copy took about 380–398 ms and
the block-copy model 53–54 ms across GCC/Clang O3. The scalar harness does not
include the full runtime cost of `Image::get_pixel`, so it is not a direct
measurement of the engine. These numbers are **not game FPS or a universal
speedup**. Benchmark actual editor painting and texture generation workloads,
including checkerboard masks and self-blits, before making broad claims.
