/**************************************************************************/
/*  test_cgame_rendering.h                                                */
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

#include "../cgame_area_lights.h"
#include "../cgame_foveated_shading.h"
#include "../cgame_frame_pacing.h"
#include "../cgame_gpu_resource_report.h"
#include "../cgame_hdr_output.h"
#include "../cgame_impostor_baker.h"
#include "../cgame_instance_culling.h"
#include "../cgame_rt_effect.h"
#include "../cgame_vram_budget.h"
#include "../impostor_field_3d.h"

#include "core/io/image.h"
#include "servers/display/display_server.h"
#include "servers/rendering/rendering_server.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/multimesh.h"
#include "tests/test_macros.h"

#include <limits>

namespace TestCgameRendering {

// ---- Frame pacing ---------------------------------------------------------------------------

TEST_CASE("[CgameFramePacing] Tiers follow the display refresh") {
	CHECK(CgameFramePacing::compute_profile(0, 144.0f).max_fps == 72);
	CHECK(CgameFramePacing::compute_profile(0, 60.0f).max_fps == 60);
	CHECK(CgameFramePacing::compute_profile(1, 60.0f).max_fps == 60);
	CHECK(CgameFramePacing::compute_profile(1, 144.0f).max_fps == 144);
	CHECK(CgameFramePacing::compute_profile(2, 120.0f).max_fps == 120);
	CHECK(CgameFramePacing::compute_profile(2, 120.0f).vsync == DisplayServerEnums::VSYNC_ADAPTIVE);
}

TEST_CASE("[CgameFramePacing] Ultra uses mailbox and no cap") {
	const CgameFramePacing::Profile profile = CgameFramePacing::compute_profile(3, 120.0f);
	CHECK(profile.vsync == DisplayServerEnums::VSYNC_MAILBOX);
	CHECK(profile.max_fps == 0);
}

TEST_CASE("[CgameFramePacing] Unknown refresh falls back to 60 and levels clamp") {
	CHECK(CgameFramePacing::compute_profile(0, 0.0f).max_fps == 60);
	CHECK(CgameFramePacing::compute_profile(1, 29.0f).max_fps == 60);
	CHECK(CgameFramePacing::compute_profile(1, std::numeric_limits<float>::infinity()).max_fps == 60);
	CHECK(CgameFramePacing::compute_profile(1, std::numeric_limits<float>::quiet_NaN()).max_fps == 60);
	CHECK(CgameFramePacing::compute_profile(1, 1.0e20f).max_fps == 60);
	CHECK(CgameFramePacing::compute_profile(1, 480.0f).max_fps == 480);
	CHECK(CgameFramePacing::compute_profile(-5, 60.0f).vsync == DisplayServerEnums::VSYNC_ENABLED);
	CHECK(CgameFramePacing::compute_profile(99, 60.0f).vsync == DisplayServerEnums::VSYNC_MAILBOX);
	const Dictionary d = CgameFramePacing::settings(0, 144.0f);
	CHECK(int(d["max_fps"]) == 72);
}

// ---- HDR output -----------------------------------------------------------------------------

TEST_CASE("[CgameHDROutput] Wanted logic") {
	CHECK(CgameHDROutput::wanted(3, "forward_plus", true));
	CHECK(CgameHDROutput::wanted(2, "mobile", true));
	CHECK_FALSE(CgameHDROutput::wanted(3, "forward_plus", false));
	CHECK_FALSE(CgameHDROutput::wanted(1, "forward_plus", true));
	CHECK_FALSE(CgameHDROutput::wanted(3, "gl_compatibility", true));
}

// ---- Area lights ----------------------------------------------------------------------------

TEST_CASE("[CgameAreaLights] Emitter sizes and filter quality") {
	CHECK(CgameAreaLights::size_for(3, 0.35f) == doctest::Approx(0.35f));
	CHECK(CgameAreaLights::size_for(2, 0.35f) == doctest::Approx(0.35f));
	CHECK(CgameAreaLights::size_for(1, 0.35f) == 0.0f);
	CHECK(CgameAreaLights::size_for(3, -1.0f) == 0.0f);
	CHECK(CgameAreaLights::filter_quality(0) == RSE::SHADOW_QUALITY_HARD);
	CHECK(CgameAreaLights::filter_quality(1) == RSE::SHADOW_QUALITY_SOFT_LOW);
	CHECK(CgameAreaLights::filter_quality(2) == RSE::SHADOW_QUALITY_SOFT_MEDIUM);
	CHECK(CgameAreaLights::filter_quality(3) == RSE::SHADOW_QUALITY_SOFT_HIGH);
}

// ---- VRAM budget ----------------------------------------------------------------------------

TEST_CASE("[CgameVRAMBudget] Budgets and upgrade gate") {
	CHECK(CgameVRAMBudget::budget_bytes(0) == doctest::Approx(1536.0 * 1024.0 * 1024.0));
	CHECK(CgameVRAMBudget::budget_bytes(3) == doctest::Approx(6144.0 * 1024.0 * 1024.0));
	CHECK(CgameVRAMBudget::budget_bytes(9) == CgameVRAMBudget::budget_bytes(3));
	CHECK(CgameVRAMBudget::upgrade_allowed(1000.0 * 1024.0 * 1024.0, 0));
	CHECK_FALSE(CgameVRAMBudget::upgrade_allowed(2500.0 * 1024.0 * 1024.0, 0));
	CHECK_FALSE(CgameVRAMBudget::upgrade_allowed(0.0, 0));
	CHECK_FALSE(CgameVRAMBudget::upgrade_allowed(-1.0, 0));
	CHECK_FALSE(CgameVRAMBudget::upgrade_allowed(std::numeric_limits<double>::quiet_NaN(), 0));
}

TEST_CASE("[CgameVRAMBudget] Pressure must be sustained") {
	Ref<CgameVRAMBudget> budget;
	budget.instantiate();
	const double over = CgameVRAMBudget::budget_bytes(2) * 0.95;
	const double under = CgameVRAMBudget::budget_bytes(2) * 0.5;
	for (int i = 0; i < 15; i++) {
		CHECK_FALSE(budget->sample(over, 2, 0.125));
	}
	CHECK_FALSE(budget->sample(over, 2, 1.0)); // Loading stall is ignored.
	CHECK_FALSE(budget->sample(std::numeric_limits<double>::infinity(), 2, 0.125));
	CHECK_FALSE(budget->sample(0.0, 2, 0.125)); // Missing reading preserves timer.
	CHECK(budget->get_pressure_seconds() == doctest::Approx(1.875));
	CHECK(budget->sample(over, 2, 0.125)); // 2 s sustained valid samples.
	CHECK_FALSE(budget->sample(over, 2, 0.125));
	CHECK_FALSE(budget->sample(under, 2, 0.125)); // Valid relief resets it.
	CHECK(budget->get_pressure_seconds() == doctest::Approx(0.0));
	for (int i = 0; i < 16; i++) {
		CHECK_FALSE(budget->sample(over, 0, 0.125)); // Lowest tier.
	}
	CHECK_FALSE(budget->sample(over, 2, std::numeric_limits<double>::infinity()));
	CHECK_FALSE(budget->sample(over, 2, -1.0));
}

// ---- Foveated shading -----------------------------------------------------------------------

TEST_CASE("[CgameFoveatedShading] Profiles per tier and renderer") {
	CHECK(CgameFoveatedShading::compute_profile(0, "forward_plus").enabled);
	CHECK(CgameFoveatedShading::compute_profile(1, "mobile").enabled);
	CHECK_FALSE(CgameFoveatedShading::compute_profile(2, "forward_plus").enabled);
	CHECK_FALSE(CgameFoveatedShading::compute_profile(3, "forward_plus").enabled);
	CHECK_FALSE(CgameFoveatedShading::compute_profile(0, "gl_compatibility").enabled);
	CHECK(CgameFoveatedShading::compute_profile(0, "forward_plus").inner == doctest::Approx(0.42f));
	CHECK(bool(CgameFoveatedShading::settings(0, "forward_plus")["enabled"]));
	CHECK_FALSE(bool(CgameFoveatedShading::settings(3, "forward_plus")["enabled"]));
}

TEST_CASE("[CgameFoveatedShading] Rate map layout") {
	const Vector2i size(40, 24);
	const Vector<uint8_t> data = CgameFoveatedShading::build_map_data(size, 0.4f, 0.7f);
	REQUIRE(data.size() == 40 * 24 * 3);
	const int center = (12 * 40 + 20) * 3;
	CHECK(data[center] == CgameFoveatedShading::RATE_1X1.r);
	CHECK(data[center + 1] == CgameFoveatedShading::RATE_1X1.g);
	CHECK(data[0] == CgameFoveatedShading::RATE_4X4.r);
	CHECK(data[1] == CgameFoveatedShading::RATE_4X4.g);
	const int last = (24 * 40 - 1) * 3;
	CHECK(data[last] == CgameFoveatedShading::RATE_4X4.r);
}

TEST_CASE("[CgameFoveatedShading] Ring orientation and image") {
	// Between inner and outer: top/bottom rows shade 2x2, the sides only horizontally.
	CgameFoveatedShading::Rate top = CgameFoveatedShading::rate_at(0.0f, 0.5f, 0.4f, 0.7f);
	CHECK(top.r == CgameFoveatedShading::RATE_2X2.r);
	CHECK(top.g == CgameFoveatedShading::RATE_2X2.g);
	CgameFoveatedShading::Rate side = CgameFoveatedShading::rate_at(0.5f, 0.0f, 0.4f, 0.7f);
	CHECK(side.r == CgameFoveatedShading::RATE_2X1.r);
	CHECK(side.g == CgameFoveatedShading::RATE_2X1.g);

	Ref<Image> image = CgameFoveatedShading::build_map(Vector2i(0, -3), 0.4f, 0.7f);
	REQUIRE(image.is_valid());
	CHECK(image->get_width() == 1); // Degenerate sizes clamp to 1x1.
	CHECK(image->get_height() == 1);
	CHECK(image->get_format() == Image::FORMAT_RGB8);
}

// ---- GPU resource report: byte estimates ----------------------------------------------------

TEST_CASE("[CgameGPUResourceReport] Format bits per pixel") {
	CHECK(CgameGPUResourceReport::format_bpp(Image::FORMAT_RGBA8) == 32);
	CHECK(CgameGPUResourceReport::format_bpp(Image::FORMAT_R8) == 8);
	CHECK(CgameGPUResourceReport::format_bpp(Image::FORMAT_RGBAF) == 128);
	CHECK(CgameGPUResourceReport::format_bpp(Image::FORMAT_DXT1) == 4);
	CHECK(CgameGPUResourceReport::format_bpp(Image::FORMAT_DXT5) == 8);
	CHECK(CgameGPUResourceReport::format_bpp(Image::FORMAT_ASTC_8x8) == 2);
	CHECK(CgameGPUResourceReport::format_bpp(Image::FORMAT_MAX) == -1);
	CHECK(CgameGPUResourceReport::is_block_compressed(Image::FORMAT_DXT1));
	CHECK_FALSE(CgameGPUResourceReport::is_block_compressed(Image::FORMAT_RGBA8));
	CHECK_FALSE(CgameGPUResourceReport::is_block_compressed(Image::FORMAT_RGBE9995));
}

TEST_CASE("[CgameGPUResourceReport] Texture byte estimates") {
	CHECK(CgameGPUResourceReport::texture_bytes(64, 64, Image::FORMAT_RGBA8, false) == 64 * 64 * 4);
	// Full mip chain of 64x64 RGBA8: 4096 + 1024 + 256 + 64 + 16 + 4 + 1 texels.
	CHECK(CgameGPUResourceReport::texture_bytes(64, 64, Image::FORMAT_RGBA8, true) == 5461 * 4);
	CHECK(CgameGPUResourceReport::texture_bytes(64, 64, Image::FORMAT_RGBA8, false, 6) == 64 * 64 * 4 * 6);
	CHECK(CgameGPUResourceReport::texture_bytes(0, 64, Image::FORMAT_RGBA8, false) == 0);
	// Block-compressed textures round dimensions up to whole 4x4 blocks.
	CHECK(CgameGPUResourceReport::texture_bytes(4, 4, Image::FORMAT_DXT1, false) == 8);
	CHECK(CgameGPUResourceReport::texture_bytes(1, 1, Image::FORMAT_DXT1, false) == 8);
	CHECK(CgameGPUResourceReport::texture_bytes(8, 8, Image::FORMAT_DXT5, false) == 64);
	// Unknown formats are assumed to be 32 bpp.
	CHECK(CgameGPUResourceReport::texture_bytes(2, 2, Image::FORMAT_MAX, false) == 16);
}

TEST_CASE("[CgameGPUResourceReport] Byte formatting") {
	CHECK(CgameGPUResourceReport::format_bytes(512) == "512 B");
	CHECK(CgameGPUResourceReport::format_bytes(2048) == "2.0 KiB");
	CHECK(CgameGPUResourceReport::format_bytes(3 * 1048576) == "3.00 MiB");
}

TEST_CASE("[CgameGPUResourceReport] Empty collect and timeline ring") {
	Ref<CgameGPUResourceReport> report;
	report.instantiate();
	const Dictionary snapshot = report->collect(nullptr);
	const Dictionary totals = snapshot["totals"];
	CHECK(int(totals["mesh_count"]) == 0);
	CHECK(int64_t(totals["estimated_bytes"]) == 0);
	CHECK(report->top(5, "textures").is_empty());
	report->set_timeline_capacity(3);
	for (int i = 0; i < 5; i++) {
		report->timeline_push();
	}
	const TypedArray<Dictionary> timeline = report->timeline();
	REQUIRE(timeline.size() == 3);
	CHECK(int(Dictionary(timeline[0])["seq"]) == 2); // Oldest first after wrap-around.
	CHECK(int(Dictionary(timeline[2])["seq"]) == 4);
	CHECK(report->to_markdown().begins_with("# GPU resource report"));
}

// ---- Instance culling -----------------------------------------------------------------------

namespace {
Vector<Plane> make_box_frustum(float p_half) {
	Vector<Plane> planes;
	planes.push_back(Plane(Vector3(1, 0, 0), p_half));
	planes.push_back(Plane(Vector3(-1, 0, 0), p_half));
	planes.push_back(Plane(Vector3(0, 1, 0), p_half));
	planes.push_back(Plane(Vector3(0, -1, 0), p_half));
	planes.push_back(Plane(Vector3(0, 0, 1), p_half));
	planes.push_back(Plane(Vector3(0, 0, -1), p_half));
	return planes;
}

float next_random(uint32_t &r_state) {
	r_state = r_state * 1664525u + 1013904223u;
	return float((r_state >> 8) & 0xFFFF) / 65535.0f;
}
} // namespace

TEST_CASE("[CgameInstanceCulling] CPU kernel matches brute force") {
	const Vector<Plane> planes = make_box_frustum(10.0f);
	Vector<Vector3> centers;
	Vector<Vector3> halves;
	uint32_t state = 12345u;
	for (int i = 0; i < 500; i++) {
		centers.push_back(Vector3(next_random(state) * 40.0f - 20.0f, next_random(state) * 40.0f - 20.0f, next_random(state) * 40.0f - 20.0f));
		halves.push_back(Vector3(next_random(state) * 3.0f, next_random(state) * 3.0f, next_random(state) * 3.0f));
	}
	const Vector<int32_t> fast = CgameInstanceCulling::cull_cpu_native(centers, halves, planes, CgameInstanceCulling::HiZ());
	const Vector<int32_t> brute = CgameInstanceCulling::cull_brute_force(centers, halves, planes);
	CHECK(fast.size() > 0);
	CHECK(fast.size() < 500);
	CHECK(fast == brute);
}

TEST_CASE("[CgameInstanceCulling] Frustum edge cases") {
	const Vector<Plane> planes = make_box_frustum(10.0f);
	// Touching the plane from outside is culled only when strictly outside.
	CHECK_FALSE(CgameInstanceCulling::outside_frustum(Vector3(11, 0, 0), Vector3(1, 1, 1), planes));
	CHECK(CgameInstanceCulling::outside_frustum(Vector3(11.5f, 0, 0), Vector3(1, 1, 1), planes));
	CHECK_FALSE(CgameInstanceCulling::outside_frustum(Vector3(0, 0, 0), Vector3(50, 50, 50), planes));
	// No planes: everything is visible.
	CHECK_FALSE(CgameInstanceCulling::outside_frustum(Vector3(1e6f, 0, 0), Vector3(), Vector<Plane>()));
}

TEST_CASE("[CgameInstanceCulling] Hi-Z occlusion") {
	CgameInstanceCulling::HiZ hiz;
	hiz.enabled = true;
	hiz.view_proj = Projection(); // Identity: world xyz is already clip space.
	hiz.width = 4;
	hiz.height = 4;
	hiz.depth.resize(16);
	for (int i = 0; i < 16; i++) {
		hiz.depth.write[i] = 0.2f; // Near occluders everywhere.
	}
	// zmin = (0.9 - 0.05) * 0.5 + 0.5 = 0.925 > 0.2: hidden behind the occluder.
	CHECK(CgameInstanceCulling::occluded(Vector3(0, 0, 0.9f), Vector3(0.1f, 0.1f, 0.05f), hiz));
	// In front of the occluder: visible.
	CHECK_FALSE(CgameInstanceCulling::occluded(Vector3(0, 0, -0.9f), Vector3(0.1f, 0.1f, 0.05f), hiz));
	// Fully off screen: never occlusion-culled.
	CHECK_FALSE(CgameInstanceCulling::occluded(Vector3(5, 5, 0.9f), Vector3(0.1f, 0.1f, 0.05f), hiz));
	// The Hi-Z test only runs when enabled.
	const Vector<Plane> planes = make_box_frustum(10.0f);
	Vector<Vector3> centers;
	centers.push_back(Vector3(0, 0, 0.9f));
	Vector<Vector3> halves;
	halves.push_back(Vector3(0.1f, 0.1f, 0.05f));
	CHECK(CgameInstanceCulling::cull_cpu_native(centers, halves, planes, hiz).is_empty());
	CHECK(CgameInstanceCulling::cull_cpu_native(centers, halves, planes, CgameInstanceCulling::HiZ()).size() == 1);
}

TEST_CASE("[CgameInstanceCulling] Object API with forced CPU path") {
	Ref<CgameInstanceCulling> culling;
	culling.instantiate();
	culling->set_force_cpu(true);
	Array planes;
	for (const Plane &p : make_box_frustum(10.0f)) {
		planes.push_back(p);
	}
	PackedVector3Array centers;
	centers.push_back(Vector3(0, 0, 0));
	centers.push_back(Vector3(30, 0, 0));
	centers.push_back(Vector3(-9, 9, 9));
	PackedFloat32Array radii;
	radii.push_back(1.0f);
	radii.push_back(1.0f);
	radii.push_back(1.0f);
	const PackedInt32Array visible = culling->cull_spheres(centers, radii, planes);
	CHECK(culling->get_last_path() == "cpu");
	REQUIRE(visible.size() == 2);
	CHECK(visible[0] == 0);
	CHECK(visible[1] == 2);

	Array boxes;
	boxes.push_back(AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)));
	boxes.push_back(AABB(Vector3(20, 0, 0), Vector3(2, 2, 2)));
	const PackedInt32Array box_visible = culling->cull(boxes, planes);
	REQUIRE(box_visible.size() == 1);
	CHECK(box_visible[0] == 0);
	CHECK(culling->generate_compute_source().begins_with("#[compute]"));
}

// ---- Impostors ------------------------------------------------------------------------------

TEST_CASE("[CgameImpostorBaker] Frame size") {
	const Vector2 size = CgameImpostorBaker::frame_size_for_aabb(AABB(Vector3(-1, 0, -1), Vector3(2, 4, 2)));
	CHECK(size.x == doctest::Approx(4.0f * 1.05f)); // Height dominates the 2.83 diagonal.
	CHECK(size.y == doctest::Approx(2.0f));
	const Vector2 wide = CgameImpostorBaker::frame_size_for_aabb(AABB(Vector3(-3, 1, -4), Vector3(6, 1, 8)));
	CHECK(wide.x == doctest::Approx(10.0f * 1.05f)); // 6x8 footprint has a diagonal of 10.
	CHECK(wide.y == doctest::Approx(1.5f));
	const Vector2 empty = CgameImpostorBaker::frame_size_for_aabb(AABB());
	CHECK(empty.x == doctest::Approx(0.05f * 1.05f));
	CHECK(CgameImpostorBaker::frame_size(Ref<Mesh>()) == Vector2(1.0f, 0.5f));
	CHECK(CgameImpostorBaker::atlas_width() == CgameImpostorBaker::FRAMES * CgameImpostorBaker::RESOLUTION);
}

TEST_CASE("[CgameImpostorBaker] Shader and material") {
	Ref<Shader> shader = CgameImpostorBaker::get_impostor_shader();
	REQUIRE(shader.is_valid());
	CHECK(shader->get_code().begins_with("shader_type spatial"));
	CHECK(CgameImpostorBaker::get_impostor_shader() == shader);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<ShaderMaterial> material = CgameImpostorBaker::material_for(mesh, Ref<Texture2D>());
	REQUIRE(material.is_valid());
	CHECK(material->get_shader() == shader);
	CHECK(float(material->get_shader_parameter("frames")) == doctest::Approx(float(CgameImpostorBaker::FRAMES)));
	CHECK(CgameImpostorBaker::get_cached(mesh).is_null());
}

TEST_CASE("[ImpostorField3D] Range tiers") {
	CHECK(ImpostorField3D::range_factor_for_level(0) == 0.0f);
	CHECK(ImpostorField3D::range_factor_for_level(1) == doctest::Approx(1.8f));
	CHECK(ImpostorField3D::range_factor_for_level(2) == doctest::Approx(2.2f));
	CHECK(ImpostorField3D::range_factor_for_level(3) == doctest::Approx(2.8f));
	CHECK(ImpostorField3D::range_factor_for_level(42) == doctest::Approx(2.8f));
	CHECK(ImpostorField3D::end_distance_for(50.0f, 2.2f) == doctest::Approx(110.0f));
}

TEST_CASE("[ImpostorField3D] Rebuild builds a hidden MultiMesh") {
	ImpostorField3D::configure(2);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	TypedArray<Transform3D> placements;
	placements.push_back(Transform3D(Basis(), Vector3(0, 0, 0)));
	placements.push_back(Transform3D(Basis(), Vector3(10, 0, 5)));
	placements.push_back(Transform3D(Basis(), Vector3(-4, 1, 8)));

	ImpostorField3D *field = memnew(ImpostorField3D);
	field->set_source_mesh(mesh);
	field->set_placements(placements);
	field->set_mesh_range(50.0f);
	CHECK(field->rebuild());
	REQUIRE(field->get_multimesh().is_valid());
	CHECK(field->get_multimesh()->get_instance_count() == 3);
	CHECK(field->get_visibility_range_begin() == doctest::Approx(50.0f));
	CHECK(field->get_visibility_range_end() == doctest::Approx(110.0f));
	CHECK_FALSE(field->is_visible()); // Hidden until its atlas is baked.
	CHECK_FALSE(field->is_baked());

	// Performance draws no impostors at all.
	ImpostorField3D::configure(0);
	CHECK_FALSE(field->rebuild());
	CHECK(field->get_multimesh().is_null());
	memdelete(field);
	ImpostorField3D::configure(2);
}

// ---- RT effect helpers ----------------------------------------------------------------------

TEST_CASE("[CgameRTEffect] Settings per tier") {
	CHECK_FALSE(bool(CgameRTEffect::settings(0)["enabled"]));
	CHECK_FALSE(bool(CgameRTEffect::settings(2, "mobile")["enabled"]));
	const Dictionary balanced = CgameRTEffect::settings(1);
	CHECK(bool(balanced["shadows"]));
	CHECK_FALSE(bool(balanced["ao"]));
	const Dictionary ultra = CgameRTEffect::settings(3);
	CHECK(bool(ultra["ao"]));
	CHECK(int(ultra["ao_rays"]) == 2);
	CHECK(int(ultra["max_instances"]) == 768);
	CHECK(float(ultra["max_distance"]) == doctest::Approx(60.0f));
}

TEST_CASE("[CgameRTEffect] Budget helpers") {
	CHECK(CgameRTEffect::group_count(1920) == 240);
	CHECK(CgameRTEffect::group_count(1921) == 241);
	CHECK(CgameRTEffect::group_count(1, 8) == 1);
	CHECK(CgameRTEffect::builds_this_frame(5, 2) == 2);
	CHECK(CgameRTEffect::builds_this_frame(1, 4) == 1);
	CHECK(CgameRTEffect::builds_this_frame(-3, 4) == 0);
	CHECK(CgameRTEffect::budget_take(10, 3) == 3);
	CHECK(CgameRTEffect::budget_take(10, -1) == 0);
}

TEST_CASE("[CgameRTEffect] Eviction picks the oldest stale keys only over the limit") {
	HashMap<int64_t, int64_t> last_used;
	last_used[1] = 10;
	last_used[2] = 400;
	last_used[3] = 5;
	last_used[4] = 20;
	// Under the limit: nothing is evicted.
	CHECK(CgameRTEffect::eviction_candidates_native(last_used, 500, 4, 4).is_empty());
	// Two over the limit: the two oldest entries older than EVICT_AGE (key 3 then 1).
	const Vector<int64_t> victims = CgameRTEffect::eviction_candidates_native(last_used, 500, 6, 4);
	REQUIRE(victims.size() == 2);
	CHECK(victims[0] == 3);
	CHECK(victims[1] == 1);
	// Recently used entries are never evicted, even over the limit.
	CHECK(CgameRTEffect::eviction_candidates_native(last_used, 100, 6, 4).is_empty());
}

TEST_CASE("[CgameRTEffect] Parameter block layout") {
	const Dictionary cfg = CgameRTEffect::settings(3);
	const PackedByteArray params = CgameRTEffect::pack_params(Projection(), Transform3D(), Projection(), Vector3(0, 1, 0), 0.0047f, Size2i(1280, 720), 7, 2, cfg);
	REQUIRE(params.size() == CgameRTEffect::PARAMS_SIZE);
	const float *f = reinterpret_cast<const float *>(params.ptr());
	CHECK(f[0] == 1.0f); // inv_proj identity diagonal.
	CHECK(f[16] == 1.0f); // cam_to_world identity diagonal.
	CHECK(f[48 + 1] == doctest::Approx(1.0f)); // sun direction y.
	CHECK(f[48 + 3] == doctest::Approx(0.0047f));
	CHECK(f[52] == doctest::Approx(1280.0f));
	CHECK(f[53] == doctest::Approx(720.0f));
	CHECK(f[54] == doctest::Approx(7.0f));
	CHECK(f[55] == doctest::Approx(2.0f));
	CHECK(f[56] == doctest::Approx(120.0f)); // shadow tmax for Ultra.
	CHECK(f[57] == doctest::Approx(2.5f)); // AO tmax for Ultra.
	CHECK(f[60] == doctest::Approx(1.0f)); // shadow strength.
	CHECK(f[61] == doctest::Approx(0.85f)); // AO strength.
}

TEST_CASE("[CgameRTEffect] Shader source assembly") {
	const String common = CgameRTEffect::get_common_source();
	CHECK(common.contains("rt_view_pos"));
	for (const String pass : { "rt_shadows", "rt_ao", "rt_denoise" }) {
		const String text = CgameRTEffect::get_pass_source(pass);
		REQUIRE_FALSE(text.is_empty());
		const String prepared = CgameRTEffect::prepare_source("#[compute]\n" + text, common);
		CHECK_FALSE(prepared.contains("#[compute]"));
		CHECK_FALSE(prepared.contains("#include"));
		CHECK(prepared.contains("RtParams"));
	}
	CHECK(CgameRTEffect::get_pass_source("rt_shadows").contains("rayQueryEXT") == false); // Ray query lives in the common block.
	CHECK(common.contains("rayQueryEXT"));
	CHECK(CgameRTEffect::get_pass_source("unknown").is_empty());
	CHECK(CgameRTEffect::shader_path("rt_ao") == "res://shaders/compute/rt_ao.glsl");
}

TEST_CASE("[CgameRTEffect] Nearest selection and geometry packing") {
	TypedArray<Dictionary> candidates;
	const Vector3 positions[] = { Vector3(10, 0, 0), Vector3(2, 0, 0), Vector3(500, 0, 0), Vector3(2, 0, 0) };
	for (const Vector3 &p : positions) {
		Dictionary c;
		c["position"] = p;
		c["radius"] = 0.0f;
		candidates.push_back(c);
	}
	const TypedArray<Dictionary> chosen = CgameRTEffect::select_nearest(candidates, Vector3(), 100.0f, 3);
	REQUIRE(chosen.size() == 3);
	CHECK(Vector3(Dictionary(chosen[0])["position"]).x == 2.0f);
	CHECK(Vector3(Dictionary(chosen[1])["position"]).x == 2.0f); // Tie keeps input order.
	CHECK(Vector3(Dictionary(chosen[2])["position"]).x == 10.0f);

	PackedVector3Array verts;
	verts.push_back(Vector3(1, 2, 3));
	verts.push_back(Vector3(4, 5, 6));
	const PackedByteArray packed = CgameRTEffect::pack_positions(verts);
	CHECK(packed.size() == 24);
	CHECK(reinterpret_cast<const float *>(packed.ptr())[4] == 5.0f);
	PackedInt32Array idx;
	idx.push_back(0);
	idx.push_back(1);
	idx.push_back(2);
	CHECK(CgameRTEffect::pack_indices(idx).size() == 12);

	Ref<BoxMesh> box;
	box.instantiate();
	const Dictionary tri = CgameRTEffect::extract_triangles(box, 0);
	CHECK(bool(tri["ok"]));
	CHECK(PackedInt32Array(tri["indices"]).size() % 3 == 0);
	CHECK_FALSE(bool(CgameRTEffect::extract_triangles(box, 5)["ok"]));
	CHECK_FALSE(bool(CgameRTEffect::extract_triangles(Ref<Mesh>(), 0)["ok"]));
	CHECK(CgameRTEffect::blas_key(box, 3) == int64_t(box->get_instance_id()) * 64 + 3);
}

} // namespace TestCgameRendering
