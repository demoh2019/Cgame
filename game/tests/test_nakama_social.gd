extends SceneTree
## Needs a running Nakama. Two players: world chat both ways, a guild created by one and joined by the other,
## guild-only chat that a non-member does not get.
##   godot --headless --path game --script res://tests/test_nakama_social.gd

const Social = preload("res://scripts/client/social.gd")

var failures: Array[String] = []
var checks := 0
var inbox: Dictionary = {} # label of the receiver -> Array of "channel|sender|text"


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL " + message)


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _make(label: String) -> Node:
	var social := Social.new()
	root.add_child(social)
	inbox[label] = []
	social.message_received.connect(func(channel: String, sender: String, text: String) -> void: inbox[label].append("%s|%s|%s" % [channel, sender, text]))
	return social


func _run() -> void:
	var tag := str(Time.get_ticks_usec() % 100000)
	var a := _make("a")
	var b := _make("b")
	var c := _make("c")
	var room := "test-world-" + tag
	for pair in [[a, "Alice" + tag], [b, "Bob" + tag], [c, "Carol" + tag]]:
		var signed_in: Dictionary = await pair[0].sign_in("127.0.0.1", 7350, "social-%s-%s" % [tag, pair[1]], pair[1])
		check(signed_in["ok"], "%s signs in" % pair[1])
		check(await pair[0].start_chat(room), "%s joins chat" % pair[1])
	await a.say("hello world")
	await _wait(0.8)
	check(inbox["b"].has("world|Alice%s|hello world" % tag), "Bob receives Alice's world message: %s" % str(inbox["b"]))
	check(inbox["c"].has("world|Alice%s|hello world" % tag), "Carol too")
	check(inbox["a"].has("world|Alice%s|hello world" % tag), "Alice sees her own message echoed")
	check(not await a.say("   "), "an empty message is not sent")
	check(Social.clean("x".repeat(500)).length() == Social.MAX_MESSAGE_LENGTH, "long messages are cut")

	check((await a.create_guild("Ab"))["ok"] == false, "a too short guild name is refused")
	var created: Dictionary = await a.create_guild("Ravens" + tag)
	check(created["ok"], "Alice creates a guild: %s" % str(created))
	check(a.guild.get("name", "") == "Ravens" + tag, "Alice is in it")
	check(not (await a.create_guild("Second" + tag))["ok"], "a member cannot found a second guild")
	var listed: Array = await b.list_guilds("Ravens" + tag)
	check(listed.size() == 1 and listed[0]["name"] == "Ravens" + tag, "Bob finds the guild: %s" % str(listed))
	var joined: Dictionary = await b.join_guild(listed[0]["id"])
	check(joined["ok"], "Bob joins the open guild: %s" % str(joined))
	check(b.guild.get("id", "") == a.guild.get("id", "x"), "same guild")
	var members: Array = await a.guild_members()
	check(members.has("Alice" + tag) and members.has("Bob" + tag) and members.size() == 2, "two members: %s" % str(members))

	inbox["a"].clear(); inbox["b"].clear(); inbox["c"].clear()
	check(await a.say_guild("guild secret"), "Alice talks to the guild")
	await _wait(0.8)
	check(inbox["b"].has("guild|Alice%s|guild secret" % tag), "Bob receives the guild message: %s" % str(inbox["b"]))
	check(inbox["c"].is_empty(), "Carol, not a member, hears nothing: %s" % str(inbox["c"]))
	check(not await c.say_guild("let me in"), "a non-member has no guild channel to speak in")
	check(await b.leave_guild(), "Bob leaves")
	check(b.guild.is_empty(), "and is no longer in a guild")
	for social in [a, b, c]:
		social.shutdown()
	print("NAKAMA SOCIAL TEST %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
