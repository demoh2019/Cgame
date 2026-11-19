/**************************************************************************/
/*  test_refcounted_initial_ownership.cpp                                 */
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

TEST_FORCE_LINK(test_refcounted_initial_ownership)

#include "core/object/class_db.h"
#include "core/object/ref_counted.h"

#ifdef THREADS_ENABLED
#include <thread>
#include <vector>
#endif

namespace TestRefCountedInitialOwnership {

class TrackedRef : public RefCounted {
	GDCLASS(TrackedRef, RefCounted);

protected:
	static void _bind_methods() {}

public:
	static int destructed;

	~TrackedRef() {
		destructed++;
	}
};

int TrackedRef::destructed = 0;

TEST_CASE("[RefInitialOwnership] New RefCounted owns exactly one physical reference") {
	const int before = TrackedRef::destructed;
	ObjectID id;
	{
		Ref<TrackedRef> owner = memnew(TrackedRef);
		REQUIRE(owner.is_valid());
		CHECK_EQ(owner->get_reference_count(), 1);
		id = owner->get_instance_id();
		CHECK(ObjectDB::get_instance(id) == owner.ptr());
	}
	CHECK_EQ(TrackedRef::destructed, before + 1);
	CHECK(ObjectDB::get_instance(id) == nullptr);
}

TEST_CASE("[RefInitialOwnership] Copy increments and destruction decrements count") {
	const int before = TrackedRef::destructed;
	Ref<TrackedRef> owner = memnew(TrackedRef);
	REQUIRE(owner.is_valid());
	CHECK_EQ(owner->get_reference_count(), 1);
	{
		Ref<TrackedRef> copy = owner;
		CHECK_EQ(owner->get_reference_count(), 2);
		{
			Ref<TrackedRef> third(copy);
			CHECK_EQ(owner->get_reference_count(), 3);
		}
		CHECK_EQ(owner->get_reference_count(), 2);
	}
	CHECK_EQ(owner->get_reference_count(), 1);
	owner = Ref<TrackedRef>();
	CHECK_EQ(TrackedRef::destructed, before + 1);
}

TEST_CASE("[RefInitialOwnership] Cross-type references retain shared ownership") {
	const int before = TrackedRef::destructed;
	Ref<TrackedRef> owner = memnew(TrackedRef);
	{
		Ref<RefCounted> base = owner;
		REQUIRE(base.is_valid());
		CHECK_EQ(owner->get_reference_count(), 2);
		CHECK_EQ(base->get_reference_count(), 2);
	}
	CHECK_EQ(owner->get_reference_count(), 1);
	owner = Ref<TrackedRef>();
	CHECK_EQ(TrackedRef::destructed, before + 1);
}

TEST_CASE("[RefInitialOwnership] Ref.instantiate adopts initial reference and frees replacement") {
	const int before = TrackedRef::destructed;
	Ref<TrackedRef> owner;
	owner.instantiate();
	REQUIRE(owner.is_valid());
	CHECK_EQ(owner->get_reference_count(), 1);
	owner.instantiate();
	REQUIRE(owner.is_valid());
	CHECK_EQ(owner->get_reference_count(), 1);
	CHECK_EQ(TrackedRef::destructed, before + 1);
	owner = Ref<TrackedRef>();
	CHECK_EQ(TrackedRef::destructed, before + 2);
}

TEST_CASE("[RefInitialOwnership] assume_ownership overtakes an existing manual reference") {
	const int before = TrackedRef::destructed;
	Ref<TrackedRef> owner = memnew(TrackedRef);
	REQUIRE(owner.is_valid());
	CHECK(owner->reference());
	CHECK_EQ(owner->get_reference_count(), 2);
	{
		Ref<TrackedRef> borrowed = Ref<TrackedRef>::assume_ownership(owner.ptr());
		CHECK_EQ(borrowed->get_reference_count(), 2);
	}
	CHECK_EQ(owner->get_reference_count(), 1);
	owner = Ref<TrackedRef>();
	CHECK_EQ(TrackedRef::destructed, before + 1);
}

TEST_CASE("[RefInitialOwnership] Legacy ClassDB raw creation converts to Ref without leaks") {
	Object *object = ClassDB::instantiate(SNAME("RefCounted"));
	REQUIRE(object != nullptr);
	RefCounted *raw = Object::cast_to<RefCounted>(object);
	REQUIRE(raw != nullptr);
	ObjectID id = raw->get_instance_id();
	{
		Ref<RefCounted> owner(raw);
		REQUIRE(owner.is_valid());
		CHECK_EQ(owner->get_reference_count(), 1);
	}
	CHECK(ObjectDB::get_instance(id) == nullptr);
}

TEST_CASE("[RefInitialOwnership] memnew non-RefCounted still returns a raw pointer") {
	struct PlainObject {
		int value = 73;
	};
	PlainObject *raw = memnew(PlainObject);
	REQUIRE(raw != nullptr);
	CHECK_EQ(raw->value, 73);
	memdelete(raw);
}

#ifdef THREADS_ENABLED
TEST_CASE("[RefInitialOwnership] Concurrent copies leave the original reference intact") {
	const int before = TrackedRef::destructed;
	Ref<TrackedRef> owner = memnew(TrackedRef);
	REQUIRE(owner.is_valid());
	std::vector<std::thread> workers;
	for (int i = 0; i < 4; i++) {
		workers.emplace_back([owner]() {
			for (int j = 0; j < 1024; j++) {
				Ref<TrackedRef> copy = owner;
				(void)copy;
			}
		});
	}
	for (std::thread &worker : workers) {
		worker.join();
	}
	CHECK_EQ(owner->get_reference_count(), 1);
	owner = Ref<TrackedRef>();
	CHECK_EQ(TrackedRef::destructed, before + 1);
}
#endif

} // namespace TestRefCountedInitialOwnership
