extends SceneTree

## Offline, deterministic transactional trade regression for Cgame headless.
## Run: <cgame-editor> --headless --path demo/days_after --script res://smoke_test_trade.gd

func _initialize() -> void:
    call_deferred("_run")


func _assert_trade(ok: bool, details: String) -> bool:
    if ok:
        return true
    push_error("trade smoke failed: " + details)
    quit(1)
    return false


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if not _assert_trade(scene != null, "scene is loadable"):
        return
    var game := scene.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player") as CharacterBody3D
    var trader := game.get_node_or_null("CampTrader")
    var infected := game.get_node_or_null("InfectedWalker")
    if not _assert_trade(survivor != null and trader is Area3D and infected != null,
            "survivor, infected and physical trader exist"):
        return
    if not _assert_trade(int(survivor.get("credits")) == 0
            and not bool(survivor.call("trade_buy", "water", 1))
            and not bool(survivor.call("trade_sell", "wood_t1", 1)),
            "cannot purchase without credits or sell nonexistent inventory"):
        return

    infected.call("take_damage", 1000.0)
    if not _assert_trade(int(survivor.call("get_item_count", "infected_sample")) == 1
            and int(survivor.get("combat_xp")) >= 25,
            "infected defeat grants one recoverable research sample and combat XP"):
        return

    trader.call("interact", survivor)
    if not _assert_trade(int(survivor.get("credits")) == 12
            and int(survivor.call("get_item_count", "infected_sample")) == 0,
            "trader exchanges exactly one sample for fixed credits"):
        return
    trader.call("buy", survivor)
    if not _assert_trade(int(survivor.get("credits")) == 5
            and int(survivor.call("get_item_count", "water")) == 1,
            "purchase spends credits and creates exactly one water bottle"):
        return
    survivor.call("add_item", "wood_t1", 3)
    if not _assert_trade(bool(survivor.call("trade_sell", "wood_t1", 2))
            and int(survivor.get("credits")) == 9
            and int(survivor.call("get_item_count", "wood_t1")) == 1,
            "sell is atomic and has stable price × quantity"):
        return
    if not _assert_trade(bool(survivor.call("trade_buy", "food", 1))
            and int(survivor.get("credits")) == 0
            and int(survivor.call("get_item_count", "food")) == 1,
            "player can convert salvaged materials into survival food"):
        return

    var stock_before := int(survivor.call("get_item_count", "wood_t1"))
    if not _assert_trade(not bool(survivor.call("trade_sell", "wood_t1", 0))
            and not bool(survivor.call("trade_sell", "wood_t1", -1))
            and not bool(survivor.call("trade_sell", "wood_t1", 101))
            and not bool(survivor.call("trade_buy", "unlisted_item", 1))
            and not bool(survivor.call("trade_buy", "water", -9))
            and int(survivor.call("get_item_count", "wood_t1")) == stock_before
            and int(survivor.get("credits")) == 0,
            "invalid/unlisted/oversized transactions do not mutate inventory"):
        return

    survivor.set("credits", 1000000000)
    if not _assert_trade(not bool(survivor.call("trade_sell", "wood_t1", 1))
            and int(survivor.call("get_item_count", "wood_t1")) == stock_before,
            "credit cap prevents currency overflow without consuming items"):
        return
    survivor.set("health", 0.0)
    if not _assert_trade(not bool(survivor.call("trade_buy", "water", 1)),
            "dead players cannot trade"):
        return

    game.queue_free()
    await process_frame
    print("PASS: Days After transactional offline trader, loot, prices, bounds and no duplication.")
    quit(0)
