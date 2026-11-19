-- Albion After: server side persistence on top of Nakama.
-- The real-time world runs in the Godot server, which is the only caller of the character_* RPCs
-- (they need the runtime http key). Players talk to Nakama directly for accounts, chat and guilds.

local nk = require("nakama")

local COLLECTION = "character"
local KEY = "main"
local LEADERBOARD = "kills"

-- Called with the runtime http key there is no user in the context; a player session has one.
local function require_server(context)
  if context.user_id ~= nil and context.user_id ~= "" then
    error({ "this call is only for the game server", 7 }) -- 7 = permission denied
  end
end

local function decode(payload)
  if payload == nil or payload == "" then
    error("empty payload")
  end
  return nk.json_decode(payload)
end

-- Loads a character. Returns {"exists": false} for a new player.
local function character_load(context, payload)
  require_server(context)
  local request = decode(payload)
  local objects = nk.storage_read({ { collection = COLLECTION, key = KEY, user_id = request.user_id } })
  if #objects == 0 then
    return nk.json_encode({ exists = false })
  end
  return nk.json_encode({ exists = true, data = objects[1].value })
end

-- Saves a character document written by the game server.
local function character_save(context, payload)
  require_server(context)
  local request = decode(payload)
  nk.storage_write({
    {
      collection = COLLECTION,
      key = KEY,
      user_id = request.user_id,
      value = request.data,
      permission_read = 1, -- The owner may read it (for an out-of-game profile); only the server writes.
      permission_write = 0,
    },
  })
  return nk.json_encode({ ok = true })
end

-- Records a player's lifetime kills on the leaderboard (the score is a "set" so it always reflects the total).
local function leaderboard_submit(context, payload)
  require_server(context)
  local request = decode(payload)
  nk.leaderboard_record_write(LEADERBOARD, request.user_id, request.username, tonumber(request.kills) or 0, tonumber(request.deaths) or 0)
  return nk.json_encode({ ok = true })
end

nk.run_once(function(ctx)
  -- Created once; already existing is not an error.
  pcall(function()
    nk.leaderboard_create(LEADERBOARD, false, "desc", "set", nil, { title = "Most zombies and survivors killed" })
  end)
  nk.logger_info("Albion After backend module loaded")
end)

nk.register_rpc(character_load, "character_load")
nk.register_rpc(character_save, "character_save")
nk.register_rpc(leaderboard_submit, "leaderboard_submit")
