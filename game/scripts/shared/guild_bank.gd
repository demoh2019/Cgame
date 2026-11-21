extends RefCounted
## Albion-style guild bank: a shared hub vault per verified guild. Any member can
## deposit; only the leader and officers (Nakama rank 0-1) can withdraw. A short
## ledger shows who moved what. Guild identity comes only from the server-side
## Nakama check (GuildIdentity), never from a client command.

const Defs = preload("res://scripts/shared/defs.gd")

const MAX_KINDS := 96
const MAX_COUNT := 1000000
const LEDGER_SIZE := 20
const OFFICER_MAX_RANK := 1


static func can_withdraw(rank: int) -> bool:
	return rank >= 0 and rank <= OFFICER_MAX_RANK


## Why a deposit of `count` x `item_id` into `vault` is refused ("" when allowed).
static func deposit_refusal(vault: Dictionary, item_id: String, count: int) -> String:
	if not Defs.is_item(item_id):
		return "invalid_item"
	if count < 1:
		return "invalid_quantity"
	if not vault.has(item_id) and vault.size() >= MAX_KINDS:
		return "vault_full"
	if int(vault.get(item_id, 0)) + count > MAX_COUNT:
		return "vault_full"
	return ""


static func add_ledger(ledger: Array, who: String, action: String, item_id: String, count: int, at: float) -> void:
	ledger.append({"who": who, "action": action, "item": item_id, "count": count, "at": at})
	while ledger.size() > LEDGER_SIZE:
		ledger.pop_front()
