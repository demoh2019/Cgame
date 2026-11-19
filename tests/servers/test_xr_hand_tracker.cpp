/**************************************************************************/
/*  test_xr_hand_tracker.cpp                                              */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_xr_hand_tracker)

#ifndef XR_DISABLED

#include "servers/xr/xr_hand_tracker.h"

namespace TestXRHandTracker {

TEST_CASE("[XRHandTracker] All hand joint flags are initially cleared") {
	Ref<XRHandTracker> tracker;
	tracker.instantiate();
	REQUIRE(tracker.is_valid());

	for (int i = 0; i < XRHandTracker::HAND_JOINT_MAX; i++) {
		INFO("Hand joint index: ", i);
		const XRHandTracker::HandJoint joint = XRHandTracker::HandJoint(i);
		CHECK(tracker->get_hand_joint_flags(joint).is_empty());
	}
}

TEST_CASE("[XRHandTracker] Changing one joint does not set flags on other joints") {
	Ref<XRHandTracker> tracker;
	tracker.instantiate();
	REQUIRE(tracker.is_valid());

	const XRHandTracker::HandJoint target = XRHandTracker::HAND_JOINT_THUMB_TIP;
	BitField<XRHandTracker::HandJointFlags> flags(XRHandTracker::HAND_JOINT_FLAG_POSITION_VALID);
	flags.set_flag(XRHandTracker::HAND_JOINT_FLAG_LINEAR_VELOCITY_VALID);
	tracker->set_hand_joint_flags(target, flags);

	const BitField<XRHandTracker::HandJointFlags> result = tracker->get_hand_joint_flags(target);
	CHECK(result.has_flag(XRHandTracker::HAND_JOINT_FLAG_POSITION_VALID));
	CHECK(result.has_flag(XRHandTracker::HAND_JOINT_FLAG_LINEAR_VELOCITY_VALID));
	CHECK_FALSE(result.has_flag(XRHandTracker::HAND_JOINT_FLAG_ORIENTATION_VALID));

	for (int i = 0; i < XRHandTracker::HAND_JOINT_MAX; i++) {
		const XRHandTracker::HandJoint joint = XRHandTracker::HandJoint(i);
		if (joint != target) {
			INFO("Unmodified hand joint index: ", i);
			CHECK(tracker->get_hand_joint_flags(joint).is_empty());
		}
	}

	tracker->set_hand_joint_flags(XRHandTracker::HAND_JOINT_WRIST, XRHandTracker::HAND_JOINT_FLAG_ORIENTATION_TRACKED);
	CHECK(tracker->get_hand_joint_flags(XRHandTracker::HAND_JOINT_WRIST).has_flag(XRHandTracker::HAND_JOINT_FLAG_ORIENTATION_TRACKED));
	CHECK(tracker->get_hand_joint_flags(target).has_flag(XRHandTracker::HAND_JOINT_FLAG_LINEAR_VELOCITY_VALID));

	tracker->set_hand_joint_flags(target, BitField<XRHandTracker::HandJointFlags>());
	CHECK(tracker->get_hand_joint_flags(target).is_empty());
	CHECK(tracker->get_hand_joint_flags(XRHandTracker::HAND_JOINT_WRIST).has_flag(XRHandTracker::HAND_JOINT_FLAG_ORIENTATION_TRACKED));
}

} // namespace TestXRHandTracker

#endif // XR_DISABLED
