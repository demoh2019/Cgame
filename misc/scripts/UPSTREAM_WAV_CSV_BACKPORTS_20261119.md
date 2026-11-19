# Cgame upstream WAV / CSV backports — 2026-11-19

Target: `demoh2019/Cgame` branch `develop`.

## Included

- [Godot #123401](https://github.com/godotengine/godot/pull/123401):
  reimport changed `csv_translation` files saved from the editor's text
  editing view. Save text to disk, update the file metadata, identify its
  registered importer via `ResourceFormatImporter`, and only run reimport
  for `csv_translation`. Unrelated text files must not reimport.
- [Godot #123812](https://github.com/godotengine/godot/pull/123812):
  unify exclusive loop sample limits between WAV import and mixer.
  Correct `-1` to represent the sample count (exclusive end), clamp
  negative or overlong limits to the valid range, avoid duplicated
  ping-pong endpoint playback, and avoid QOA decoder allocation of an
  extra sample.

The upstream PRs were still open when inspected. Source hunks were
matched exactly against the live fork before application; revisit if
upstream changes.

## Test coverage

- Two new native `[Audio][AudioStreamWAV]` tests exercise:
  six negative/overlong loop endpoint combinations on 64-frame PCM16
  WAV; and forward, ping-pong, backward modes on 32-frame PCM8 WAV.
- 18 source-invariant tests in
  `misc/scripts/tests/test_upstream_wav_csv_20261119.py`, covering
  both path-specific CSV reimport and WAV loop/decoder boundaries.
- GitHub Actions workflow at
  `.github/workflows/upstream-wav-csv-regressions.yml`
  runs source guards on Python 3.10 and 3.13.

Source guard command:
```bash
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_wav_csv_20261119.py -v
```

For native verification, build Cgame with `tests=yes`, run
`[AudioStreamWAV]` tests, then manually save a CSV translation while
the editor runs, verifying translation import fires once and ordinary
text files do not reimport.

**Limitations:** No compiled Godot runtime/editor or audio mixer was
available during source authoring. Source checks do not validate native
tests or audio behavior. CI results must be reviewed before release.

## Deferred risky patch

Upstream [#121025](https://github.com/godotengine/godot/pull/121025)
fixes LoadToken leaks but includes a reviewer-reported potential
resource load deadlock dated 2026-11-18. Do not integrate unreviewed
until the race is resolved and multithreaded stress tests pass.
