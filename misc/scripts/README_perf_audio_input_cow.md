# Audio input hot path: eliminate copy-on-write buffer aliasing

The microphone read and AudioServer input-capture read paths formerly copied
the audio driver's `Vector<int32_t>` **by value** while holding the driver lock.
Godot vectors share copy-on-write storage: even when the capture reader only
reads, an extra live value alias may cause the driver's next `Vector::write`
to detach and copy the entire ring buffer.

Return `const Vector<int32_t> &` from `AudioDriver::get_input_buffer()`, and
keep a read-only reference in the two consumers. This avoids an extra alias,
reference-count traffic, and possible full-buffer detach. It also reduces
transient memory pressure during microphone capture, especially with large
buffers. The existing lock/unlock protocol remains unchanged.

This is a deliberately smaller and safer step towards upstream Godot
[#125533](https://github.com/godotengine/godot/pull/125533). It does **not**
implement that PR's fully lock-free capture or change buffer ownership. The
reference is valid only while the driver lock is held and the buffer is not
resized. Do not store the reference after releasing the lock.

## Verification

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_audio_input_ref_fastpath.py -v
```

Also run the native `[Audio]` tests with an editor build compiled using
`tests=yes`. The tests verify getter type, COW alias properties, the existing
locks and the full read path. Release qualification still requires recording
microphone input under PulseAudio, WASAPI, CoreAudio and Web, including
stop/restart, and comparing allocations and buffer latency with baseline.
