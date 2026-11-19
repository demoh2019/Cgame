# String::replace() single-character fast path

When both the search and replacement strings have exactly one character, use the
existing one-pass `replace_char` algorithm instead of finding every occurrence,
appending match positions to `LocalVector<int>`, allocating a new buffer and
copying around each position. The specialized loop allocates only the result
string (and zero allocations when there is no match or when old=new).

This applies to Unicode `String` replacement and ASCII C-string replacement.
For C strings only, high-bit input bytes are delegated to the old code so that
encoding interpretation is unchanged. Embedded NUL characters in `String`
arguments likewise retain the generic path. Multi-character, deletion, and
case-insensitive replacements keep their existing implementations.

Run structural and native regressions:

```sh
python -m unittest discover -s misc/scripts/tests -p test_string_replace_single_char.py -v
scons platform=linuxbsd target=editor tests=yes dev_build=yes
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case='[String]*'
```

This is a complexity and allocation-path improvement, not a universal measured
FPS claim. Benchmark using long strings with many one-character replacements and
collect allocations and frame times before and after.

Single-character deletion (`replace("x", "")`) uses `remove_char()` with no match
positions buffer. Repeating an empty `String` with a positive repeat count
returns the same empty COW buffer without a resize/write operation.
