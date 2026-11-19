#!/usr/bin/env python3
"""Read-only static resource reference graph and transitive source-size report.

Scope: quoted res:// literals in Godot text resources, not runtime dependencies.
"""

import argparse
import json
import re
from pathlib import Path
import sys

from asset_size_map import AssetSizeError, scan_project

TEXT_EXTENSIONS = frozenset({".tscn", ".tres", ".gd", ".cs", ".gdshader", ".gdshaderinc", ".shader", ".gdextension"})
MAX_TEXT_BYTES = 8 * 1024 * 1024
MAX_ROOTS = 100
# Search for meaningful lexer tokens in C instead of walking every ordinary
# source character in Python. Patterns preserve the scanner's comment rules.
_HASH_TOKENS = re.compile(r"""[#'"]""")
_CPP_TOKENS = re.compile(r"""[/'"]""")
_QUOTE_TOKENS = re.compile(r"""['"]""")
_RESERVED_STEMS = frozenset(
    {"CON", "PRN", "AUX", "NUL"}
    | {"COM" + str(i) for i in range(1, 10)}
    | {"LPT" + str(i) for i in range(1, 10)}
)


class ReferenceMapError(ValueError):
    """A project, root, or static dependency is unsafe or cannot be inspected."""


def _references(text, suffix):
    """Extract quoted literal res:// paths, skipping source-language comments.

    This is a conservative source scanner, not a full GDScript/scene parser.
    """
    result = set()
    index = 0
    length = len(text)
    block_comment = False
    hash_comments = suffix in {".gd", ".tscn", ".tres"}
    cpp_comments = suffix in {".cs", ".gdshader", ".gdshaderinc", ".shader"}
    tokens = _HASH_TOKENS if hash_comments else (_CPP_TOKENS if cpp_comments else _QUOTE_TOKENS)
    while index < length:
        if block_comment:
            closing = text.find("*/", index)
            if closing < 0:
                break
            block_comment = False
            index = closing + 2
            continue
        token = tokens.search(text, index)
        if token is None:
            break
        index = token.start()
        char = text[index]
        if hash_comments and char == "#":
            ending = text.find("\n", index)
            index = length if ending < 0 else ending + 1
            continue
        if cpp_comments and text.startswith("//", index):
            ending = text.find("\n", index)
            index = length if ending < 0 else ending + 1
            continue
        if cpp_comments and text.startswith("/*", index):
            block_comment = True
            index += 2
            continue
        if char in ("'", '"'):
            quote = char
            value_start = index + 1
            search_from = value_start
            # Let the C-level string search skip ordinary literal content.
            # A quote closes only when preceded by an even number of slashes.
            # This preserves escaped quotes and original literal backslashes,
            # without building a character list for unrelated strings.
            while True:
                closing = text.find(quote, search_from)
                if closing < 0:
                    index = length
                    break
                escaped = False
                scan = closing - 1
                while scan >= value_start and text[scan] == "\\":
                    escaped = not escaped
                    scan -= 1
                if escaped:
                    search_from = closing + 1
                    continue
                if text.startswith("res://", value_start):
                    result.add(text[value_start + 6:closing])
                index = closing + 1
                break
            continue
        index += 1
    return sorted(result)


def _portable_path(path):
    """Reject traversal, absolute/ambiguous paths and Windows-incompatible names."""
    if not isinstance(path, str) or not path or len(path) > 4096:
        raise ReferenceMapError("Empty or oversized res:// path")
    if any(c in path for c in ('\\', '\x00', ':')) or path.startswith('/'):
        raise ReferenceMapError("Resource path must be POSIX relative")
    for component in path.split('/'):
        stem = component.split('.', 1)[0].upper()
        if (component in ('', '.', '..') or component.endswith((' ', '.'))
                or stem in _RESERVED_STEMS
                or any(ord(c) < 32 or c in '<>"|?*' for c in component)):
            raise ReferenceMapError("Non-portable resource path component")
    return path


def _resolve_roots(roots, index):
    if not roots or len(roots) > MAX_ROOTS:
        raise ReferenceMapError("Provide 1 to {} --root entries".format(MAX_ROOTS))
    resolved = set()
    for root in roots:
        if root.startswith('res://'):
            root = root[6:]
        _portable_path(root)
        if root not in index:
            raise ReferenceMapError("Unknown project asset root: {}".format(root))
        resolved.add(root)
    return sorted(resolved)


def build_reference_map(project, roots, max_text_bytes=MAX_TEXT_BYTES, max_total_bytes=None):
    """Return reference graph and deduplicated transitive size for selected roots."""
    if type(max_text_bytes) is not int or max_text_bytes < 1:
        raise ReferenceMapError("max_text_bytes must be a positive integer")
    if max_total_bytes is not None and (type(max_total_bytes) is not int or max_total_bytes < 0):
        raise ReferenceMapError("max_total_bytes must be nonnegative")
    project = Path(project)
    files = scan_project(project)  # Reuse size-map scanning/symlink/collision checks.
    index = {asset["path"]: asset["bytes"] for asset in files}
    root_paths = _resolve_roots(roots, index)
    portable_index = {path.casefold(): path for path in index}
    graph = {}
    problems_by_source = {}

    def direct(source):
        if source in graph:
            return graph[source]
        suffix = Path(source).suffix.casefold()
        if suffix not in TEXT_EXTENSIONS:
            graph[source] = []
            return graph[source]
        size = index[source]
        if size > max_text_bytes:
            raise ReferenceMapError("Text resource exceeds read limit: {}".format(source))
        # scan_project has already checked the tree, but reject symlink replacement.
        full_path = project / source
        if full_path.is_symlink():
            raise ReferenceMapError("Resource became a symlink: {}".format(source))
        try:
            text = full_path.read_text(encoding='utf-8')
        except (OSError, UnicodeError) as error:
            raise ReferenceMapError("Cannot read text resource {}: {}".format(source, error)) from error
        references = []
        issues = []
        for target in _references(text, suffix):
            try:
                _portable_path(target)
            except ReferenceMapError:
                issues.append({"source": source, "reference": "res://" + target, "kind": "invalid"})
                continue
            if target not in index:
                equivalent = portable_index.get(target.casefold())
                issue = {"source": source, "reference": "res://" + target,
                         "kind": "case_mismatch" if equivalent is not None else "missing"}
                if equivalent is not None:
                    issue["actual"] = "res://" + equivalent
                issues.append(issue)
                continue
            references.append(target)
        graph[source] = sorted(set(references))
        problems_by_source[source] = sorted(issues, key=lambda issue: (issue["reference"], issue["kind"]))
        return graph[source]

    per_root = []
    combined = set()
    for root in root_paths:
        # Mark at enqueue time: on dense shared-dependency graphs the old
        # pop-time check could schedule the same resource thousands of times.
        seen = {root}
        pending = [root]
        while pending:
            path = pending.pop()
            for target in direct(path):
                if target not in seen:
                    seen.add(target)
                    pending.append(target)
        per_root.append({"root": "res://" + root, "file_count": len(seen),
                         "total_bytes": sum(index[path] for path in seen)})
        combined.update(seen)

    referenced_by = {node: [] for node in combined}
    for source in sorted(combined):
        for target in graph[source]:
            referenced_by[target].append(source)
    total = sum(index[node] for node in combined)
    problems = sorted((problem for source in sorted(combined)
                       for problem in problems_by_source.get(source, [])),
                      key=lambda issue: (issue["source"], issue["reference"], issue["kind"]))
    return {
        "format": 1,
        "roots": per_root,
        "combined": {"file_count": len(combined), "total_bytes": total,
                     "files": [{"path": path, "bytes": index[path]} for path in sorted(combined)]},
        "references": {"res://" + source: ["res://" + target for target in graph[source]]
                       for source in sorted(combined)},
        "referenced_by": {"res://" + path: ["res://" + source for source in referenced_by[path]]
                          for path in sorted(combined)},
        "problems": problems,
        "budget": {"limit_bytes": max_total_bytes, "exceeded": max_total_bytes is not None and total > max_total_bytes},
    }


def _nonnegative(value):
    if not value.isascii() or not value.isdecimal():
        raise argparse.ArgumentTypeError("Expected a nonnegative byte count")
    return int(value)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path, help='Directory containing project.godot')
    parser.add_argument('--root', action='append', required=True, help='res:// asset root (repeatable)')
    parser.add_argument('--max-text-bytes', type=_nonnegative, default=MAX_TEXT_BYTES)
    parser.add_argument('--max-total-bytes', type=_nonnegative)
    parser.add_argument('--format', choices=('json', 'text'), default='text')
    args = parser.parse_args(argv)
    try:
        report = build_reference_map(args.project, args.root, args.max_text_bytes, args.max_total_bytes)
    except (AssetSizeError, ReferenceMapError, OSError) as error:
        print('asset_reference_map: {}'.format(error), file=sys.stderr)
        return 2
    if args.format == 'json':
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        for root in report['roots']:
            print('{}: {} files, {} bytes'.format(root['root'], root['file_count'], root['total_bytes']))
        print('Combined: {} unique assets, {} bytes'.format(
            report['combined']['file_count'], report['combined']['total_bytes']))
        for problem in report['problems']:
            print('{}: {}: {}'.format(problem['source'], problem['kind'], problem['reference']))
        if report['budget']['exceeded']:
            print('BUDGET EXCEEDED: {} > {} bytes'.format(report['combined']['total_bytes'],
                                                       report['budget']['limit_bytes']))
    return 1 if report['problems'] or report['budget']['exceeded'] else 0


if __name__ == '__main__':
    sys.exit(main())
