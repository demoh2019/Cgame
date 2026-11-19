/**************************************************************************/
/*  ref_counted.h                                                         */
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

#include "core/object/object.h"
#include "core/templates/safe_refcount.h"

// New RefCounted instances begin with one owned reference. Creation through
// memnew() hands that reference directly to the returned Ref<T>.
class RefCounted : public Object {
	GDCLASS(RefCounted, Object);
	SafeRefCount refcount;
	// Effective refcount offset for legacy APIs which expect initial zero.
	SafeNumeric<uint32_t> negative_refcount{ 0 };
	SafeNumeric<uint32_t> dereference_count{ 0 };

protected:
	static void _bind_methods();

public:
	static constexpr AncestralClass static_ancestral_class = AncestralClass::REF_COUNTED;

	bool init_ref();
	void deinit_ref(); // Adds one effective negative reference for legacy callers.
	bool reference(); // returns false if refcount is at zero and didn't get increased
	bool unreference();
	int get_reference_count() const;

	RefCounted();
};

template <typename T>
class Ref {
	T *reference = nullptr;

	_FORCE_INLINE_ void ref(const Ref &p_from) {
		ref_pointer<false>(p_from.reference);
	}

	template <bool Init>
	_FORCE_INLINE_ void ref_pointer(T *p_refcounted) {
		if (p_refcounted == reference) {
			return;
		}

		// This will go out of scope and get unref'd.
		Ref cleanup_ref;
		cleanup_ref.reference = reference;
		reference = p_refcounted;
		if (reference) {
			if constexpr (Init) {
				if (!reference->init_ref()) {
					reference = nullptr;
				}
			} else {
				if (!reference->reference()) {
					reference = nullptr;
				}
			}
		}
	}

	//virtual RefCounted * get_reference() const { return reference; }
public:
	static _FORCE_INLINE_ String get_class_static() {
		return T::get_class_static();
	}

	_FORCE_INLINE_ bool operator==(const T *p_ptr) const {
		return reference == p_ptr;
	}
	_FORCE_INLINE_ bool operator!=(const T *p_ptr) const {
		return reference != p_ptr;
	}
#ifdef STRICT_CHECKS
	// Delete these to prevent raw comparisons with `nullptr`.
	bool operator==(std::nullptr_t) const = delete;
	bool operator!=(std::nullptr_t) const = delete;
#endif // STRICT_CHECKS

	_FORCE_INLINE_ bool operator<(const Ref<T> &p_r) const {
		return reference < p_r.reference;
	}
	_FORCE_INLINE_ bool operator==(const Ref<T> &p_r) const {
		return reference == p_r.reference;
	}
	_FORCE_INLINE_ bool operator!=(const Ref<T> &p_r) const {
		return reference != p_r.reference;
	}

	_FORCE_INLINE_ T *operator*() const {
		return reference;
	}

	_FORCE_INLINE_ T *operator->() const {
		return reference;
	}

	_FORCE_INLINE_ T *ptr() const {
		return reference;
	}

	operator Variant() const {
		static_assert(std::is_base_of_v<RefCounted, T>, "T is not a RefCounted type or is an incomplete type.");
		return Variant(reference);
	}

	void operator=(const Ref &p_from) {
		ref(p_from);
	}

	void operator=(Ref &&p_from) {
		if (reference == p_from.reference) {
			return;
		}
		unref();
		reference = p_from.reference;
		p_from.reference = nullptr;
	}

	template <typename T_Other>
	void operator=(const Ref<T_Other> &p_from) {
		ref_pointer<false>(Object::cast_to<T>(p_from.ptr()));
	}

	void operator=(T *p_from) {
		ref_pointer<true>(p_from);
	}

	void operator=(const Variant &p_variant) {
		Object *object = p_variant.get_validated_object();

		if (object == reference) {
			return;
		}

		ref_pointer<false>(Object::cast_to<T>(object));
	}

	template <typename T_Other>
	void reference_ptr(T_Other *p_ptr) {
		if (reference == p_ptr) {
			return;
		}

		ref_pointer<true>(Object::cast_to<T>(p_ptr));
	}

	// Takes over an already-owned reference without incrementing its count.
	// Only use when the caller owns one existing reference to p_object.
	static Ref assume_ownership(T *p_object) {
		Ref result;
		result.reference = p_object;
		return result;
	}

	Ref(const Ref &p_from) {
		this->operator=(p_from);
	}

	Ref(Ref &&p_from) {
		reference = p_from.reference;
		p_from.reference = nullptr;
	}

	template <typename T_Other>
	Ref(const Ref<T_Other> &p_from) {
		this->operator=(p_from);
	}

	Ref(T *p_from) {
		this->operator=(p_from);
	}

	Ref(const Variant &p_from) {
		this->operator=(p_from);
	}

	inline bool is_valid() const { return reference != nullptr; }
	inline bool is_null() const { return reference == nullptr; }

	void unref() {
		// TODO: this should be moved to mutexes, since this engine does not really
		// do a lot of referencing on references and stuff
		// mutexes will avoid more crashes?

		if (reference) {
			// NOTE: `reinterpret_cast` is "safe" here because we know `T` has simple linear
			// inheritance to `RefCounted`. This guarantees that `T * == `RefCounted *`, which
			// allows us to declare `Ref<T>` with forward declared `T` types.
			if (reinterpret_cast<RefCounted *>(reference)->unreference()) {
				memdelete(reinterpret_cast<RefCounted *>(reference));
			}
			reference = nullptr;
		}
	}

	template <typename... Args>
	void instantiate(Args &&...p_params) {
		Ref<T> ref = memnew(T(std::forward<Args>(p_params)...));
		// Appropriate the new Ref, and if the previous one was set, free it.
		SWAP(reference, ref.reference);
	}

	uint32_t hash() const { return HashMapHasherDefault::hash(reference); }

	Ref() = default;

	~Ref() {
		unref();
	}
};

template <typename T>
struct memnew_result<T, std::enable_if_t<std::is_base_of_v<RefCounted, T>>> {
	using class_name = Ref<T>;

	static Ref<T> wrap(T *p_object) {
		return Ref<T>::assume_ownership(p_object);
	}
};

// Zero-constructing Ref initializes reference to nullptr (and thus empty).
template <typename T>
struct is_zero_constructible<Ref<T>> : std::true_type {};

template <typename T>
Ref<T> ObjectDB::get_ref(ObjectID p_instance_id) {
	return Ref<T>(get_instance(p_instance_id));
}
