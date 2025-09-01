-- ===================================================================
-- FILENAME: stats_manager.lua
-- DESCRIPTION: Main script for gathering and persisting game stats.
--              This is the file to load via the `lua_modules` cvar.
-- ===================================================================

require("database")
require("schema")
local json = require("dkjson")

local modname = "game-stats-sqlite"
local version = "2.0.0"

-- In-memory state (will be reset every map)
local State = {}
local function resetState()
    State = {
        DB_FILE = "legacy/stats.db",
        currentMatchId = nil,
        currentRoundId = nil,
        players = {}, -- Maps clientNum to session data
        obituaries = {},
        damageEvents = {},
        objectiveEvents = {},
        messages = {},
        classSwitches = {},
        lastFrameTime = 0
    }
end

-- ===================================================================
-- Player Management
-- ===================================================================

--- Loads a player from the DB or creates a new entry.
-- Caches the result in the in-memory State table.
local function loadOrCreatePlayer(clientNum)
    local userinfo = et.trap_GetUserinfo(clientNum)
    local guid = et.Info_ValueForKey(userinfo, "cl_guid")
    local name = et.Info_ValueForKey(userinfo, "name")

    if not guid or #guid ~= 32 then return end

    local p = DB.QueryRow("SELECT id FROM players WHERE guid =?;", {guid})
    local player_id

    if p then
        player_id = p.id
        DB.Execute("UPDATE players SET name =? WHERE id =?;", {name, player_id})
    else
        DB.Execute("INSERT INTO players (guid, name) VALUES (?,?);", {guid, name})
        player_id = DB.LastInsertRowId()
    end

    -- Initialize in-memory session data for this player
    State.players[clientNum] = {
        db_id = player_id,
        guid = guid,
        name = name,
        team = et.gentity_get(clientNum, "sess.sessionTeam"),
        stats = {
            weaponStats = {},
            stance_stats = {
                in_prone = 0, in_crouch = 0, in_mg = 0, in_lean = 0,
                in_objcarrier = 0, in_vehiclescort = 0, in_disguise = 0,
                in_sprint = 0, in_turtle = 0, is_downed = 0
            },
            player_speed = { ups_samples = {}, peak_speed_ups = 0 },
            distance_travelled_meters = 0,
            spawn_count = 0,
            distance_travelled_spawn = 0,
            last_position = nil,
            last_stance_check = 0
        }
    }
    et.G_Print(string.format("Loaded player %s (GUID: %s, DB_ID: %d)\n", name, guid, player_id))
end

-- ===================================================================
-- Data Persistence
-- ===================================================================

--- Saves all aggregated data from the completed round to the database.
local function saveRoundStats()
    if not State.currentRoundId then
        et.G_Print("^1WARNING: Cannot save stats, no current round ID.^7\n")
        return
    end

    et.G_Print(string.format("Saving stats for round ID %d...\n", State.currentRoundId))

    local success, err = pcall(function()
        DB.Execute("BEGIN TRANSACTION;")

        for _, pData in pairs(State.players) do
            if pData and pData.db_id then
                local avg_speed = 0
                if #pData.stats.player_speed.ups_samples > 0 then
                    local sum = 0
                    for _, s in ipairs(pData.stats.player_speed.ups_samples) do sum = sum + s end
                    avg_speed = sum / #pData.stats.player_speed.ups_samples
                end

                DB.Execute(
                    "INSERT INTO round_player_stats (round_id, player_id, team, weapon_stats, stance_stats, player_speed, distance_travelled_meters, spawn_count, distance_travelled_spawn_avg) VALUES (?,?,?,?,?,?,?,?,?);",
                    {
                        State.currentRoundId, pData.db_id, pData.team,
                        json.encode(pData.stats.weaponStats),
                        json.encode(pData.stats.stance_stats),
                        json.encode({ ups_avg = avg_speed, ups_peak = pData.stats.player_speed.peak_speed_ups }),
                        pData.stats.distance_travelled_meters,
                        pData.stats.spawn_count,
                        (pData.stats.spawn_count > 0 and pData.stats.distance_travelled_spawn / pData.stats.spawn_count or 0)
                    }
                )
            end
        end

        for _, obit in ipairs(State.obituaries) do
            local attacker_id = (State.players[obit.attacker] and State.players[obit.attacker].db_id) or nil
            local target_id = (State.players[obit.target] and State.players[obit.target].db_id) or nil
            DB.Execute("INSERT INTO obituaries (round_id, timestamp, attacker_id, target_id, means_of_death) VALUES (?,?,?,?,?);",
                {State.currentRoundId, obit.timestamp, attacker_id, target_id, obit.meansOfDeath})
        end
        
        -- Implement saving for other event tables here...

        DB.Execute("COMMIT;")
        et.G_Print("Round stats saved successfully.\n")
    end)

    if not success then
        et.G_Print("^1CRITICAL: FAILED TO SAVE STATS! Rolling back transaction. Error: ".. tostring(err).. "^7\n")
        DB.Execute("ROLLBACK;")
    end
end

-- ===================================================================
-- Stat Collection Logic (from user script)
-- ===================================================================
local function calculateDistance3D(pos1, pos2)
    if not pos1 or not pos2 then return 0 end
    local dx, dy, dz = pos1[2] - pos2[2], pos1[3] - pos2[3], pos1[4] - pos2[4]
    return math.sqrt(dx*dx + dy*dy + dz*dz) / 39.37 -- Convert to meters
end

local function trackPlayerStanceAndMovement(levelTime)
    local frameDelta = levelTime - State.lastFrameTime
    if frameDelta <= 0 then return end

    for clientNum, pData in pairs(State.players) do
        if pData and et.gentity_get(clientNum, "pers.connected") == 2 then
            local health = et.gentity_get(clientNum, "health") or 0
            local eFlags = et.gentity_get(clientNum, "ps.eFlags") or 0
            
            if health > 0 then
                local timeDelta = (levelTime - (pData.stats.last_stance_check or levelTime)) / 1000
                if timeDelta > 0 then
                    if (eFlags & 0x00080000) ~= 0 or (eFlags & 0x00100000) ~= 0 then pData.stats.stance_stats.in_prone = pData.stats.stance_stats.in_prone + timeDelta end
                    if (eFlags & 0x00000010) ~= 0 then pData.stats.stance_stats.in_crouch = pData.stats.stance_stats.in_crouch + timeDelta end
                    -- Add other stance checks here...
                end
                pData.stats.last_stance_check = levelTime

                local currentPos = et.gentity_get(clientNum, "ps.origin")
                if currentPos and pData.stats.last_position then
                    pData.stats.distance_travelled_meters = pData.stats.distance_travelled_meters + calculateDistance3D(pData.stats.last_position, currentPos)
                end
                pData.stats.last_position = currentPos

                local velocity = et.gentity_get(clientNum, "ps.velocity")
                if velocity then
                    local speed = math.sqrt(velocity[2]^2 + velocity[3]^2 + velocity[4]^2)
                    if speed > 10 then table.insert(pData.stats.player_speed.ups_samples, speed) end
                    if speed > pData.stats.player_speed.peak_speed_ups then pData.stats.player_speed.peak_speed_ups = speed end
                end
            end
        end
    end
    State.lastFrameTime = levelTime
end

-- ===================================================================
-- ET:Legacy Engine Callbacks
-- ===================================================================

function et_InitGame(levelTime, randomSeed, restart)
    et.RegisterModname(string.format("%s %s", modname, version))
    resetState()
    State.lastFrameTime = levelTime

    if DB.Connect(State.DB_FILE) then
        Schema.Initialize()
    else
        et.G_Print("^1CRITICAL: Stats system failed to connect to database. Stats will not be saved.^7\n")
        return
    end

    State.currentMatchId = et.trap_Cvar_Get("g_match_id") or ("M".. os.time().. math.random(100, 999))
    local mapname = et.trap_Cvar_Get("mapname")
    local roundNum = (tonumber(et.trap_Cvar_Get("g_currentRound")) or 0) + 1

    DB.Execute("INSERT OR IGNORE INTO matches (id, start_time) VALUES (?,?);", {State.currentMatchId, os.time()})
    DB.Execute("INSERT INTO rounds (match_id, map_name, round_num, start_time) VALUES (?,?,?,?);",
        {State.currentMatchId, mapname, roundNum, levelTime})
    State.currentRoundId = DB.LastInsertRowId()

    et.G_Print(string.format("Stats tracker initialized. Match ID: %s, Round ID: %d\n", State.currentMatchId, State.currentRoundId))
end

function et_ShutdownGame(restart)
    et.G_Print("Map shutting down. Performing final stats flush...\n")
    
    if State.currentRoundId then
        local winnerTeam = tonumber(et.Info_ValueForKey(et.trap_GetConfigstring(et.CS_MULTI_MAPWINNER), "w"))
        DB.Execute("UPDATE rounds SET end_time =?, winner_team =? WHERE id =?;", {et.trap_Cvar_Get("level.time"), winnerTeam, State.currentRoundId})
    end

    saveRoundStats()
    DB.Disconnect()
end

function et_RunFrame(levelTime)
    trackPlayerStanceAndMovement(levelTime)
end

function et_ClientBegin(clientNum)
    loadOrCreatePlayer(clientNum)
end

function et_ClientDisconnect(clientNum)
    State.players[clientNum] = nil
end

function et_Obituary(victimNum, killerNum, meansOfDeath)
    local victim = State.players[victimNum]
    if victim then victim.stats.deaths = (victim.stats.deaths or 0) + 1 end

    if killerNum < et.MAX_CLIENTS and killerNum ~= victimNum then
        local killer = State.players[killerNum]
        if killer then killer.stats.kills = (killer.stats.kills or 0) + 1 end
    end

    table.insert(State.obituaries, {
        timestamp = et.trap_Cvar_Get("level.time"),
        target = victimNum,
        attacker = killerNum,
        meansOfDeath = meansOfDeath
    })
end