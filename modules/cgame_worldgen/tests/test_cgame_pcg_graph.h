/**************************************************************************/
/*  test_cgame_pcg_graph.h                                                */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "../cgame_pcg_graph.h"

#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "core/templates/hash_set.h"
#include "tests/test_macros.h"

// Mirrors tests/test_pcg_graph.gd: typed pins, determinism, pruning/difference, spline sampling,
// subgraphs, custom nodes, incremental cache, debugger capture, partition cells and presets.
namespace TestCgamePCGGraph {

typedef CgamePCGGraph G;

static Dictionary pts_with_density(const PackedVector3Array &p_positions, const Vector<float> &p_dens) {
	Dictionary d = G::make_points(p_positions);
	Dictionary attrs = d["attrs"];
	PackedFloat32Array arr = attrs["density"];
	for (int i = 0; i < p_dens.size(); i++) {
		arr.set(i, p_dens[i]);
	}
	attrs["density"] = arr;
	return d;
}

static PackedVector3Array origins(const Dictionary &p_mesh_data) {
	PackedVector3Array res;
	const Array recs = p_mesh_data["records"];
	for (int i = 0; i < recs.size(); i++) {
		const Dictionary r = recs[i];
		const Array trs = r["transforms"];
		for (int k = 0; k < trs.size(); k++) {
			res.push_back(Transform3D(trs[k]).origin);
		}
	}
	return res;
}

static double landscape_height_fn(double p_x, double p_z) {
	return Math::sin(p_x * 0.05) * 3.0 + Math::cos(p_z * 0.07) * 2.0;
}

static Ref<G> sampling_graph(bool p_prune) {
	Ref<G> g;
	g.instantiate();
	g->set_graph_seed(77);
	(void)g->add_graph_input("in_v", "volume", "volume");
	Dictionary sample_p;
	sample_p["spacing"] = 3.0;
	sample_p["jitter"] = 0.8;
	(void)g->add_node("sample", "surface_sampler", sample_p);
	Dictionary noise_p;
	noise_p["frequency"] = 0.05;
	(void)g->add_node("noise", "density_noise", noise_p);
	Dictionary filter_p;
	filter_p["min"] = 0.3;
	filter_p["max"] = 1.0;
	(void)g->add_node("filter", "density_filter", filter_p);
	(void)g->add_graph_output("out", "pts", "points");
	(void)g->link("in_v", "out", "sample", "volume");
	(void)g->link("sample", "out", "noise", "in");
	(void)g->link("noise", "out", "filter", "in");
	if (p_prune) {
		Dictionary prune_p;
		prune_p["min_distance"] = 2.5;
		(void)g->add_node("prune", "self_pruning", prune_p);
		(void)g->link("filter", "out", "prune", "in");
		(void)g->link("prune", "out", "out", "in");
	} else {
		(void)g->link("filter", "out", "out", "in");
	}
	return g;
}

static HashSet<String> keyset(const Dictionary &p_points) {
	HashSet<String> res;
	const PackedVector3Array pos = p_points["positions"];
	for (int i = 0; i < pos.size(); i++) {
		res.insert(vformat("%.3f,%.3f,%.3f", pos[i].x, pos[i].y, pos[i].z));
	}
	return res;
}

static Dictionary vol_input(const Variant &p_volume) {
	Dictionary in;
	in["volume"] = p_volume;
	return in;
}

static bool near_value(double p_a, double p_b, double p_tol) {
	return Math::abs(p_a - p_b) <= p_tol;
}

static int64_t hash_of(const Variant &p_value) {
	return (int64_t)p_value.hash();
}

// Custom node callables.
static Dictionary boost_node_full(const Dictionary &p_inputs, const Dictionary &p_params) {
	const Dictionary src = p_inputs["in"];
	Dictionary attrs = Dictionary(src["attrs"]).duplicate();
	PackedFloat32Array dens = PackedFloat32Array(attrs["density"]).duplicate();
	const double factor = p_params.get("factor", 2.0);
	for (int i = 0; i < dens.size(); i++) {
		dens.set(i, (float)(dens[i] * factor));
	}
	attrs["density"] = dens;
	Dictionary boosted;
	boosted["type"] = "points";
	boosted["positions"] = src["positions"];
	boosted["attrs"] = attrs;
	Dictionary out;
	out["out"] = boosted;
	out["count_only"] = src;
	return out;
}

static Dictionary boost_node_single(const Dictionary &p_inputs) {
	const Dictionary src = p_inputs["in"];
	Dictionary attrs = Dictionary(src["attrs"]).duplicate();
	PackedFloat32Array nd = PackedFloat32Array(attrs["density"]).duplicate();
	nd.fill(0.9f);
	attrs["density"] = nd;
	Dictionary boosted;
	boosted["type"] = "points";
	boosted["positions"] = src["positions"];
	boosted["attrs"] = attrs;
	Dictionary out;
	out["out"] = boosted;
	return out;
}

static Dictionary pin_dict(const char *p_name, const char *p_type) {
	Dictionary d;
	d[p_name] = p_type;
	return d;
}

TEST_CASE("[CgamePCGGraph] Typed pins reject incompatible links") {
	Ref<G> g;
	g.instantiate();
	(void)g->add_graph_input("in_v", "volume", "volume");
	(void)g->add_node("sample", "surface_sampler");
	(void)g->add_node("filter", "density_filter");
	CHECK_MESSAGE(g->link("in_v", "out", "sample", "landscape") != "", "volume into a landscape pin is rejected");
	CHECK_MESSAGE(g->link("in_v", "out", "filter", "in") != "", "volume into a points pin is rejected");
	CHECK_MESSAGE(g->link("in_v", "out", "sample", "nope") != "", "unknown pin is rejected");
	CHECK_MESSAGE(g->link("in_v", "out", "sample", "volume") == "", "matching types connect");
	CHECK_MESSAGE(g->link("sample", "out", "filter", "in") == "", "points into points connect");
	CHECK_MESSAGE(g->link("sample", "out", "filter", "in") != "", "a single-input pin takes only one edge");
	CHECK_MESSAGE(g->validate().size() == 0, "valid graph has no errors");

	TypedArray<Dictionary> edges = g->get_edges();
	Dictionary bad;
	bad["from"] = "in_v";
	bad["from_pin"] = "out";
	bad["to"] = "filter";
	bad["to_pin"] = "in";
	edges.push_back(bad);
	CHECK_MESSAGE(g->validate().size() > 0, "validate reports an injected incompatible edge");
	CHECK_MESSAGE(g->execute(Dictionary()).size() == 0, "invalid graphs do not execute");
	CHECK_MESSAGE(g->get_last_errors().size() > 0, "errors are kept in last_errors");

	Ref<G> cyc;
	cyc.instantiate();
	(void)cyc->add_node("a", "density_filter");
	(void)cyc->add_node("b", "density_filter");
	(void)cyc->link("a", "out", "b", "in");
	(void)cyc->link("b", "out", "a", "in");
	CHECK_MESSAGE(cyc->validate().size() > 0, "cycles are validation errors");
	CHECK_MESSAGE((G::pins_compatible("any", "points") && !G::pins_compatible("spline", "points")), "any is a wildcard");
	CHECK(G::pins_compatible("points", "points[]"));

	Ref<G> unk;
	unk.instantiate();
	(void)unk->add_node("x", "no_such_node");
	CHECK_MESSAGE(unk->validate().size() > 0, "unknown node types are validation errors");
}

TEST_CASE("[CgamePCGGraph] Hashing helpers") {
	CHECK(G::mix64(0) == G::mix64(0));
	CHECK(G::mix64(1) != G::mix64(2));
	CHECK(G::hash3(1, 2, 3) == G::mix64(G::mix64(G::mix64(1) ^ 2) ^ 3));
	const double r = G::rand01(G::mix64(12345));
	CHECK((r >= 0.0 && r < 1.0));
}

TEST_CASE("[CgamePCGGraph] Determinism and seeds") {
	const Dictionary vol = G::make_volume(AABB(Vector3(0, 0, 0), Vector3(60, 10, 60)));
	Ref<G> ga = sampling_graph(true);
	Ref<G> gb = sampling_graph(true);
	const Dictionary oa = ga->execute(vol_input(vol));
	const Dictionary ob = gb->execute(vol_input(vol));
	CHECK_MESSAGE(G::point_count(oa["pts"]) > 50, "sampler produces points");
	CHECK_MESSAGE(hash_of(oa) == hash_of(ob), "same seed and inputs give identical output");
	gb->set_graph_seed(78);
	const Dictionary oc = gb->execute(vol_input(vol));
	CHECK_MESSAGE(hash_of(oa) != hash_of(oc), "a different seed changes the output");
}

TEST_CASE("[CgamePCGGraph] Self pruning keeps minimum distance") {
	Ref<G> gp;
	gp.instantiate();
	gp->set_graph_seed(5);
	(void)gp->add_graph_input("v", "volume", "volume");
	Dictionary sp;
	sp["spacing"] = 1.0;
	sp["jitter"] = 1.0;
	(void)gp->add_node("s", "surface_sampler", sp);
	Dictionary pp;
	pp["min_distance"] = 2.0;
	(void)gp->add_node("p", "self_pruning", pp);
	(void)gp->add_graph_output("o", "pruned", "points");
	(void)gp->add_graph_output("o0", "raw", "points");
	(void)gp->link("v", "out", "s", "volume");
	(void)gp->link("s", "out", "p", "in");
	(void)gp->link("p", "out", "o", "in");
	(void)gp->link("s", "out", "o0", "in");
	const Dictionary po = gp->execute(vol_input(G::make_volume(AABB(Vector3(), Vector3(30, 5, 30)))));
	const Dictionary pruned = po["pruned"];
	const PackedVector3Array pos = pruned["positions"];
	double min_d = 1.0e9;
	for (int i = 0; i < pos.size(); i++) {
		for (int j = i + 1; j < pos.size(); j++) {
			min_d = MIN(min_d, (double)pos[i].distance_to(pos[j]));
		}
	}
	CHECK_MESSAGE(min_d >= 2.0 - 0.0001, "survivors are at least min_distance apart");
	CHECK_MESSAGE((G::point_count(pruned) < G::point_count(po["raw"]) && pos.size() > 10), "pruning removes some but not all points");
}

TEST_CASE("[CgamePCGGraph] Difference removes nearby points") {
	Ref<G> gd;
	gd.instantiate();
	(void)gd->add_graph_input("a", "a", "points");
	(void)gd->add_graph_input("b", "b", "points");
	Dictionary dp;
	dp["distance"] = 2.0;
	dp["planar"] = true;
	(void)gd->add_node("d", "difference", dp);
	(void)gd->add_graph_output("o", "res", "points");
	(void)gd->link("a", "out", "d", "in");
	(void)gd->link("b", "out", "d", "other");
	(void)gd->link("d", "out", "o", "in");
	PackedVector3Array grid;
	for (int x = 0; x <= 10; x++) {
		for (int z = 0; z <= 10; z++) {
			grid.push_back(Vector3(x, 0, z));
		}
	}
	PackedVector3Array cut;
	cut.push_back(Vector3(5, 3, 5));
	cut.push_back(Vector3(0, 0, 0));
	Dictionary in;
	in["a"] = G::make_points(grid);
	in["b"] = G::make_points(cut);
	const Dictionary dr = gd->execute(in);
	const PackedVector3Array res_pts = Dictionary(dr["res"])["positions"];
	bool ok_far = true;
	for (int i = 0; i < res_pts.size(); i++) {
		for (int k = 0; k < cut.size(); k++) {
			if (Vector2(res_pts[i].x - cut[k].x, res_pts[i].z - cut[k].z).length() < 2.0) {
				ok_far = false;
			}
		}
	}
	CHECK_MESSAGE(ok_far, "no remaining point is within the difference distance");
	CHECK_MESSAGE((res_pts.size() < grid.size() && res_pts.size() > grid.size() - 30), "only nearby points were removed");
	CHECK_MESSAGE((!res_pts.has(Vector3(5, 0, 5)) && res_pts.has(Vector3(10, 0, 10))), "centre removed, far corner kept");
}

TEST_CASE("[CgamePCGGraph] Spline sampler along and around") {
	Ref<G> gs;
	gs.instantiate();
	(void)gs->add_graph_input("sp", "spline", "spline");
	Dictionary along_p;
	along_p["mode"] = "along";
	along_p["spacing"] = 5.0;
	(void)gs->add_node("along", "spline_sampler", along_p);
	Dictionary off_p;
	off_p["mode"] = "along";
	off_p["spacing"] = 5.0;
	off_p["lateral_offset"] = 3.0;
	(void)gs->add_node("off", "spline_sampler", off_p);
	Dictionary around_p;
	around_p["mode"] = "around";
	around_p["spacing"] = 2.0;
	around_p["band_inner"] = 2.0;
	around_p["band_outer"] = 6.0;
	(void)gs->add_node("around", "spline_sampler", around_p);
	(void)gs->add_graph_output("o1", "along", "points");
	(void)gs->add_graph_output("o2", "off", "points");
	(void)gs->add_graph_output("o3", "around", "points");
	const char *names[3] = { "along", "off", "around" };
	for (const char *n : names) {
		(void)gs->link("sp", "out", n, "spline");
	}
	(void)gs->link("along", "out", "o1", "in");
	(void)gs->link("off", "out", "o2", "in");
	(void)gs->link("around", "out", "o3", "in");

	PackedVector3Array straight;
	straight.push_back(Vector3(0, 0, 0));
	straight.push_back(Vector3(100, 0, 0));
	Dictionary in;
	in["spline"] = G::make_spline(straight);
	const Dictionary so = gs->execute(in);
	const PackedVector3Array along = Dictionary(so["along"])["positions"];
	CHECK_MESSAGE(along.size() == 21, "100 m at 5 m spacing gives 21 points");
	bool spacing_ok = true;
	for (int i = 1; i < along.size(); i++) {
		if (Math::abs((double)along[i].distance_to(along[i - 1]) - 5.0) > 0.001) {
			spacing_ok = false;
		}
	}
	CHECK_MESSAGE(spacing_ok, "consecutive points are spacing apart");
	const PackedVector3Array off_pts = Dictionary(so["off"])["positions"];
	CHECK_MESSAGE(near_value(off_pts[3].z, 3.0, 0.001), "lateral offset moves points sideways");
	const PackedVector3Array around = Dictionary(so["around"])["positions"];
	bool band_ok = around.size() == 102;
	for (int i = 0; i < around.size(); i++) {
		if (Math::abs(around[i].z) < 2.0 - 0.001 || Math::abs(around[i].z) > 6.0 + 0.001) {
			band_ok = false;
		}
	}
	CHECK_MESSAGE(band_ok, "around mode keeps points inside the band on both sides");

	PackedVector3Array bent_pts;
	bent_pts.push_back(Vector3(0, 0, 0));
	bent_pts.push_back(Vector3(10, 0, 0));
	bent_pts.push_back(Vector3(10, 0, 10));
	Dictionary bent_in;
	bent_in["spline"] = G::make_spline(bent_pts);
	const Dictionary bent = gs->execute(bent_in);
	CHECK_MESSAGE(PackedVector3Array(Dictionary(bent["along"])["positions"]).size() == 5, "a bent 20 m path at 5 m gives 5 points");
}

TEST_CASE("[CgamePCGGraph] Subgraphs reuse one graph asset with independent caches") {
	Ref<G> sub;
	sub.instantiate();
	(void)sub->add_graph_input("i", "in", "points");
	Dictionary fp;
	fp["min"] = 0.5;
	(void)sub->add_node("f", "density_filter", fp);
	Dictionary xp;
	xp["scale_min"] = 2.0;
	xp["scale_max"] = 2.0;
	xp["rot_min_deg"] = 0.0;
	xp["rot_max_deg"] = 0.0;
	(void)sub->add_node("x", "transform_points", xp);
	(void)sub->add_graph_output("o", "out", "points");
	(void)sub->link("i", "out", "f", "in");
	(void)sub->link("f", "out", "x", "in");
	(void)sub->link("x", "out", "o", "in");

	Ref<G> par;
	par.instantiate();
	(void)par->add_graph_input("ia", "a", "points");
	(void)par->add_graph_input("ib", "b", "points");
	Dictionary sg;
	sg["graph"] = sub;
	(void)par->add_node("s1", "subgraph", sg);
	(void)par->add_node("s2", "subgraph", sg);
	(void)par->add_graph_output("oa", "ra", "points");
	(void)par->add_graph_output("ob", "rb", "points");
	CHECK_MESSAGE(par->link("ia", "out", "s1", "in") == "", "graph input feeds the subgraph input pin");
	CHECK_MESSAGE(par->link("ib", "out", "s2", "in") == "", "same subgraph asset can be reused");
	CHECK_MESSAGE(par->link("ia", "out", "s1", "nope") != "", "subgraph pins come from its graph inputs");
	(void)par->link("s1", "out", "oa", "in");
	(void)par->link("s2", "out", "ob", "in");

	PackedVector3Array pa_pos;
	for (int i = 0; i < 4; i++) {
		pa_pos.push_back(Vector3(i, 0, 0));
	}
	Vector<float> pa_d;
	pa_d.push_back(0.2f);
	pa_d.push_back(0.6f);
	pa_d.push_back(0.9f);
	pa_d.push_back(0.4f);
	const Dictionary pa = pts_with_density(pa_pos, pa_d);
	PackedVector3Array pb_pos;
	pb_pos.push_back(Vector3(0, 0, 5));
	pb_pos.push_back(Vector3(1, 0, 5));
	Vector<float> pb_d;
	pb_d.push_back(0.7f);
	pb_d.push_back(0.1f);
	const Dictionary pb = pts_with_density(pb_pos, pb_d);
	Dictionary in;
	in["a"] = pa;
	in["b"] = pb;
	const Dictionary sr = par->execute(in);
	CHECK_MESSAGE(G::point_count(sr["ra"]) == 2, "first instance filtered with its own inputs");
	CHECK_MESSAGE(G::point_count(sr["rb"]) == 1, "second instance filtered independently");
	const PackedFloat32Array sscale = Dictionary(Dictionary(sr["ra"])["attrs"])["scale"];
	CHECK_MESSAGE(near_value(sscale[0], 2.0, 0.0001), "subgraph nodes apply their params");
	CHECK_MESSAGE((par->get_executed_nodes().has("s1/f") && par->get_executed_nodes().has("s2/x")), "inner nodes are reported with a prefix");
	(void)par->execute(in);
	CHECK_MESSAGE(par->get_executed_nodes().size() == 0, "unchanged subgraph run is fully cached");

	Vector<float> pb2_d;
	pb2_d.push_back(0.9f);
	pb2_d.push_back(0.9f);
	Dictionary in2;
	in2["a"] = pa;
	in2["b"] = pts_with_density(pb_pos, pb2_d);
	const Dictionary sr2 = par->execute(in2);
	CHECK_MESSAGE(G::point_count(sr2["rb"]) == 2, "changed input flows through the subgraph");
	bool s1_ran = false;
	const TypedArray<String> ran = par->get_executed_nodes();
	for (int i = 0; i < ran.size(); i++) {
		if (String(ran[i]).begins_with("s1")) {
			s1_ran = true;
		}
	}
	CHECK_MESSAGE(!s1_ran, "the untouched subgraph instance stayed cached");
}

TEST_CASE("[CgamePCGGraph] Custom Callable nodes") {
	Ref<G> gc;
	gc.instantiate();
	Dictionary out_pins;
	out_pins["out"] = "points";
	out_pins["count_only"] = "points";
	gc->register_node("boost_density", pin_dict("in", "points"), out_pins, callable_mp_static(&boost_node_full));
	(void)gc->add_graph_input("i", "p", "points");
	Dictionary bp;
	bp["factor"] = 3.0;
	(void)gc->add_node("b", "boost_density", bp);
	(void)gc->add_graph_output("o", "res", "points");
	CHECK_MESSAGE(gc->link("i", "out", "b", "in") == "", "custom node pins validate");
	CHECK_MESSAGE(gc->link("b", "count_only", "o", "in") == "", "second custom output is linkable");
	CHECK_MESSAGE(gc->link("i", "out", "b", "other") != "", "custom node rejects unknown pins");
	PackedVector3Array two;
	two.push_back(Vector3());
	two.push_back(Vector3(1, 1, 1));
	Vector<float> dens;
	dens.push_back(0.25f);
	dens.push_back(0.5f);
	Dictionary in;
	in["p"] = pts_with_density(two, dens);
	const Dictionary cr = gc->execute(in);
	CHECK_MESSAGE(G::point_count(cr["res"]) == 2, "custom output wired through");

	Ref<G> gc2;
	gc2.instantiate();
	gc2->register_node("boost_density", pin_dict("in", "points"), pin_dict("out", "points"), callable_mp_static(&boost_node_single));
	(void)gc2->add_graph_input("i", "p", "points");
	(void)gc2->add_node("b", "boost_density");
	(void)gc2->add_graph_output("o", "res", "points");
	(void)gc2->link("i", "out", "b", "in");
	(void)gc2->link("b", "out", "o", "in");
	PackedVector3Array one;
	one.push_back(Vector3());
	Dictionary in2;
	in2["p"] = G::make_points(one);
	const Dictionary cr2 = gc2->execute(in2);
	const PackedFloat32Array cd = Dictionary(Dictionary(cr2["res"])["attrs"])["density"];
	CHECK_MESSAGE(near_value(cd[0], 0.9, 0.0001), "one-argument execute callables work");
}

TEST_CASE("[CgamePCGGraph] Incremental cache with early cutoff") {
	const Dictionary vol = G::make_volume(AABB(Vector3(0, 0, 0), Vector3(60, 10, 60)));
	Ref<G> gi = sampling_graph(true);
	Dictionary spawn_p;
	spawn_p["mesh_id"] = "tree";
	(void)gi->add_node("spawn", "static_mesh_spawner", spawn_p);
	(void)gi->add_graph_output("out_m", "meshes", "mesh_instances");
	(void)gi->link("prune", "out", "spawn", "in");
	(void)gi->link("spawn", "out", "out_m", "in");
	const Dictionary first = gi->execute(vol_input(vol));
	CHECK_MESSAGE(gi->get_executed_nodes().size() == gi->get_nodes().size(), "first run executes every node");
	const Array m1 = Dictionary(first["meshes"])["records"];
	CHECK_MESSAGE(String(Dictionary(m1[0])["mesh_id"]) == "tree", "spawner records the mesh id");
	(void)gi->execute(vol_input(vol));
	CHECK_MESSAGE(gi->get_executed_nodes().size() == 0, "second identical run executes nothing");
	CHECK_MESSAGE(gi->get_cache_hits() == (int)gi->get_nodes().size(), "every node was a cache hit");

	gi->set_param("filter", "min", 0.5);
	(void)gi->execute(vol_input(vol));
	HashSet<String> ran;
	for (int i = 0; i < gi->get_executed_nodes().size(); i++) {
		ran.insert(String(gi->get_executed_nodes()[i]));
	}
	CHECK_MESSAGE((ran.size() == 5 && ran.has("filter") && ran.has("out") && ran.has("out_m") && ran.has("prune") && ran.has("spawn")), "only the changed node and its dependants re-run");

	gi->set_param("filter", "max", 5.0);
	(void)gi->execute(vol_input(vol));
	CHECK_MESSAGE((gi->get_executed_nodes().size() == 1 && String(gi->get_executed_nodes()[0]) == "filter"), "unchanged output stops propagation (early cutoff)");

	gi->set_param("sample", "spacing", 4.0);
	(void)gi->execute(vol_input(vol));
	CHECK_MESSAGE((gi->get_executed_nodes().has("sample") && gi->get_executed_nodes().has("spawn") && !gi->get_executed_nodes().has("in_v")), "upstream param change re-runs the chain but not the input");

	(void)gi->execute(vol_input(G::make_volume(AABB(Vector3(), Vector3(40, 10, 40)))));
	CHECK_MESSAGE(gi->get_executed_nodes().has("sample"), "changed graph input invalidates dependants");

	gi->clear_cache();
	(void)gi->execute(vol_input(vol));
	CHECK_MESSAGE(gi->get_executed_nodes().size() == gi->get_nodes().size(), "clear_cache forces a full re-run");
}

TEST_CASE("[CgamePCGGraph] Debug capture") {
	const Dictionary vol = G::make_volume(AABB(Vector3(0, 0, 0), Vector3(60, 10, 60)));
	Ref<G> gi = sampling_graph(true);
	Dictionary spawn_p;
	spawn_p["mesh_id"] = "tree";
	(void)gi->add_node("spawn", "static_mesh_spawner", spawn_p);
	(void)gi->add_graph_output("out_m", "meshes", "mesh_instances");
	(void)gi->link("prune", "out", "spawn", "in");
	(void)gi->link("spawn", "out", "out_m", "in");
	(void)gi->execute(vol_input(vol));
	CHECK_MESSAGE(gi->get_debug().size() == gi->get_nodes().size(), "every node is captured");
	CHECK_MESSAGE(gi->get_debug_steps().size() == gi->get_nodes().size(), "steps list every node");
	const Dictionary dbg = Dictionary(gi->get_debug())["sample"];
	const Dictionary summ = Dictionary(dbg["outputs"])["out"];
	CHECK_MESSAGE((int)summ["count"] > 0, "output counts are recorded");
	CHECK_MESSAGE(Array(summ["sample"]).size() == 5, "sample points are limited to debug_sample_count");
	CHECK_MESSAGE(((int64_t)dbg["usec"] >= 0 && (bool)dbg["executed"]), "timing and executed flag are recorded");
	CHECK_MESSAGE((int)dbg["step"] < (int)Dictionary(gi->get_debug()["prune"])["step"], "steps follow dependency order");
	const Dictionary pdbg = Dictionary(gi->get_debug())["prune"];
	CHECK_MESSAGE((int)Dictionary(pdbg["in_counts"])["in"] >= (int)Dictionary(Dictionary(pdbg["outputs"])["out"])["count"], "input counts are captured");

	(void)gi->execute(vol_input(vol));
	CHECK_MESSAGE(!(bool)Dictionary(Dictionary(gi->get_debug())["sample"])["executed"], "cached nodes are flagged as not executed");
	gi->set_debug_capture_full(true);
	gi->set_param("filter", "min", 0.6);
	(void)gi->execute(vol_input(vol));
	CHECK_MESSAGE(Dictionary(Dictionary(gi->get_debug())["filter"]).has("full"), "full outputs can be captured for inspection");

	gi->set_debug_enabled(false);
	(void)gi->execute(vol_input(vol));
	CHECK(gi->get_debug().size() == 0);
}

TEST_CASE("[CgamePCGGraph] Partition cells reproduce the unpartitioned run") {
	const Dictionary vol = G::make_volume(AABB(Vector3(0, 0, 0), Vector3(60, 10, 60)));
	const double cell = 20.0;
	Ref<G> gl = sampling_graph(false);
	const HashSet<String> whole = keyset(Dictionary(gl->execute(vol_input(vol)))["pts"]);
	HashSet<String> union_set;
	bool dup_found = false;
	for (int cx = 0; cx < 3; cx++) {
		for (int cz = 0; cz < 3; cz++) {
			const Dictionary part = gl->partition_execute(Vector2i(cx, cz), cell, vol_input(vol));
			const HashSet<String> ks = keyset(part["pts"]);
			for (const String &k : ks) {
				if (union_set.has(k)) {
					dup_found = true;
				}
				union_set.insert(k);
			}
		}
	}
	CHECK_MESSAGE(whole.size() > 50, "unpartitioned run produced points");
	CHECK_MESSAGE(!dup_found, "no point appears in two cells");
	CHECK_MESSAGE(union_set.size() == whole.size(), "cells together reproduce the unpartitioned result");
	bool same_keys = true;
	for (const String &k : whole) {
		if (!union_set.has(k)) {
			same_keys = false;
		}
	}
	CHECK_MESSAGE(same_keys, "positions at cell borders match exactly");

	Ref<G> gq = sampling_graph(true);
	const HashSet<String> whole_p = keyset(Dictionary(gq->execute(vol_input(vol)))["pts"]);
	HashSet<String> union_p;
	for (int cx = 0; cx < 3; cx++) {
		for (int cz = 0; cz < 3; cz++) {
			const Dictionary part_p = gq->partition_execute(Vector2i(cx, cz), cell, vol_input(vol), 12.0);
			for (const String &k : keyset(part_p["pts"])) {
				union_p.insert(k);
			}
		}
	}
	CHECK_MESSAGE(union_p.size() == whole_p.size(), "pruned cells with a margin match the unpartitioned run");
	const Dictionary a1 = gq->partition_execute(Vector2i(1, 1), cell, vol_input(vol), 12.0);
	const Dictionary a2 = gq->partition_execute(Vector2i(1, 1), cell, vol_input(vol), 12.0);
	CHECK_MESSAGE(hash_of(a1) == hash_of(a2), "re-running a cell is deterministic");
}

TEST_CASE("[CgamePCGGraph] Presets validate and honour their clearings") {
	Dictionary in_land = G::make_landscape(callable_mp_static(&landscape_height_fn));
	const Dictionary big = G::make_volume(AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120)));
	PackedVector3Array road_pts;
	road_pts.push_back(Vector3(-60, 0, 0));
	road_pts.push_back(Vector3(0, 0, 0));
	road_pts.push_back(Vector3(60, 0, 0));
	const Dictionary road = G::make_spline(road_pts);

	Ref<G> forest = G::forest_scatter();
	CHECK_MESSAGE(forest->validate().size() == 0, "forest preset validates");
	Dictionary fin;
	fin["volume"] = big;
	fin["landscape"] = in_land;
	fin["road"] = road;
	const Dictionary fo = forest->execute(fin);
	const PackedVector3Array tree_pts = origins(fo["trees"]);
	CHECK_MESSAGE(tree_pts.size() > 50, "forest produces trees");
	const PackedVector3Array road_samples = Dictionary(forest->node_output("road_pts"))["positions"];
	bool clear_ok = true;
	for (int i = 0; i < tree_pts.size(); i++) {
		for (int k = 0; k < road_samples.size(); k++) {
			if (Vector2(tree_pts[i].x - road_samples[k].x, tree_pts[i].z - road_samples[k].z).length() < 7.0 - 0.001) {
				clear_ok = false;
			}
		}
	}
	CHECK_MESSAGE(clear_ok, "no tree stands within the road clearing");
	CHECK_MESSAGE(G::point_count(fo["floor"]) == tree_pts.size(), "forest floor layer weights match tree count");

	Ref<G> ruins = G::ruins_debris();
	CHECK_MESSAGE(ruins->validate().size() == 0, "ruins preset validates");
	PackedVector3Array poi_pos;
	poi_pos.push_back(Vector3(0, 0, 0));
	poi_pos.push_back(Vector3(40, 2, 10));
	poi_pos.push_back(Vector3(-30, 1, 25));
	Dictionary rin;
	rin["pois"] = G::make_points(poi_pos);
	const Dictionary ro = ruins->execute(rin);
	CHECK_MESSAGE(G::point_count(ro["debris"]) > 6, "ruins scatter debris around points of interest");
	CHECK_MESSAGE(G::point_count(ro["ground"]) == G::point_count(ro["debris"]), "rubble ground layer follows debris");

	Ref<G> cave = G::cave_rocks();
	CHECK_MESSAGE(cave->validate().size() == 0, "cave preset validates");
	PackedVector3Array ent_pos;
	ent_pos.push_back(Vector3(10, 0, 10));
	ent_pos.push_back(Vector3(-20, 3, 5));
	Dictionary cin;
	cin["entrances"] = G::make_points(ent_pos);
	const Dictionary co = cave->execute(cin);
	const PackedVector3Array rocks = origins(co["rocks"]);
	CHECK_MESSAGE(rocks.size() > 4, "cave entrances get rocks");
	bool mouth_ok = true;
	for (int i = 0; i < rocks.size(); i++) {
		for (int k = 0; k < ent_pos.size(); k++) {
			if (Vector2(rocks[i].x - ent_pos[k].x, rocks[i].z - ent_pos[k].z).length() < 3.0 - 0.001) {
				mouth_ok = false;
			}
		}
	}
	CHECK_MESSAGE(mouth_ok, "cave mouths stay clear of rocks");
}

} // namespace TestCgamePCGGraph
