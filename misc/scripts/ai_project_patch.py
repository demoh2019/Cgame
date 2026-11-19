#!/usr/bin/env python3
"""Review model-proposed game edits and stage a verified project copy.

Nothing executes. The original project is never changed; stage requires explicit
--stage and a previously absent destination outside the source project.
"""

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import unicodedata

MAX_PLAN_BYTES = 2 * 1024 * 1024
MAX_CHANGES = 20
MAX_FILE_BYTES = 96 * 1024
MAX_PROJECT_FILES = 20000
MAX_PROJECT_BYTES = 512 * 1024 * 1024
MAX_DIFF_CHARS = 16000
ALLOWED_EXTENSIONS = {'.gd', '.tscn', '.tres', '.gdshader', '.json', '.md', '.txt', '.svg'}
SKIP_DIRS = {'.git', '.godot', '.import', '.hg', '.svn', '__pycache__'}
RESERVED = {'CON', 'PRN', 'AUX', 'NUL'} | {f'COM{i}' for i in range(1, 10)} | {f'LPT{i}' for i in range(1, 10)}
SHA_RE = re.compile(r'[0-9a-f]{64}\Z')


class PatchError(Exception):
    """Unsafe, stale, ambiguous or invalid edit proposal."""


def valid_path(path):
    if not isinstance(path, str) or not path or len(path) > 1024 or path != unicodedata.normalize('NFC', path):
        raise PatchError('Invalid or non-NFC relative path')
    if path.startswith('/') or '\\' in path or ':' in path:
        raise PatchError(f'Non-portable path: {path!r}')
    for part in path.split('/'):
        if (not part or part in {'.', '..'} or part.startswith('.') or part.endswith((' ', '.')) or part.split('.', 1)[0].endswith(' ')
                or any(c in '<>"|?*' or ord(c) < 32 or ord(c) == 127 for c in part)
                or part.split('.')[0].upper() in RESERVED):
            raise PatchError(f'Unsafe path component: {path!r}')
    if path.split('/')[0].lower() in {'addons', 'ai_generated'}:
        raise PatchError('Editing addons or generated output is not allowed')
    if Path(path).suffix.lower() not in ALLOWED_EXTENSIONS:
        raise PatchError(f'Unsupported resource extension: {path!r}')
    return path


def _safe_source(root, relative):
    path = root
    for part in relative.split('/'):
        path = path / part
        if path.is_symlink():
            raise PatchError(f'Symlink in project path: {relative}')
    return path


def _read_regular(path):
    if path.is_symlink():
        raise PatchError(f'Symlink is not permitted: {path}')
    flags = os.O_RDONLY | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(path, flags)
    try:
        first = os.fstat(fd)
        if not stat.S_ISREG(first.st_mode):
            raise PatchError(f'Not a regular file: {path}')
        with os.fdopen(os.dup(fd), 'rb') as stream:
            content = stream.read(MAX_FILE_BYTES + 1)
        if len(content) > MAX_FILE_BYTES:
            raise PatchError(f'File exceeds the 96 KiB editable limit: {path}')
        last = os.fstat(fd)
        if (first.st_dev, first.st_ino, first.st_size, first.st_mtime_ns) != (last.st_dev, last.st_ino, last.st_size, last.st_mtime_ns):
            raise PatchError(f'File changed during read: {path}')
        return content
    finally:
        os.close(fd)


def _sha(contents):
    return hashlib.sha256(contents).hexdigest()


def load_plan(plan_path):
    if plan_path.is_symlink() or not plan_path.is_file() or plan_path.stat().st_size > MAX_PLAN_BYTES:
        raise PatchError('Plan must be a real JSON file under 2 MiB')
    with plan_path.open('r', encoding='utf-8') as handle:
        plan = json.load(handle)
    if not isinstance(plan, dict) or set(plan) != {'format', 'changes'} or type(plan['format']) is not int or plan['format'] != 1:
        raise PatchError('Unsupported AI patch plan format')
    edits = plan['changes']
    if not isinstance(edits, list) or not 1 <= len(edits) <= MAX_CHANGES:
        raise PatchError('Plan must contain 1 to 20 changes')
    paths = set()
    for edit in edits:
        if not isinstance(edit, dict) or set(edit) not in ({'path', 'expected_sha256', 'content'}, {'path', 'expected_sha256', 'delete'}):
            raise PatchError('Invalid patch operation structure')
        path = valid_path(edit['path'])
        if path.casefold() in paths:
            raise PatchError('Duplicate or case-colliding paths in plan')
        paths.add(path.casefold())
        expected = edit['expected_sha256']
        if expected is not None and (not isinstance(expected, str) or not SHA_RE.fullmatch(expected)):
            raise PatchError('Expected SHA-256 must be lowercase hex or null for new files')
        if 'delete' in edit:
            if edit['delete'] is not True or expected is None:
                raise PatchError('Deletes require delete=true and existing hash')
        else:
            if not isinstance(edit['content'], str) or len(edit['content'].encode('utf-8')) > MAX_FILE_BYTES:
                raise PatchError('Generated file is not UTF-8 text within 96 KiB')
            if path.endswith('.gd') and '@tool' in edit['content']:
                raise PatchError('Generated editor-executable scripts are not allowed')
    return edits


def _scan_project(root):
    if root.is_symlink() or not root.is_dir():
        raise PatchError('Project root must be a real directory')
    if not (root / 'project.godot').is_file() or (root / 'project.godot').is_symlink():
        raise PatchError('project.godot is required')
    seen = {}
    entries = []
    count = 0
    size = 0
    def walk_error(error):
        raise PatchError(f'Cannot read project directory: {error}')
    for current, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
        base = Path(current)
        for name in list(dirs):
            if name in SKIP_DIRS:
                dirs.remove(name)
            elif (base / name).is_symlink():
                raise PatchError(f'Symlink directory in project: {name}')
        dirs.sort()
        for name in sorted(files):
            full = base / name
            relative = full.relative_to(root).as_posix()
            if full.is_symlink() or not full.is_file():
                raise PatchError(f'Unsafe project file: {relative}')
            folded = relative.casefold()
            if folded in seen and seen[folded] != relative:
                raise PatchError(f'Case-insensitive project path collision: {relative}')
            seen[folded] = relative
            count += 1
            size += full.stat().st_size
            if count > MAX_PROJECT_FILES or size > MAX_PROJECT_BYTES:
                raise PatchError('Project snapshot budget exceeded')
            entries.append(relative)
    return entries


def review(root, edits):
    paths = _scan_project(root)
    known = {path.casefold(): path for path in paths}
    planned_creates = set()
    actions = []
    total_diff = ''
    for edit in edits:
        name = edit['path']
        current = known.get(name.casefold())
        if current is not None and current != name:
            raise PatchError(f'Case mismatch with existing resource: {name}')
        expected = edit['expected_sha256']
        if expected is None:
            if current is not None:
                raise PatchError(f'Create would overwrite an existing resource: {name}')
            before = b''
            kind = 'create'
            planned_creates.add(name)
        else:
            if current is None:
                raise PatchError(f'Expected existing resource missing: {name}')
            before = _read_regular(_safe_source(root, current))
            if _sha(before) != expected:
                raise PatchError(f'Stale revision for resource: {name}')
            kind = 'delete' if 'delete' in edit else 'modify'
        if kind == 'delete':
            after = b''
        else:
            after = edit['content'].encode('utf-8')
        try:
            previous = before.decode('utf-8')
        except UnicodeDecodeError as error:
            raise PatchError(f'Cannot edit non-UTF-8 resource: {name}') from error
        if kind == 'modify' and before == after:
            raise PatchError(f'No-op modification: {name}')
        diff = ''.join(difflib.unified_diff(previous.splitlines(keepends=True), after.decode('utf-8').splitlines(keepends=True), fromfile=f'a/{name}', tofile=f'b/{name}'))
        # Bound review payloads so untrusted model output cannot flood logs.
        remaining = MAX_DIFF_CHARS - len(total_diff)
        if remaining > 0:
            total_diff += diff[:remaining]
        actions.append({'path': name, 'action': kind, 'before_sha256': _sha(before) if current is not None else None,
                        'after_sha256': _sha(after) if kind != 'delete' else None})
    # Build the deleted-path lookup once, not once for every source file.
    # Large projects can have thousands of files but only a handful of edits.
    deleted_paths = {action['path'] for action in actions if action['action'] == 'delete'}
    remaining = [path for path in paths if path not in deleted_paths]
    new_names = remaining + list(planned_creates)
    prefixes = set(new_names)
    for name in new_names:
        parts = name.split('/')
        for index in range(1, len(parts)):
            if '/'.join(parts[:index]) in prefixes:
                raise PatchError(f'File/directory conflict involving: {name}')
    return {'ok': True, 'changes': actions, 'diff': total_diff,
            'diff_truncated': len(total_diff) >= MAX_DIFF_CHARS}


def stage(root, edits, report, destination):
    if destination.exists() or destination.is_symlink():
        raise PatchError('Destination already exists')
    if not destination.parent.is_dir() or destination.parent.is_symlink():
        raise PatchError('Destination parent must be an existing real directory')
    if destination.resolve().is_relative_to(root.resolve()):
        raise PatchError('Destination must be outside the source project')
    temp = Path(tempfile.mkdtemp(prefix='.ai-patch-', dir=destination.parent))
    try:
        paths = _scan_project(root)
        for relative in paths:
            source = _safe_source(root, relative)
            target = temp / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_BINARY', 0)
            fd = os.open(source, flags)
            try:
                before = os.fstat(fd)
                if not stat.S_ISREG(before.st_mode):
                    raise PatchError(f'Source changed type: {relative}')
                digest = hashlib.sha256()
                with os.fdopen(os.dup(fd), 'rb') as stream, target.open('xb') as output:
                    while True:
                        block = stream.read(1024 * 1024)
                        if not block:
                            break
                        digest.update(block)
                        output.write(block)
                after = os.fstat(fd)
                if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
                    raise PatchError(f'Source changed during snapshot: {relative}')
            finally:
                os.close(fd)
        # Review the staged snapshot again: reject any drift since preflight.
        updated = review(temp, edits)
        if updated['changes'] != report['changes']:
            raise PatchError('Project changed between review and staging')
        for edit in edits:
            path = temp / edit['path']
            if 'delete' in edit:
                path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open('w', encoding='utf-8', newline='\n') as target:
                    target.write(edit['content'])
        if destination.exists() or destination.is_symlink():
            raise PatchError('Destination created concurrently')
        os.rename(temp, destination)
    except BaseException:
        shutil.rmtree(temp)
        raise
    return destination


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('plan', type=Path)
    parser.add_argument('--stage', type=Path, help='Explicitly create a new reviewed project copy')
    args = parser.parse_args(argv)
    try:
        edits = load_plan(args.plan)
        report = review(args.project, edits)
        if args.stage is not None:
            report['staged_to'] = str(stage(args.project, edits, report, args.stage))
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0
    except (PatchError, OSError, ValueError, UnicodeError, json.JSONDecodeError) as error:
        print(f'ai_project_patch: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
