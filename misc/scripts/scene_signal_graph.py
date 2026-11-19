#!/usr/bin/env python3
"""Read-only Godot scene signal connection graph for AI gameplay debugging.

Complement to scene_context_export.py: inspect editor-wired signal edges only,
without reading scripts, arbitrary node properties, or executing project code.
"""

import argparse
import json
import os
from pathlib import Path
import re
import sys

from scene_context_export import SceneContextError, attributes, safe_path

SECTION = re.compile(r'^\[(node|connection)\s+(.*)\]\s*$')
SKIP_DIRS = {'.git', '.godot', '.hg', '.svn', '__pycache__', 'addons'}
MAX_SCENES = 32
MAX_SCENE_BYTES = 512 * 1024
MAX_NODES = 2048
MAX_CONNECTIONS = 8192
MAX_OUTPUT_BYTES = 512 * 1024


def _node_relative(value):
    if not isinstance(value, str):
        raise SceneContextError('Missing connection endpoint')
    if value == '.':
        return '.'
    if not value or value.startswith('/') or '\\' in value or ':' in value:
        raise SceneContextError('Unsafe connection endpoint')
    if any(p in ('', '.', '..') or any(ord(c) < 32 for c in p) for p in value.split('/')):
        raise SceneContextError('Unsafe connection endpoint')
    return value


def parse_connections(text, uri):
    """Static Godot 4 `.tscn` node/signal edge extraction without eval."""
    if '\x00' in text:
        raise SceneContextError('Scene includes NUL')
    if not text.lstrip('\ufeff\n\r \t').startswith('[gd_scene '):
        raise SceneContextError('Not a Godot 4 text scene')
    declared = set()
    edges = []
    root = None
    for raw in text.splitlines():
        m = SECTION.fullmatch(raw.strip())
        if not m:
            continue
        kind, body = m.groups()
        fields = attributes(body)
        if kind == 'node':
            name = fields.get('name', '')
            if not name or name in ('.', '..') or '/' in name or '\\' in name:
                raise SceneContextError('Invalid node name')
            if root is None:
                if 'parent' in fields:
                    raise SceneContextError('Root node must be first')
                root = name
                path = '.'
            else:
                if 'parent' not in fields:
                    raise SceneContextError('Unexpected second root node')
                parent = _node_relative(fields['parent'])
                path = name if parent == '.' else parent + '/' + name
            if path in declared:
                raise SceneContextError('Duplicate node path')
            declared.add(path)
            if len(declared) > MAX_NODES:
                raise SceneContextError('Too many scene nodes')
        elif kind == 'connection':
            required = ('signal', 'from', 'to', 'method')
            if any(key not in fields or not fields[key] for key in required):
                raise SceneContextError('Connection requires signal, from, to and method')
            source = _node_relative(fields['from'])
            target = _node_relative(fields['to'])
            edges.append({'from': source, 'to': target,
                          'signal': fields['signal'], 'method': fields['method']})
            if len(edges) > MAX_CONNECTIONS:
                raise SceneContextError('Too many signal connections')
    if root is None:
        raise SceneContextError('Scene contains no root node')
    edges.sort(key=lambda x: (x['from'], x['to'], x['signal'], x['method']))
    unresolved = sorted({path for edge in edges for path in (edge['from'], edge['to']) if path not in declared})
    return {'scene': uri, 'root': root, 'connection_count': len(edges),
            'connections': edges, 'unresolved_endpoints': unresolved}


def _validate_scene(root, uri):
    if not isinstance(uri, str) or not uri.endswith('.tscn'):
        raise SceneContextError('Only res:// text .tscn scenes are supported')
    path = safe_path(root, uri)
    if not path.is_file():
        raise SceneContextError('Scene not found: ' + uri)
    if path.stat().st_size > MAX_SCENE_BYTES:
        raise SceneContextError('Scene exceeds 512 KiB')
    return path


def discover_scenes(root):
    """Explicit opt-in project scan excluding caches and third-party add-ons."""
    scenes = []

    def onerror(error):
        raise SceneContextError('Could not scan scenes: ' + str(error))

    for current, dirs, files in os.walk(root, followlinks=False, onerror=onerror):
        folder = Path(current)
        for name in list(dirs):
            if name.startswith('.') or name in SKIP_DIRS:
                dirs.remove(name)
            elif (folder / name).is_symlink():
                raise SceneContextError('Symlinked scene directory found')
        dirs.sort()
        for name in sorted(files):
            if not name.endswith('.tscn'):
                continue
            uri = 'res://' + (folder / name).relative_to(root).as_posix()
            _validate_scene(root, uri)
            scenes.append(uri)
            if len(scenes) > MAX_SCENES:
                raise SceneContextError('Too many scenes; specify --scene explicitly')
    return scenes


def build_graph(project, selected=(), all_scenes=False):
    root = Path(project).absolute()
    if (root.is_symlink() or not root.is_dir() or
            (root / 'project.godot').is_symlink() or not (root / 'project.godot').is_file()):
        raise SceneContextError('Project requires a real project.godot directory')
    if bool(selected) == bool(all_scenes):
        raise SceneContextError('Choose --scene or --all-scenes')
    if all_scenes:
        scene_uris = discover_scenes(root)
    else:
        scene_uris = sorted(selected)
        if len(scene_uris) > MAX_SCENES or len(scene_uris) != len(set(scene_uris)):
            raise SceneContextError('Too many or duplicate selected scenes')
    parsed = []
    for uri in scene_uris:
        path = _validate_scene(root, uri)
        try:
            content = path.read_text(encoding='utf-8-sig')
        except (OSError, UnicodeError) as error:
            raise SceneContextError('Cannot read scene ' + uri) from error
        parsed.append(parse_connections(content, uri))
    return {'format': 1, 'summary': {'scenes': len(parsed),
            'connections': sum(s['connection_count'] for s in parsed),
            'unresolved_endpoints': sum(len(s['unresolved_endpoints']) for s in parsed)},
            'scenes': parsed}


def to_json(graph):
    result = json.dumps(graph, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n'
    if len(result.encode('utf-8')) > MAX_OUTPUT_BYTES:
        raise SceneContextError('Signal graph exceeds output budget')
    return result


def to_dot(graph):
    """Generate graphviz edges with escaped quoted labels; no raw DOT injection."""
    lines = ['digraph SceneSignals {', '  rankdir=LR;']
    for scene in graph['scenes']:
        prefix = scene['scene'] + '#'
        for edge in scene['connections']:
            source = json.dumps(prefix + edge['from'], ensure_ascii=False)
            target = json.dumps(prefix + edge['to'], ensure_ascii=False)
            label = json.dumps(edge['signal'] + ' -> ' + edge['method'], ensure_ascii=False)
            lines.append('  ' + source + ' -> ' + target + ' [label=' + label + '];')
    lines.append('}')
    output = '\n'.join(lines) + '\n'
    if len(output.encode('utf-8')) > MAX_OUTPUT_BYTES:
        raise SceneContextError('Signal graph exceeds output budget')
    return output


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument('--scene', action='append', help='Selected res://scene.tscn (repeatable)')
    choice.add_argument('--all-scenes', action='store_true', help='Explicitly scan local project scenes')
    parser.add_argument('--format', choices=('json', 'dot'), default='json')
    args = parser.parse_args(argv)
    try:
        graph = build_graph(args.project, args.scene or (), args.all_scenes)
        print(to_dot(graph) if args.format == 'dot' else to_json(graph), end='')
        return 0
    except (SceneContextError, OSError) as error:
        print('scene_signal_graph: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
