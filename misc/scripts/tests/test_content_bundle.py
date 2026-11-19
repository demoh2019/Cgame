"""Regression coverage for deterministic offline game content packs."""
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import content_bundle as cb
import content_manifest as cm


class BundleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.project = self.base / 'project'
        self.project.mkdir()
        self.file('assets/hello.txt', b'hello, world!')
        self.file('godot.cfg', b'example=1')
        self.manifest = self.project / 'release.json'
        self.bundle = self.base / 'pack.zip'
        self.dest = self.base / 'installed'
        self.make_manifest()

    def file(self, name, data):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def make_manifest(self):
        entries = []
        for path in sorted(self.project.rglob('*')):
            if not path.is_file() or path == self.manifest:
                continue
            data = path.read_bytes()
            entries.append({'path': path.relative_to(self.project).as_posix(),
                            'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
        self.manifest.write_text(json.dumps({'format': 1, 'files': entries}), encoding='utf8')

    def pack(self):
        return cb.pack(self.project, self.manifest, self.bundle)

    def rewrite(self, mutator):
        with zipfile.ZipFile(self.bundle) as src:
            rows = [(item, src.read(item)) for item in src.infolist()]
        with zipfile.ZipFile(self.bundle, 'w') as dest:
            for info, data in rows:
                dest.writestr(*mutator(info, data))

    def test_pack_and_verify(self):
        self.assertEqual(self.pack()['files'], 2)
        self.assertEqual(cb.verify(self.bundle)['files'], 2)

    def test_extraction(self):
        self.pack()
        self.assertEqual(cb.extract(self.bundle, self.dest)['files'], 2)
        self.assertEqual((self.dest / 'assets/hello.txt').read_bytes(), b'hello, world!')
        self.assertFalse((self.dest / 'release.json').exists())

    def test_identical_zip_bytes_on_rebuild(self):
        self.pack()
        first = self.bundle.read_bytes()
        self.bundle.unlink()
        self.pack()
        self.assertEqual(self.bundle.read_bytes(), first)

    def test_archive_member_order(self):
        self.pack()
        with zipfile.ZipFile(self.bundle) as archive:
            self.assertEqual(archive.namelist(), ['manifest.json', 'content/assets/hello.txt', 'content/godot.cfg'])

    def test_fixed_zip_metadata(self):
        self.pack()
        with zipfile.ZipFile(self.bundle) as archive:
            for info in archive.infolist():
                self.assertEqual(info.date_time, cb.FIXED_DATE)
                self.assertEqual(info.compress_type, zipfile.ZIP_STORED)

    def test_empty_project(self):
        (self.project / 'assets/hello.txt').unlink()
        (self.project / 'godot.cfg').unlink()
        self.make_manifest()
        self.pack()
        self.assertEqual(cb.verify(self.bundle)['files'], 0)
        cb.extract(self.bundle, self.dest)
        self.assertTrue(self.dest.is_dir())

    def test_non_ascii_filename(self):
        self.file('assets/тест.txt', b'data')
        self.make_manifest()
        self.pack()
        cb.extract(self.bundle, self.dest)
        self.assertEqual((self.dest / 'assets/тест.txt').read_bytes(), b'data')

    def test_does_not_replace_existing_zip(self):
        self.bundle.write_bytes(b'keep')
        with self.assertRaises(cb.BundleError): self.pack()
        self.assertEqual(self.bundle.read_bytes(), b'keep')

    def test_reject_output_inside_project(self):
        with self.assertRaises(cb.BundleError):
            cb.pack(self.project, self.manifest, self.project / 'pack.zip')

    def test_reject_project_changed_after_manifest(self):
        self.file('godot.cfg', b'modified')
        with self.assertRaises(cb.BundleError): self.pack()
        self.assertFalse(self.bundle.exists())

    def test_reject_extra_project_file(self):
        self.file('unexpected.txt', b'x')
        with self.assertRaises(cb.BundleError): self.pack()

    def test_reject_missing_project_file(self):
        (self.project / 'godot.cfg').unlink()
        with self.assertRaises(cb.BundleError): self.pack()

    def test_reject_source_symlink(self):
        (self.project / 'godot.cfg').unlink()
        try: (self.project / 'godot.cfg').symlink_to(self.base / 'elsewhere')
        except (OSError, NotImplementedError): self.skipTest('symlink not supported')
        with self.assertRaises((cb.BundleError, cm.ManifestError)): self.pack()

    def test_bad_zip_signature(self):
        self.bundle.write_bytes(b'not a zip')
        with self.assertRaises(zipfile.BadZipFile): cb.verify(self.bundle)

    def test_reject_archive_extra_file(self):
        self.pack()
        with zipfile.ZipFile(self.bundle, 'a') as archive:
            archive.writestr('evil.txt', b'data')
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_archive_missing_member(self):
        self.pack()
        with zipfile.ZipFile(self.bundle) as src:
            items = [(info, src.read(info)) for info in src.infolist() if info.filename!='content/godot.cfg']
        with zipfile.ZipFile(self.bundle, 'w') as dst:
            for i,data in items: dst.writestr(i,data)
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_duplicate_members(self):
        self.pack()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(self.bundle, 'a') as archive:
                archive.writestr('content/godot.cfg', b'evil')
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_invalid_traversal_manifest(self):
        self.pack()
        def mutate(info, data):
            if info.filename == 'manifest.json':
                doc = json.loads(data)
                doc['files'][0]['path'] = '../escape.txt'
                data = json.dumps(doc).encode()
            return info, data
        self.rewrite(mutate)
        with self.assertRaises((cm.ManifestError, cb.BundleError)): cb.extract(self.bundle, self.dest)
        self.assertFalse(self.dest.exists())

    def test_reject_corrupt_content(self):
        self.pack()
        def mutate(info, data):
            if info.filename == 'content/godot.cfg': data=b'BADCONTENT'
            return info,data
        self.rewrite(mutate)
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_failed_extract_cleans_stage(self):
        self.pack()
        def mutate(info, data):
            if info.filename == 'content/godot.cfg': data=b'BADCONTENT'
            return info,data
        self.rewrite(mutate)
        with self.assertRaises(cb.BundleError): cb.extract(self.bundle, self.dest)
        self.assertFalse(self.dest.exists())
        self.assertEqual(list(self.base.glob('.godot-bundle-stage-*')), [])

    def test_reject_wrong_content_size(self):
        self.pack()
        def mutate(info, data):
            if info.filename == 'content/godot.cfg': data=b'changed length'
            return info,data
        self.rewrite(mutate)
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_zip_symlink(self):
        self.pack()
        def mutate(info, data):
            if info.filename == 'content/godot.cfg':
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
            return info,data
        self.rewrite(mutate)
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_directory_member(self):
        self.pack()
        with zipfile.ZipFile(self.bundle, 'a') as archive:
            archive.writestr('directory/', b'')
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_oversized_manifest_member(self):
        self.pack()
        def mutate(info, data):
            if info.filename == 'manifest.json': data=b'x'*(cm.MAX_MANIFEST_BYTES+1)
            return info,data
        self.rewrite(mutate)
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_unsupported_compression(self):
        self.pack()
        def mutate(info, data):
            if info.filename == 'content/godot.cfg': info.compress_type=zipfile.ZIP_DEFLATED
            return info,data
        self.rewrite(mutate)
        with self.assertRaises(cb.BundleError): cb.verify(self.bundle)

    def test_reject_existing_destination(self):
        self.pack()
        self.dest.mkdir()
        sentinel = self.dest / 'keep.txt'
        sentinel.write_text('keep')
        with self.assertRaises(cb.BundleError): cb.extract(self.bundle, self.dest)
        self.assertEqual(sentinel.read_text(), 'keep')

    def test_reject_destination_symlink(self):
        self.pack()
        try: self.dest.symlink_to(self.project, target_is_directory=True)
        except (OSError, NotImplementedError): self.skipTest('symlink not supported')
        with self.assertRaises(cb.BundleError): cb.extract(self.bundle, self.dest)

    def test_reject_manifest_size_limit(self):
        self.file('file.bin', b'anything')
        self.make_manifest()
        with patch.object(cb, 'MAX_TOTAL_BYTES', 1):
            with self.assertRaises(cb.BundleError): self.pack()

    def test_cli_pack_verify_extract(self):
        exe = Path(cb.__file__)
        for args in [('pack', self.project, self.manifest, self.bundle),
                     ('verify', self.bundle), ('extract', self.bundle, self.dest)]:
            outcome = subprocess.run([sys.executable, str(exe), *map(str, args)], capture_output=True, text=True)
            self.assertEqual(outcome.returncode, 0, outcome.stderr)
            self.assertEqual(json.loads(outcome.stdout)['files'], 2)

    def test_cli_invalid_bundle_exit_2(self):
        process = subprocess.run([sys.executable, str(Path(cb.__file__)), 'verify', self.bundle],
                                 text=True, capture_output=True)
        self.assertEqual(process.returncode, 2)
        self.assertIn('content_bundle:', process.stderr)


if __name__ == '__main__':
    unittest.main()
