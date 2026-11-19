Image blend memory and CPU hot-path

The Image::blend_rect() and Image::blend_rect_mask() implementations repeatedly fetched CowData pointers when using get_pixel() / set_pixel() for each pixel. The new fast path holds source and destination pointers across each operation, with copy-on-write detachment occurring once before the loop. The format-aware color decoding, encoding and Color::blend() equation remain unchanged. RGBA8 masks use a direct alpha-byte check.

Self-blending and destination-mask aliasing use the original scalar loops, preserving sequential read/write semantics. Compressed and other unsupported fast-path cases also preserve their fallback.

Memory: No scratch arrays or new persistent caches are introduced.

Tests: Five native cases cover RGBA8, RGB8, LA8, RGBAF, clipping, transparency, COW and aliasing. Twenty source-level contracts verify the fast path. GitHub Actions builds the native editor and runs the native tests.

No measured full-engine FPS, peak RSS or allocator deltas: run comparable before/after profiling on representative compositing scenes. Tiny rectangles may show little benefit due to dispatch overhead.
