-- Albion After: server side persistence on top of Nakama.
-- The real-time world runs in the Godot server, which is the only caller of the character_* RPCs
-- (they need the runtime http key). Players talk to Nakama directly for accounts, chat and guilds.

local nk = require("nakama")

local COLLECTION = "character"
local KEY = "main"
local LEADERBOARD = "kills"
local RECEIPTS = "trade_receipt"

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

local function require_user_id(value)
  if type(value) ~= "string" or #value ~= 36 or not value:match("^[%da-fA-F%-]+$") then
    error({ "invalid user ID", 3 })
  end
end

local function require_character_document(data)
  if type(data) ~= "table" or type(data.json) ~= "string" or #data.json < 2 or #data.json > 120000 then
    error({ "invalid character document", 3 })
  end
end

local function require_version(version, allow_create)
  if type(version) ~= "string" or version == "" or #version > 128 or (version == "*" and not allow_create) then
    error({ "character version required", 3 })
  end
end

local function character_object(user_id, data, version)
  return {
    collection = COLLECTION, key = KEY, user_id = user_id,
    value = data, version = version,
    permission_read = 1, permission_write = 0,
  }
end

-- Loads a character. Returns {"exists": false} for a new player.
local function character_load(context, payload)
  require_server(context)
  local request = decode(payload)
  require_user_id(request.user_id)
  local objects = nk.storage_read({ { collection = COLLECTION, key = KEY, user_id = request.user_id } })
  if #objects == 0 then
    return nk.json_encode({ exists = false, version = "*" })
  end
  return nk.json_encode({ exists = true, data = objects[1].value, version = objects[1].version })
end

-- Each save carries the version returned by character_load or the previous save.
-- A stale server cannot overwrite a character after a trade committed on another shard.
local function character_save(context, payload)
  require_server(context)
  local request = decode(payload)
  require_user_id(request.user_id)
  require_character_document(request.data)
  require_version(request.version, true)
  local ok, acks = pcall(nk.storage_write, { character_object(request.user_id, request.data, request.version) })
  if not ok or type(acks) ~= "table" or #acks ~= 1 then
    return nk.json_encode({ ok = false, reason = "write_conflict_or_unavailable" })
  end
  return nk.json_encode({ ok = true, version = acks[1].version })
end


-- All THREE records (both character snapshots and the replay receipt) are
-- written in one Nakama storage transaction with version preconditions.
-- This is only the storage primitive. The world server must lock both live
-- characters while awaiting it before using it for actual market settlement.
local function character_pair_save(context, payload)
  require_server(context)
  local request = decode(payload)
  require_user_id(request.user_a)
  require_user_id(request.user_b)
  if request.user_a == request.user_b then
    error({ "distinct accounts required", 3 })
  end
  require_character_document(request.data_a)
  require_character_document(request.data_b)
  require_version(request.version_a, false)
  require_version(request.version_b, false)
  local id = request.transaction_id
  if type(id) ~= "string" or #id < 8 or #id > 96 or not id:match("^[%w%-]+$") then
    error({ "invalid transaction ID", 3 })
  end
  local receipt_key = { collection = RECEIPTS, key = id }
  local hash_a = nk.hmac_sha256_hash(request.data_a.json, "afterlands-pair-v1")
  local hash_b = nk.hmac_sha256_hash(request.data_b.json, "afterlands-pair-v1")

  local function existing_receipt()
    local objects = nk.storage_read({ receipt_key })
    if #objects == 0 then
      return nil
    end
    local receipt = objects[1].value
    if receipt.user_a ~= request.user_a or receipt.user_b ~= request.user_b
      or receipt.hash_a ~= hash_a or receipt.hash_b ~= hash_b then
      return nk.json_encode({ ok = false, reason = "transaction_id_conflict" })
    end
    -- Re-read current versions; a later valid autosave may already have happened.
    local versions = nk.storage_read({
      { collection = COLLECTION, key = KEY, user_id = request.user_a },
      { collection = COLLECTION, key = KEY, user_id = request.user_b },
    })
    if #versions ~= 2 then
      return nk.json_encode({ ok = false, reason = "missing_character" })
    end
    local map = {}
    for _, obj in ipairs(versions) do
      map[obj.user_id] = obj
    end
    -- A receipt may outlive further legitimate character updates. A replay
    -- must not teach a stale world server the latest version of newer data.
    if map[request.user_a] == nil or map[request.user_b] == nil
      or map[request.user_a].value.json ~= request.data_a.json
      or map[request.user_b].value.json ~= request.data_b.json then
      return nk.json_encode({ ok = false, reason = "transaction_replay_advanced" })
    end
    return nk.json_encode({ ok = true, replayed = true,
      version_a = map[request.user_a].version, version_b = map[request.user_b].version })
  end

  local replay = existing_receipt()
  if replay ~= nil then
    return replay
  end
  local writes = {
    character_object(request.user_a, request.data_a, request.version_a),
    character_object(request.user_b, request.data_b, request.version_b),
    { collection = RECEIPTS, key = id, version = "*",
      value = { user_a = request.user_a, user_b = request.user_b,
        hash_a = hash_a, hash_b = hash_b },
      permission_read = 0, permission_write = 0 },
  }
  local ok, acks = pcall(nk.storage_write, writes)
  if not ok or type(acks) ~= "table" or #acks ~= 3 then
    -- Ambiguous network failures may have committed: check the durable receipt.
    replay = existing_receipt()
    if replay ~= nil then
      return replay
    end
    return nk.json_encode({ ok = false, reason = "write_conflict_or_unavailable" })
  end
  return nk.json_encode({ ok = true, replayed = false,
    version_a = acks[1].version, version_b = acks[2].version })
end

-- Resolve one accepted Nakama guild for an authenticated account.
-- Invocation requires the server key; the ENet client never supplies its
-- own guild identity. Pending applications (state 3+) do not count.
local function guild_affiliation(context, payload)
  require_server(context)
  local request = decode(payload)
  require_user_id(request.user_id)
  local ok, groups = pcall(nk.user_groups_list, request.user_id, 100)
  if not ok or type(groups) ~= "table" then
    return nk.json_encode({ ok = false, reason = "guild_directory_unavailable" })
  end
  local entries = groups.user_groups or groups
  for _, membership in ipairs(entries) do
    local state = tonumber(membership.state)
    local guild = membership.group
    if state ~= nil and state >= 0 and state <= 2 and type(guild) == "table"
      and type(guild.id) == "string" and type(guild.name) == "string" then
      return nk.json_encode({
        ok = true, guild_id = guild.id, guild_name = guild.name, rank = state,
      })
    end
  end
  return nk.json_encode({ ok = true, guild_id = "", guild_name = "", rank = -1 })
end

-- Immutable siege receipts and CAS-based guild score increments. Both the
-- receipt and score update are one Nakama storage transaction, not two writes.
-- This is the durable victory history, NOT persistent outpost ownership.
local SIEGE_SCORES = "guild_siege_scores"
local SIEGE_RECEIPTS = "guild_siege_receipts"
local MAX_SIEGE_WINS = 1000000

local function require_guild_id(value)
  if type(value) ~= "string" or #value ~= 36
    or not value:match("^[%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x]$") then
    error({ "invalid guild id", 3 })
  end
end

local function siege_score_read(guild_id)
  local records = nk.storage_read({ { collection = SIEGE_SCORES, key = guild_id } })
  if #records == 0 then return 0, "*" end
  local value = records[1].value
  local wins = value and value.wins
  if type(wins) ~= "number" or wins < 0 or wins > MAX_SIEGE_WINS
    or wins ~= math.floor(wins) then
    error({ "invalid guild siege score", 13 })
  end
  return wins, records[1].version
end

local function guild_siege_score(context, payload)
  require_server(context)
  local request = decode(payload)
  require_guild_id(request.guild_id)
  local count = siege_score_read(request.guild_id)
  return nk.json_encode({ ok = true, wins = count })
end

local function guild_siege_commit(context, payload)
  require_server(context)
  local request = decode(payload)
  require_guild_id(request.guild_id)
  local tx_id = request.event_id
  if type(tx_id) ~= "string" or not tx_id:match("^[0-9a-f]+$") or #tx_id ~= 32 then
    error({ "invalid siege event id", 3 })
  end
  local site = request.site
  local seed = request.world_seed
  if type(site) ~= "number" or site ~= math.floor(site) or site < 1 or site > 25
    or type(seed) ~= "number" or seed ~= math.floor(seed)
    or seed < -2147483648 or seed > 2147483647 then
    error({ "invalid siege event metadata", 3 })
  end

  local receipt_key = { collection = SIEGE_RECEIPTS, key = tx_id }
  local function read_receipt()
    local receipts = nk.storage_read({ receipt_key })
    if #receipts == 0 then return nil end
    local receipt = receipts[1].value
    if receipt.guild_id ~= request.guild_id or receipt.site ~= site
      or receipt.world_seed ~= seed then
      return nk.json_encode({ ok = false, reason = "event_id_conflict" })
    end
    local current = siege_score_read(request.guild_id)
    return nk.json_encode({ ok = true, replayed = true, wins = current })
  end

  for _ = 1, 5 do
    local existing = read_receipt()
    if existing then return existing end
    local wins, version = siege_score_read(request.guild_id)
    if wins >= MAX_SIEGE_WINS then
      return nk.json_encode({ ok = false, reason = "score_limit" })
    end
    local writes = {
      { collection = SIEGE_SCORES, key = request.guild_id, version = version,
        value = { wins = wins + 1 }, permission_read = 0, permission_write = 0 },
      { collection = SIEGE_RECEIPTS, key = tx_id, version = "*",
        value = { guild_id = request.guild_id, site = site, world_seed = seed },
        permission_read = 0, permission_write = 0 },
    }
    local ok, ack = pcall(nk.storage_write, writes)
    if ok and type(ack) == "table" and #ack == 2 then
      return nk.json_encode({ ok = true, replayed = false, wins = wins + 1 })
    end
    -- Either an optimistic-version collision or an ambiguous committed
    -- response. Always probe the receipt before attempting another write.
    local retry = read_receipt()
    if retry then return retry end
  end
  return nk.json_encode({ ok = false, reason = "retry_later" })
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
nk.register_rpc(character_pair_save, "character_pair_save")
nk.register_rpc(guild_affiliation, "guild_affiliation")
nk.register_rpc(guild_siege_score, "guild_siege_score")
nk.register_rpc(guild_siege_commit, "guild_siege_commit")
nk.register_rpc(leaderboard_submit, "leaderboard_submit")
