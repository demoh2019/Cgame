/**************************************************************************/
/*  gameplay_ability_system.h                                             */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.       */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

class GameplayAbilitySystem : public RefCounted {
    GDCLASS(GameplayAbilitySystem, RefCounted);

public:
    enum ActivationResult {
        ACTIVATED,
        UNKNOWN_ABILITY,
        ON_COOLDOWN,
        INSUFFICIENT_RESOURCE,
        MISSING_REQUIRED_TAG,
        BLOCKED_BY_TAG,
    };

private:
    Dictionary definitions;
    Dictionary cooldowns;
    PackedStringArray tags;
    double resource = 100.0;
    double max_resource = 100.0;

    bool _has_matching_tag(const String &p_tag) const;
    static bool _validate_tag_array(const Variant &p_value);
    static bool _validate_definition(const Dictionary &p_definition);

protected:
    static void _bind_methods();

public:
    bool register_ability(const String &p_id, const Dictionary &p_definition);
    void unregister_ability(const String &p_id);
    bool has_ability(const String &p_id) const;
    Dictionary get_ability(const String &p_id) const;

    ActivationResult get_activation_result(const String &p_id) const;
    ActivationResult activate(const String &p_id);
    double get_remaining_cooldown(const String &p_id) const;
    void tick(double p_delta);

    bool add_tag(const String &p_tag);
    void remove_tag(const String &p_tag);
    bool has_tag(const String &p_tag) const;
    PackedStringArray get_tags() const;

    bool set_max_resource(double p_value);
    double get_max_resource() const;
    bool set_resource(double p_value);
    double get_resource() const;

    Dictionary save_state() const;
    bool load_state(const Dictionary &p_state);
};

VARIANT_ENUM_CAST(GameplayAbilitySystem::ActivationResult);
