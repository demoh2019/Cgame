extends RefCounted
const NetSchema = preload("res://scripts/shared/net_schema.gd")

func run(t) -> void:
	var schema: Dictionary = {"fields": [NetSchema.make_field("alive", "bool", 1)]}
	var baseline: Dictionary = {"alive": false, "health": 75}
	t.current = "valid schema delta framing"
	var packet: PackedByteArray = NetSchema.serialize(schema, {"alive": true}, {}, true)
	t.eq(packet.size(), 1, "one-bit mask and field share a byte")
	t.eq(NetSchema.deserialize(schema, packet, {}).get("alive"), true,
		"valid partial-byte packet decodes")
	var checked: Dictionary = NetSchema._deserialize_checked(schema, packet, baseline)
	t.check(bool(checked.get("ok", false)), "checked parser accepts zero padding")
	t.eq(checked.get("state", {}).get("health"), 75, "baseline fields are preserved")
	var empty_delta: PackedByteArray = NetSchema.serialize(schema, {}, baseline, true)
	t.eq(NetSchema.deserialize(schema, empty_delta, baseline), baseline,
		"empty delta preserves baseline")

	t.current = "corrupt schema packet framing fails closed"
	t.eq(NetSchema._deserialize_checked(schema, PackedByteArray(), baseline).get("ok"),
		false, "truncated field mask rejected")
	var extra: PackedByteArray = packet.duplicate()
	extra.append(0)
	t.eq(NetSchema._deserialize_checked(schema, extra, baseline).get("ok"),
		false, "extra trailing byte rejected")
	var dirty: PackedByteArray = packet.duplicate()
	dirty[0] |= 0x80
	t.eq(NetSchema._deserialize_checked(schema, dirty, baseline).get("ok"),
		false, "nonzero unused padding bit rejected")
	t.eq(NetSchema.deserialize(schema, dirty, baseline), {},
		"legacy decoder refuses damaged snapshots")

	t.current = "versioned schema frame integrity"
	var versioned: PackedByteArray = NetSchema.serialize_versioned(schema, {"alive": true}, {}, true)
	var version_result: Dictionary = NetSchema.deserialize_versioned(schema, versioned, {})
	t.check(bool(version_result.get("ok", false)), "valid schema hash and payload decode")
	t.eq(version_result.get("state", {}).get("alive"), true, "decoded state matches")
	var with_extra: PackedByteArray = versioned.duplicate()
	with_extra.append(0)
	t.eq(NetSchema.deserialize_versioned(schema, with_extra, {}).get("ok"),
		false, "versioned decoder rejects trailing bytes")
	var wrong_hash: PackedByteArray = versioned.duplicate()
	wrong_hash[0] ^= 1
	t.eq(NetSchema.deserialize_versioned(schema, wrong_hash, {}).get("ok"),
		false, "wrong schema hash rejected")
