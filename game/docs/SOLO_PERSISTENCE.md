# Local solo character persistence

**Play solo** now keeps one survivor and its stash/progression between sessions even when Nakama is not installed.

- The title-screen Play solo button starts a real loopback-only dedicated server using `--solo-character user://albion_after_solo_character.json` when no local Nakama service exists. The existing `--world-save user://solo_world.json` remains responsible for world barriers/holds. The ENet server accepts only a loopback connection and one player. Public dedicated servers never gain unauthenticated character persistence.
- The server reads a versioned, world-seed-scoped single-character file **before it listens for clients**. Existing corrupt, invalid or wrong-seed files fail startup rather than minting a fresh backpack. It uses `GameServer.valid_character_data` and its existing inventory/progression/save limits.
- Changes are saved every 20 seconds, on disconnect and during orderly server shutdown. Writes use a flushed temporary file and atomic rename. An `--solo-stop` signal lets the launcher ask its child server to flush character and world checkpoints before exiting; after a bounded timeout the launcher retains a hard-kill fallback.
- If Nakama is available at solo start, character persistence uses the existing account-backed Nakama path instead, rather than mixing local and online saves. A solo local account uses a server-defined identity solely for persistent owned structures.
- Network clients cannot supply item amounts, a save path, a stored character or a persistent account identity via RPC. No new network protocol commands, save fields or native engine extension are necessary.

Regression suite: `tests/test_solo_character_store.gd`, registered in `tests/run_all.gd`.
