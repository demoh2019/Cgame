/**************************************************************************/
/*  behavior_tree.h                                                       */
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

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

class BehaviorTree : public RefCounted {
	GDCLASS(BehaviorTree, RefCounted);

public:
	enum Status {
		FAILURE,
		SUCCESS,
		RUNNING,
	};

private:
	Dictionary tree;
	Dictionary blackboard;
	Dictionary memory;

	bool _validate_node(const Variant &p_node, int p_depth, int &r_count) const;
	Status _tick_node(const Dictionary &p_node, const String &p_path);
	void _clear_memory_prefix(const String &p_path);

protected:
	static void _bind_methods();

public:
	// Set a deep-copied tree description. Invalid trees leave the previous one intact.
	bool set_tree(const Dictionary &p_tree);
	Dictionary get_tree() const;

	Status tick();
	void reset();
	void clear_blackboard();
	void set_blackboard_value(const String &p_key, const Variant &p_value);
	Variant get_blackboard_value(const String &p_key, const Variant &p_default = Variant()) const;
	bool has_blackboard_value(const String &p_key) const;
};

VARIANT_ENUM_CAST(BehaviorTree::Status);
