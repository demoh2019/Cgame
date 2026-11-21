#pragma once

#include "../cgame_facial_animation.h"
#include "../cgame_lip_sync.h"
#include "../cgame_locomotion_tools.h"
#include "../cgame_mocap_cleanup.h"
#include "../cgame_motion_matching_database.h"
#include "../cgame_retargeter.h"
#include "../cgame_rig_solvers.h"
#include "../foot_lock_modifier_3d.h"

#include "tests/test_macros.h"

namespace TestCgameAnimation {

// Deterministic pseudo random in [0, 1).
static float _lcg(uint32_t &r_state) {
	r_state = r_state * 1664525u + 1013904223u;
	return float((r_state >> 8) & 0xffff) / 65536.0f;
}

TEST_CASE("[CgameAnimation][MotionMatching] Indexed search matches brute force") {
	Ref<CgameMotionMatchingDatabase> db = CgameMotionMatchingDatabase::build_default_database();
	REQUIRE(db.is_valid());
	CHECK(db->is_built());
	CHECK(db->get_frame_count() > 100);
	CHECK(db->get_clip_count() == 8);

	uint32_t state = 12345u;
	for (int i = 0; i < 200; i++) {
		const Vector2 vel(_lcg(state) * 6.0f - 3.0f, _lcg(state) * 8.0f - 4.0f);
		const Vector2 goal(_lcg(state) * 6.0f - 3.0f, _lcg(state) * 8.0f - 4.0f);
		const float facing = _lcg(state) * 2.0f - 1.0f;
		const Vector3 foot(_lcg(state) * 0.4f - 0.2f, _lcg(state) * 0.15f, _lcg(state) * 0.6f - 0.3f);
		const Vector<float> q = db->query_features_from(vel, 0.0f, goal, facing, foot, -foot, foot * 3.0f, -foot * 3.0f);
		const CgameMotionMatchingDatabase::SearchResult a = db->search_native(q, -1, -1, PackedStringArray(), true);
		const CgameMotionMatchingDatabase::SearchResult b = db->search_native(q, -1, -1, PackedStringArray(), false);
		REQUIRE(a.clip >= 0);
		CHECK(a.clip == b.clip); // Ties only occur between repeated cycles of one clip, so frames may differ.
		CHECK(Math::is_equal_approx(a.cost, b.cost));
	}
}

TEST_CASE("[CgameAnimation][MotionMatching] Required tags filter and continuing pose bias") {
	Ref<CgameMotionMatchingDatabase> db = CgameMotionMatchingDatabase::build_default_database();
	const Vector<float> q = db->query_features_from(Vector2(0, 1.4f), 0.0f, Vector2(0, 1.4f), 0.0f, Vector3(), Vector3(), Vector3(), Vector3());
	PackedStringArray tags;
	tags.push_back("run");
	const CgameMotionMatchingDatabase::SearchResult run = db->search_native(q, -1, -1, tags, true);
	REQUIRE(run.clip >= 0);
	CHECK(db->get_clip_name(run.clip) == "run_forward");

	// Playing the clip that best matches keeps playing it (next frame) rather than jumping.
	const CgameMotionMatchingDatabase::SearchResult first = db->search_native(q, -1, -1, PackedStringArray(), true);
	REQUIRE(first.clip >= 0);
	const CgameMotionMatchingDatabase::SearchResult next = db->search_native(q, first.clip, first.frame, PackedStringArray(), true);
	CHECK(next.clip == first.clip);

	// Dictionary API round trip.
	const Dictionary d = db->search(db->query_from(Vector2(0, 4), 0.0f, Vector2(0, 4), 0.0f, Vector3(), Vector3(), Vector3(), Vector3()));
	CHECK(String(d["clip"]) != "");
	CHECK(db->prune_redundant(0.0001f) >= 0);
}

TEST_CASE("[CgameAnimation][MotionMatching] Spring prediction converges to the goal") {
	const Vector2 v = CgameMotionMatchingDatabase::predict_velocity(Vector2(0, 0), Vector2(0, 3), 0.27f, 5.0f);
	CHECK(v.distance_to(Vector2(0, 3)) < 0.001f);
	CHECK(CgameMotionMatchingDatabase::predict_velocity(Vector2(1, 1), Vector2(2, 2), 0.27f, 0.0f).is_equal_approx(Vector2(1, 1)));
	CHECK(Math::abs(CgameMotionMatchingDatabase::predict_facing(0.0f, 1.0f, 0.27f, 5.0f) - 1.0f) < 0.001f);
}

TEST_CASE("[CgameAnimation][IK] Two bone reaches reachable targets and clamps unreachable ones") {
	const Vector3 root(0, 0, 0);
	const Vector3 mid(0, 1, 0);
	const Vector3 tip(0, 2, 0);
	const Vector3 pole(0, 1, 5);

	const Vector3 target(1.0f, 1.0f, 0.0f);
	CgameRigSolvers::TwoBoneResult r = CgameRigSolvers::two_bone(root, mid, tip, target, pole);
	CHECK(r.reached);
	CHECK(r.tip.distance_to(target) < 0.0001f);
	CHECK(Math::abs(r.mid.distance_to(root) - 1.0f) < 0.0001f);
	CHECK(Math::abs(r.mid.distance_to(r.tip) - 1.0f) < 0.0001f);
	CHECK(r.mid.z > 0.0f); // Bends towards the pole.

	const Vector3 far(0, 10, 0);
	r = CgameRigSolvers::two_bone(root, mid, tip, far, pole);
	CHECK_FALSE(r.reached);
	CHECK(Math::abs(r.tip.distance_to(root) - 2.0f) < 0.001f);
}

TEST_CASE("[CgameAnimation][IK] FABRIK chain converges to a reachable target") {
	Vector<Vector3> chain;
	for (int i = 0; i < 5; i++) {
		chain.push_back(Vector3(0, i, 0));
	}
	const Vector3 target(2.0f, 1.5f, 1.0f);
	const Vector<Vector3> solved = CgameRigSolvers::fabrik_chain(chain, target, 32, 0.0005f);
	CHECK(solved[4].distance_to(target) < 0.001f);
	CHECK(solved[0].is_equal_approx(chain[0]));
	for (int i = 0; i < 4; i++) {
		CHECK(Math::abs(solved[i].distance_to(solved[i + 1]) - 1.0f) < 0.001f);
	}
	// Unreachable target: chain stretches towards it and keeps bone lengths.
	const Vector<Vector3> stretched = CgameRigSolvers::fabrik_chain(chain, Vector3(0, 0, 20), 32, 0.0005f);
	CHECK(stretched[4].z > 3.5f);
}

TEST_CASE("[CgameAnimation][IK] Hinge and cone constraints limit direction") {
	CgameRigSolvers::JointConstraint cone;
	cone.type = CgameRigSolvers::JointConstraint::TYPE_CONE;
	cone.angle = Math::deg_to_rad(30.0f);
	const Vector3 limited = CgameRigSolvers::limit_direction(Vector3(0, 1, 0), Vector3(1, 0, 0), cone);
	CHECK(Math::abs(Vector3(0, 1, 0).angle_to(limited) - cone.angle) < 0.001f);
}

TEST_CASE("[CgameAnimation][IK] Full body solver pulls both legs through shared hips") {
	// 0 hips, 1 left thigh, 2 left foot, 3 right thigh, 4 right foot.
	Vector<int> parents;
	parents.push_back(-1);
	parents.push_back(0);
	parents.push_back(1);
	parents.push_back(0);
	parents.push_back(3);
	Vector<Vector3> rest;
	rest.push_back(Vector3(0, 2, 0));
	rest.push_back(Vector3(-0.5f, 1, 0));
	rest.push_back(Vector3(-0.5f, 0, 0));
	rest.push_back(Vector3(0.5f, 1, 0));
	rest.push_back(Vector3(0.5f, 0, 0));
	CgameRigSolvers::FullBodySolver solver;
	solver.setup(parents, rest);
	solver.root_pin = 1.0f;
	solver.set_effector(2, Vector3(-0.5f, 0.4f, 0.4f));
	solver.set_effector(4, Vector3(0.5f, 0.2f, -0.3f));
	const float err = solver.solve(64, 0.002f);
	CHECK(err < 0.01f);
	CHECK(solver.positions[0].is_equal_approx(rest[0])); // Pinned root.
}

TEST_CASE("[CgameAnimation][Mocap] One Euro filter smooths noise and preserves constants") {
	PackedVector3Array constant;
	for (int i = 0; i < 50; i++) {
		constant.push_back(Vector3(1, 2, 3));
	}
	const PackedVector3Array filtered_constant = CgameMocapCleanup::one_euro_positions(constant, 60.0f, 1.0f, 0.0f, 1.0f);
	for (int i = 0; i < constant.size(); i++) {
		CHECK(filtered_constant[i].is_equal_approx(Vector3(1, 2, 3)));
	}

	uint32_t state = 7u;
	PackedVector3Array noisy;
	for (int i = 0; i < 300; i++) {
		noisy.push_back(Vector3(_lcg(state) - 0.5f, 0, 0));
	}
	const PackedVector3Array smooth = CgameMocapCleanup::one_euro_positions(noisy, 60.0f, 1.0f, 0.0f, 1.0f);
	double raw_var = 0.0;
	double smooth_var = 0.0;
	for (int i = 10; i < noisy.size(); i++) {
		raw_var += noisy[i].x * noisy[i].x;
		smooth_var += smooth[i].x * smooth[i].x;
	}
	CHECK(smooth_var < raw_var * 0.5);

	// With a large beta the filter follows fast motion closely (low lag).
	PackedVector3Array ramp;
	for (int i = 0; i < 60; i++) {
		ramp.push_back(Vector3(float(i) * 0.1f, 0, 0));
	}
	const PackedVector3Array lag_heavy = CgameMocapCleanup::one_euro_positions(ramp, 60.0f, 0.5f, 0.0f, 1.0f);
	const PackedVector3Array lag_light = CgameMocapCleanup::one_euro_positions(ramp, 60.0f, 0.5f, 5.0f, 1.0f);
	CHECK(Math::abs(lag_light[59].x - ramp[59].x) < Math::abs(lag_heavy[59].x - ramp[59].x));
}

TEST_CASE("[CgameAnimation][Mocap] Butterworth keeps DC, spikes are repaired, keys reduce, contacts plant") {
	PackedVector3Array constant;
	for (int i = 0; i < 40; i++) {
		constant.push_back(Vector3(2, 0, 0));
	}
	const PackedVector3Array bw = CgameMocapCleanup::butterworth(constant, 60.0f, 6.0f);
	for (int i = 0; i < bw.size(); i++) {
		CHECK(Math::abs(bw[i].x - 2.0f) < 0.001f);
	}

	PackedVector3Array line;
	for (int i = 0; i < 30; i++) {
		line.push_back(Vector3(float(i) * 0.1f, 0, 0));
	}
	PackedVector3Array spiky = line.duplicate();
	spiky.write[15] = Vector3(50, 9, 0);
	const PackedVector3Array repaired = CgameMocapCleanup::remove_spikes(spiky, 4.0f);
	CHECK(repaired[15].distance_to(line[15]) < 0.2f);

	CHECK(CgameMocapCleanup::reduce_keys(line, 0.001f).size() == 2); // A straight line needs two keys.

	PackedVector3Array foot;
	for (int i = 0; i < 20; i++) {
		foot.push_back(Vector3(i < 10 ? 0.0f : float(i - 9) * 0.2f, i < 10 ? 0.0f : 0.3f, 0));
	}
	const PackedByteArray contacts = CgameMocapCleanup::detect_contacts(foot, 30.0f, 0.05f, 0.5f);
	CHECK(contacts[3] == 1);
	CHECK(contacts[18] == 0);
	const PackedVector3Array fixed = CgameMocapCleanup::fix_foot_skate(foot, contacts, 2);
	CHECK(fixed.size() == foot.size());

	const PackedVector3Array re = CgameMocapCleanup::retime(line, 30.0f, 60.0f);
	CHECK(re.size() == 2 * 29 + 1);
	CHECK(re[re.size() - 1].is_equal_approx(line[line.size() - 1]));
}

TEST_CASE("[CgameAnimation][LipSync] Viseme timeline is ordered, framed by rest and mapped") {
	const PackedStringArray phones = CgameLipSync::phonemes_from_text("Mama", "en");
	CHECK(phones.size() > 0);
	CHECK(CgameLipSync::viseme_for("m") == "A");
	CHECK(CgameLipSync::viseme_for("unknown") == "X");

	const Array tl = CgameLipSync::timeline("Hello world", 1.5f, "en");
	REQUIRE(tl.size() >= 3);
	Dictionary first = tl[0];
	Dictionary last = tl[tl.size() - 1];
	CHECK(String(first["viseme"]) == "X");
	CHECK(String(last["viseme"]) == "X");
	CHECK(Math::is_equal_approx((float)last["time"], 1.5f));
	float prev = -1.0f;
	for (int i = 0; i < tl.size(); i++) {
		const Dictionary k = tl[i];
		CHECK((float)k["time"] > prev);
		prev = k["time"];
	}
	const Dictionary at_start = CgameLipSync::sample(tl, 0.0f);
	CHECK(at_start.has("X"));
	const Dictionary mid = CgameLipSync::sample(tl, 0.75f);
	CHECK(mid.size() >= 1);

	const Array ru = CgameLipSync::timeline(String::utf8("привет"), 1.0f, "ru");
	CHECK(ru.size() >= 3);

	// Silent audio forces rest.
	PackedFloat32Array silent;
	silent.resize(50);
	silent.fill(0.0f);
	const Array refined = CgameLipSync::refine_with_audio(tl, silent, 0.02f);
	for (int i = 0; i < refined.size(); i++) {
		CHECK(String(Dictionary(refined[i])["viseme"]) == "X");
	}
}

TEST_CASE("[CgameAnimation][Facial] Emotions, visemes and determinism") {
	Ref<CgameFacialAnimation> a;
	a.instantiate();
	Ref<CgameFacialAnimation> b;
	b.instantiate();
	a->set_seed(42);
	b->set_seed(42);
	a->set_saccades_enabled(false);
	a->set_blink_enabled(false);
	const Dictionary happy = a->evaluate(1.0f, "happy", 1.0f, Dictionary());
	CHECK(float(happy["mouthSmileLeft"]) > 0.8f);
	Dictionary visemes;
	visemes["D"] = 1.0f;
	CHECK(float(a->evaluate(1.0f, "neutral", 0.0f, visemes)["jawOpen"]) > 0.8f);
	CHECK(a->blink_weight(0.0f) == b->blink_weight(0.0f));
	float blink_peak = 0.0f;
	for (int i = 0; i < 1200; i++) {
		blink_peak = MAX(blink_peak, b->blink_weight(float(i) * 0.01f));
	}
	CHECK(blink_peak > 0.9f);
}

TEST_CASE("[CgameAnimation][FootLock] Plant, stretch release and blending") {
	CgameFootLockState state;
	CgameFootLockState::Params params;
	const Vector3 anim(1, 0.05f, 2);
	CgameFootLockState::Output out = state.update(0.016f, anim, 1.0f, 0.0f, params);
	CHECK(out.locked);
	CHECK(out.target.is_equal_approx(Vector3(1, 0.0f, 2)));
	CHECK(out.weight > 0.0f);
	for (int i = 0; i < 20; i++) {
		out = state.update(0.016f, anim + Vector3(0.1f, 0, 0), 1.0f, 0.0f, params);
	}
	CHECK(out.weight == 1.0f);
	CHECK(out.target.is_equal_approx(Vector3(1, 0.0f, 2)));
	// Body drifts too far: the foot releases and does not re-lock until lift-off.
	out = state.update(0.016f, anim + Vector3(1, 0, 0), 1.0f, 0.0f, params);
	CHECK_FALSE(out.locked);
	out = state.update(0.016f, anim + Vector3(1, 0, 0), 1.0f, 0.0f, params);
	CHECK_FALSE(out.locked);
	out = state.update(0.016f, anim, 0.0f, 0.0f, params); // Lift-off.
	out = state.update(0.016f, anim, 1.0f, 0.0f, params);
	CHECK(out.locked);
}

TEST_CASE("[CgameAnimation][Locomotion] Distance matching and warping helpers") {
	PackedFloat32Array dist;
	PackedFloat32Array times;
	for (int i = 0; i <= 10; i++) {
		dist.push_back(float(i)); // Ascending distances.
		times.push_back(float(i) * 0.1f);
	}
	CHECK(Math::is_equal_approx(CgameLocomotionTools::playback_time_for_distance(dist, times, 5.5f), 0.55f));
	CHECK(Math::is_equal_approx(CgameLocomotionTools::playback_time_for_distance(dist, times, -3.0f), 0.0f));
	CHECK(Math::is_equal_approx(CgameLocomotionTools::stride_play_rate(10.0f, 1.0f), 1.35f));
	CHECK(Math::is_equal_approx(CgameLocomotionTools::stride_play_rate(1.0f, 0.0f), 1.0f));

	Array targets;
	targets.push_back(Vector3(0, 0, 1.6f));
	const Dictionary warp = CgameLocomotionTools::motion_warp_solve(Vector3(), Vector2(0, 1), 1.0f, targets);
	CHECK(warp.has("offset"));
	CHECK(CgameLocomotionTools::motion_warp_solve(Vector3(), Vector2(0, -1), 1.0f, targets).is_empty());
}

TEST_CASE("[CgameAnimation][Retarget] Bone names canonicalize across rig conventions") {
	CHECK(CgameRetargeter::canonical("mixamorig:LeftUpLeg") == "upperleg|l");
	CHECK(CgameRetargeter::canonical("Bip01 R Thigh") == "upperleg|r");
	CHECK(CgameRetargeter::canonical("Pelvis") == "hips");
	CHECK(CgameRetargeter::canonical("Unknown_Bone_X") == "");

	PackedStringArray src;
	src.push_back("mixamorig:Hips");
	src.push_back("mixamorig:LeftUpLeg");
	PackedStringArray dst;
	dst.push_back("pelvis");
	dst.push_back("thigh_l");
	const Dictionary map = CgameRetargeter::build_map(src, dst);
	CHECK(map.size() == 2);
	CHECK(int(map[0]) == 0);
	CHECK(int(map[1]) == 1);
}

} // namespace TestCgameAnimation
