"""Signal topology regressions, including safe read-only CLI behaviour."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scene_signal_graph as g

SCENE = '''[gd_scene format=3]
[node name="Main" type="Control"]
[node name="Button" type="Button" parent="."]
[node name="Panel" type="Panel" parent="."]
[node name="Label" type="Label" parent="Panel"]
[connection signal="pressed" from="Button" to="." method="_on_pressed"]
[connection signal="changed" from="Panel/Label" to="Panel" method="_on_changed"]
secret = "DONOT_EXPORT"
'''

class SignalTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        (self.root/'project.godot').write_text('config_version=5')
        (self.root/'main.tscn').write_text(SCENE)

    def one(self, **kwargs):
        return g.build_graph(self.root, ('res://main.tscn',), **kwargs)

    def bad(self, text):
        with self.assertRaises(g.SceneContextError):
            g.parse_connections(text, 'res://main.tscn')

    def test_edges(self):
        d=self.one()
        self.assertEqual(d['summary'], {'scenes':1, 'connections':2, 'unresolved_endpoints':0})
        self.assertEqual(d['scenes'][0]['connections'][0]['signal'], 'pressed')

    def test_sorted_edges(self):
        d=self.one()['scenes'][0]['connections']
        self.assertEqual([e['from'] for e in d], ['Button', 'Panel/Label'])

    def test_root_endpoint(self):
        self.assertEqual(self.one()['scenes'][0]['connections'][0]['to'], '.')

    def test_no_arbitrary_properties(self):
        self.assertNotIn('DONOT_EXPORT', g.to_json(self.one()))

    def test_dot_is_deterministic(self):
        self.assertEqual(g.to_dot(self.one()),g.to_dot(self.one()))
        self.assertIn('label="pressed -> _on_pressed"',g.to_dot(self.one()))

    def test_dot_escaped_label(self):
        p='[gd_scene format=3]\n[node name="N"]\n[connection signal="a\\\"b" from="." to="." method="m"]'
        out=g.to_dot({'scenes':[g.parse_connections(p,'res://x.tscn')]})
        self.assertIn('a\\\"b',out)

    def test_orphan_endpoints_are_reported(self):
        (self.root/'main.tscn').write_text('[gd_scene format=3]\n[node name="N"]\n[connection signal="clicked" from="Instanced/Child" to="." method="h"]')
        self.assertEqual(self.one()['scenes'][0]['unresolved_endpoints'],['Instanced/Child'])

    def test_empty_connection_set(self):
        (self.root/'main.tscn').write_text('[gd_scene format=3]\n[node name="N"]')
        self.assertEqual(self.one()['summary']['connections'],0)

    def test_unrecognized_section_ignored(self):
        d=g.parse_connections('[gd_scene format=3]\n[sub_resource type="Resource" id="a"]\n[node name="N"]','res://x.tscn')
        self.assertEqual(d['root'],'N')

    def test_no_nodes_fails(self):
        self.bad('[gd_scene format=3]')

    def test_bad_header(self):
        self.bad('[gd_resource format=3]\n[node name="N"]')

    def test_nul(self):
        self.bad(SCENE+'\x00')

    def test_duplicate_path(self):
        self.bad('[gd_scene format=3]\n[node name="N"]\n[node name="X" parent="."]\n[node name="X" parent="."]')

    def test_bad_root_parent(self):
        self.bad('[gd_scene format=3]\n[node name="N" parent="."]')

    def test_second_root(self):
        self.bad('[gd_scene format=3]\n[node name="A"]\n[node name="B"]')

    def test_invalid_node_names(self):
        for s in ('', '..', 'a/b', 'a\\b'):
            with self.subTest(s=s):
                self.bad('[gd_scene format=3]\n[node name='+json.dumps(s)+']')

    def test_invalid_endpoint_paths(self):
        for path in ('../child','/root','x\\y','x//y', 'x/./y'):
            with self.subTest(path=path):
                self.bad('[gd_scene format=3]\n[node name="N"]\n[connection signal="foo" from='+json.dumps(path)+' to="." method="bar"]')

    def test_required_connection_fields(self):
        for missing in ('signal','from','to','method'):
            attrs={'signal':'s','from':'.','to':'.','method':'h'}
            del attrs[missing]
            s=' '.join(k+'='+json.dumps(v) for k,v in attrs.items())
            with self.subTest(missing=missing):
                self.bad('[gd_scene format=3]\n[node name="N"]\n[connection '+s+']')

    def test_node_budget(self):
        with patch.object(g,'MAX_NODES',1):
            with self.assertRaises(g.SceneContextError): self.one()

    def test_edge_budget(self):
        with patch.object(g,'MAX_CONNECTIONS',1):
            with self.assertRaises(g.SceneContextError): self.one()

    def test_output_budget(self):
        with patch.object(g,'MAX_OUTPUT_BYTES',10):
            with self.assertRaises(g.SceneContextError):g.to_json(self.one())
            with self.assertRaises(g.SceneContextError):g.to_dot(self.one())

    def test_missing_project(self):
        (self.root/'project.godot').unlink()
        with self.assertRaises(g.SceneContextError): self.one()

    def test_missing_scene(self):
        with self.assertRaises(g.SceneContextError):g.build_graph(self.root,('res://absent.tscn',))

    def test_wrong_extension(self):
        with self.assertRaises(g.SceneContextError):g.build_graph(self.root,('res://a.gd',))

    def test_traversal(self):
        for x in ('res://../a.tscn','res:///abs.tscn','res://./main.tscn','res://a\\b.tscn'):
            with self.subTest(path=x),self.assertRaises(g.SceneContextError):g.build_graph(self.root,(x,))

    def test_symlink_file(self):
        try:
            (self.root/'alias.tscn').symlink_to(self.root/'main.tscn')
        except (OSError, NotImplementedError):
            self.skipTest('Symlinks unavailable on this platform')
        with self.assertRaises(g.SceneContextError):g.build_graph(self.root,('res://alias.tscn',))

    def test_symlink_dir(self):
        (self.root/'scenes').mkdir()
        try:
            (self.root/'alias').symlink_to(self.root/'scenes',target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest('Directory symlinks unavailable on this platform')
        with self.assertRaises(g.SceneContextError):g.build_graph(self.root,all_scenes=True)

    def test_scene_file_size_limit(self):
        with patch.object(g,'MAX_SCENE_BYTES',1):
            with self.assertRaises(g.SceneContextError):self.one()

    def test_all_scenes(self):
        (self.root/'b.tscn').write_text('[gd_scene format=3]\n[node name="B"]')
        self.assertEqual(g.build_graph(self.root,all_scenes=True)['summary']['scenes'],2)

    def test_skipped_dirs(self):
        for d in ('.godot','.hidden','addons'):
            folder=self.root/d;folder.mkdir()
            (folder/'n.tscn').write_text('[gd_scene format=3]\n[node name="N"]')
        self.assertEqual(g.build_graph(self.root,all_scenes=True)['summary']['scenes'],1)

    def test_scene_selection_required(self):
        with self.assertRaises(g.SceneContextError):g.build_graph(self.root)
        with self.assertRaises(g.SceneContextError):g.build_graph(self.root,('res://main.tscn',),True)

    def test_duplicate_selection(self):
        with self.assertRaises(g.SceneContextError):g.build_graph(self.root,('res://main.tscn','res://main.tscn'))

    def test_cli_json(self):
        c=subprocess.run([sys.executable,str(Path(g.__file__)),str(self.root),'--scene','res://main.tscn'],capture_output=True,text=True)
        self.assertEqual(c.returncode,0,c.stderr)
        self.assertEqual(json.loads(c.stdout)['summary']['connections'],2)

    def test_cli_dot(self):
        c=subprocess.run([sys.executable,str(Path(g.__file__)),str(self.root),'--scene','res://main.tscn','--format','dot'],capture_output=True,text=True)
        self.assertEqual(c.returncode,0,c.stderr)
        self.assertTrue(c.stdout.startswith('digraph'))

    def test_cli_fails(self):
        c=subprocess.run([sys.executable,str(Path(g.__file__)),str(self.root),'--scene','res://missing.tscn'],capture_output=True,text=True)
        self.assertEqual(c.returncode,2)
        self.assertFalse(c.stdout)

if __name__=='__main__':unittest.main()
