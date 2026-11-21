/**************************************************************************/
/*  cgame_ai_common.h                                                     */
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

#include "core/object/class_db.h"
#include "core/string/ustring.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/vector.h"
#include "core/variant/binder_common.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

namespace CgameAI {

// GDScript "==" semantics: mismatched, non-comparable types are simply unequal.
_FORCE_INLINE_ bool variants_equal(const Variant &p_a, const Variant &p_b) {
	bool valid = false;
	Variant result;
	Variant::evaluate(Variant::OP_EQUAL, p_a, p_b, result, valid);
	return valid && bool(result);
}

// True when every key of `p_conditions` exists in `p_state` with an equal value.
_FORCE_INLINE_ bool state_holds(const Dictionary &p_state, const Dictionary &p_conditions) {
	const Array keys = p_conditions.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant &key = keys[i];
		if (!p_state.has(key) || !variants_equal(p_state[key], p_conditions[key])) {
			return false;
		}
	}
	return true;
}

} // namespace CgameAI
