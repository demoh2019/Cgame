/**************************************************************************/
/*  test_gameplay_ability_system.h                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.       */
/**************************************************************************/

#pragma once

#include "../gameplay_ability_system.h"
#include "tests/test_macros.h"

namespace TestGameplayAbilitySystem {

static Dictionary ability(double p_cost, double p_cooldown) {
    Dictionary d;
    d["cost"] = p_cost;
    d["cooldown"] = p_cooldown;
    return d;
}

TEST_CASE("[GameplayAbilitySystem] Invalid definitions are rejected without replacing the original") {
    Ref<GameplayAbilitySystem> system;
    system.instantiate();
    Dictionary initial = ability(25.0, 1.5);
    REQUIRE(system->register_ability("fire", initial));

    Dictionary invalid = ability(-1.0, 0.0);
    CHECK_FALSE(system->register_ability("fire", invalid));
    CHECK_FALSE(system->register_ability("", initial));
    CHECK_FALSE(system->register_ability(" bad ", initial));
    CHECK_FALSE(system->register_ability("other", ability(1.0, -0.5)));
    invalid = ability(1.0, 0.0);
    invalid["required_tags"] = Array();
    CHECK_FALSE(system->register_ability("other", invalid));

    initial["cost"] = 999.0;
    CHECK(double(system->get_ability("fire")["cost"]) == doctest::Approx(25.0));
    Dictionary copy = system->get_ability("fire");
    copy["cost"] = 0.0;
    CHECK(double(system->get_ability("fire")["cost"]) == doctest::Approx(25.0));
}

TEST_CASE("[GameplayAbilitySystem] Cost and cooldown are atomic and deterministic") {
    Ref<GameplayAbilitySystem> system;
    system.instantiate();
    REQUIRE(system->register_ability("fire", ability(25.0, 2.0)));
    REQUIRE(system->set_resource(40.0));
    CHECK(system->activate("fire") == GameplayAbilitySystem::ACTIVATED);
    CHECK(system->get_resource() == doctest::Approx(15.0));
    CHECK(system->get_remaining_cooldown("fire") == doctest::Approx(2.0));

    CHECK(system->activate("fire") == GameplayAbilitySystem::ON_COOLDOWN);
    CHECK(system->get_resource() == doctest::Approx(15.0));
    system->tick(-1.0);
    CHECK(system->get_remaining_cooldown("fire") == doctest::Approx(2.0));
    system->tick(1.0);
    CHECK(system->get_remaining_cooldown("fire") == doctest::Approx(1.0));
    system->tick(2.0);
    CHECK(system->get_remaining_cooldown("fire") == doctest::Approx(0.0));
    CHECK(system->activate("fire") == GameplayAbilitySystem::INSUFFICIENT_RESOURCE);
    CHECK(system->get_resource() == doctest::Approx(15.0));
    REQUIRE(system->set_resource(100.0));
    CHECK(system->activate("fire") == GameplayAbilitySystem::ACTIVATED);
    CHECK(system->get_resource() == doctest::Approx(75.0));
}

TEST_CASE("[GameplayAbilitySystem] Hierarchical status tags gate abilities") {
    Ref<GameplayAbilitySystem> system;
    system.instantiate();
    Dictionary spell = ability(5.0, 0.0);
    PackedStringArray required_tags;
    required_tags.push_back("class.mage");
    spell["required_tags"] = required_tags;
    PackedStringArray blocked_tags;
    blocked_tags.push_back("status.stunned");
    spell["blocked_tags"] = blocked_tags;
    REQUIRE(system->register_ability("cast", spell));
    CHECK(system->activate("cast") == GameplayAbilitySystem::MISSING_REQUIRED_TAG);
    CHECK(system->add_tag("class.mage.fire"));
    CHECK(system->has_tag("class.mage"));
    CHECK(system->activate("cast") == GameplayAbilitySystem::ACTIVATED);
    CHECK(system->add_tag("status.stunned.heavy"));
    CHECK(system->activate("cast") == GameplayAbilitySystem::BLOCKED_BY_TAG);
    system->remove_tag("status.stunned.heavy");
    CHECK(system->activate("cast") == GameplayAbilitySystem::ACTIVATED);
}

TEST_CASE("[GameplayAbilitySystem] State roundtrips and rejects invalid input transactionally") {
    Ref<GameplayAbilitySystem> source;
    source.instantiate();
    REQUIRE(source->register_ability("dash", ability(10.0, 3.5)));
    REQUIRE(source->set_max_resource(120.0));
    REQUIRE(source->set_resource(80.0));
    REQUIRE(source->add_tag("class.rogue"));
    REQUIRE(source->activate("dash") == GameplayAbilitySystem::ACTIVATED);
    const Dictionary saved = source->save_state();

    Ref<GameplayAbilitySystem> restored;
    restored.instantiate();
    REQUIRE(restored->register_ability("dash", ability(10.0, 3.5)));
    REQUIRE(restored->load_state(saved));
    CHECK(restored->get_resource() == doctest::Approx(70.0));
    CHECK(restored->get_max_resource() == doctest::Approx(120.0));
    CHECK(restored->get_remaining_cooldown("dash") == doctest::Approx(3.5));
    CHECK(restored->has_tag("class.rogue"));

    Dictionary invalid = saved.duplicate(true);
    invalid["resource"] = 500.0;
    CHECK_FALSE(restored->load_state(invalid));
    CHECK(restored->save_state() == saved);
    invalid = saved.duplicate(true);
    Dictionary invalid_cooldowns;
    invalid_cooldowns["unknown"] = 1.0;
    invalid["cooldowns"] = invalid_cooldowns;
    CHECK_FALSE(restored->load_state(invalid));
    CHECK(restored->save_state() == saved);
}

TEST_CASE("[GameplayAbilitySystem] Instances, cooldowns and tags are independent") {
    Ref<GameplayAbilitySystem> a;
    a.instantiate();
    Ref<GameplayAbilitySystem> b;
    b.instantiate();
    REQUIRE(a->register_ability("dash", ability(5.0, 10.0)));
    REQUIRE(b->register_ability("dash", ability(5.0, 10.0)));
    REQUIRE(a->activate("dash") == GameplayAbilitySystem::ACTIVATED);
    CHECK(b->get_remaining_cooldown("dash") == doctest::Approx(0.0));
    CHECK(b->get_resource() == doctest::Approx(100.0));
    REQUIRE(a->add_tag("status.silenced"));
    CHECK_FALSE(b->has_tag("status.silenced"));
    a->unregister_ability("dash");
    CHECK_FALSE(a->has_ability("dash"));
    CHECK(b->has_ability("dash"));
}

} // namespace TestGameplayAbilitySystem
