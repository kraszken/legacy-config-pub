local modname = "game-stats-json"
local version = "1.0.0"

-- Required libraries
local json = require("dkjson")
local toml = require("toml")

-- Default configuration
local configuration = {
    json_output_enabled = true,
    json_output_directory = "json_stats/",
    json_retention_days = 30,
    log_filepath = "log_filepath",
    logging_enabled = true,
    collect_damageStats = true,
    collect_messages = true,
    collect_objstats = true,
    collect_obituaries = true,
    collect_shovestats = true,
    collect_movement_stats = true,
    collect_stance_stats = true,
    force_names = true
}

-- config.toml
local function get_config_path()
    local fs_basepath = et.trap_Cvar_Get("fs_basepath")
    local fs_game = et.trap_Cvar_Get("fs_game")
    
    if not fs_basepath or not fs_game then
        et.G_Print(string.format("%s: Failed to get game paths\n", modname))
        return nil
    end
    
    return string.format("%s/%s/luascripts/config.toml", fs_basepath, fs_game)
end

local function load_config(filepath)
    if not filepath then
        et.G_Print(string.format("%s: Invalid config file path\n", modname))
        return nil
    end

    -- Check if file exists and can be opened
    local exists = io.open(filepath)
    if not exists then
        et.G_Print(string.format("%s: Config file not found: %s\n", modname, filepath))
        return nil
    end
    exists:close()
    
    -- Read file
    local file, err = io.open(filepath, "r")
    if not file then
        et.G_Print(string.format("%s: Failed to open config file: %s\n", modname, err))
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        et.G_Print(string.format("%s: Config file is empty\n", modname))
        return nil
    end
    
    -- Parse TOML
    local success, result = pcall(toml.parse, content)
    if not success then
        local error_msg = result
        local line_number = string.match(result, ":(%d+):")
        if line_number then
            error_msg = string.format("Parse error near line %s: %s", line_number, result)
        end
        et.G_Print(string.format("%s: %s\n", modname, error_msg))
        return nil
    end
    
    return result
end

local function normalize_key(key)
    if type(key) ~= "string" then
        return tostring(key):lower()
    end
    return string.lower(key)
end

function isEmpty(str)
	if str == nil or str == '' then
		return 0
	end
	return str
end

local function table_count(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function process_config(config)
    local normalized = {}
    local maps_section
    
    maps_section = config.maps

    -- Ensure we have a maps table
    if not maps_section then
        return {}
    end
    
    for map_name, map_data in pairs(maps_section) do
        normalized[normalize_key(map_name)] = {
            objectives = {},
            buildables = {},
            flags = {},
            misc = {},
            escort = {}
        }
        
        -- Process objectives
        if map_data.objectives then
            for obj_name, obj_data in pairs(map_data.objectives) do
                table.insert(normalized[normalize_key(map_name)].objectives, {
                    name = normalize_key(obj_name),
                    steal_pattern = normalize_key(obj_data.steal_pattern),
                    secured_pattern = normalize_key(obj_data.secured_pattern),
                    return_pattern = normalize_key(obj_data.return_pattern)
                })
            end
        end
        
        -- Process buildables
        if map_data.buildables then
            for build_name, build_data in pairs(map_data.buildables) do
                if build_data.enabled ~= nil then
                    normalized[normalize_key(map_name)].buildables[normalize_key(build_name)] = {
                        enabled = build_data.enabled
                    }
                else
                    normalized[normalize_key(map_name)].buildables[normalize_key(build_name)] = {
                        construct_pattern = normalize_key(build_data.construct_pattern or ""),
                        destruct_pattern = normalize_key(build_data.destruct_pattern or ""),
                        plant_pattern = normalize_key(build_data.plant_pattern or "")
                    }
                end
            end
        end

        -- Process flags configurations
        if map_data.flags then
            for flag_name, flag_data in pairs(map_data.flags) do
                normalized[normalize_key(map_name)].flags[normalize_key(flag_name)] = {
                    flag_pattern = normalize_key(flag_data.flag_pattern),
                    flag_coordinates = flag_data.flag_coordinates
                }
            end
        end

        if map_data.misc then
            for misc_name, misc_data in pairs(map_data.misc) do
                normalized[normalize_key(map_name)].misc[normalize_key(misc_name)] = {
                    misc_pattern = normalize_key(misc_data.misc_pattern),
                    misc_coordinates = misc_data.misc_coordinates
                }
            end
        end

        if map_data.escort then
            for escort_name, escort_data in pairs(map_data.escort) do
                normalized[normalize_key(map_name)].escort[normalize_key(escort_name)] = {
                    escort_pattern = normalize_key(escort_data.escort_pattern),
                    escort_coordinates = escort_data.escort_coordinates
                }
            end
        end
    end
    return normalized
end

local function process_common_buildables(config)
    local buildables_section = config.common_buildables

    return buildables_section or {}
end

do
    local config_path = get_config_path()
    local config = load_config(config_path)

    if not config then
        et.G_Print(string.format("%s: Failed to load configuration file: %s\n", modname, config_path))
        return
    end

    -- Check which configuration to use based on docker_config flag
    local use_docker = config.docker_config or false
    local config_section = use_docker and config.docker_configuration or config.configuration

    if not config_section then
        et.G_Print(string.format("%s: No configuration section found\n", modname))
        return
    end

    -- Update configuration with values from TOML
    for key, value in pairs(config_section) do
        configuration[key] = value
    end

    -- Process map configs
    if config.maps then
        map_configs = process_config(config)
        if table_count(map_configs) == 0 then
            et.G_Print(string.format("%s: No valid map configurations found\n", modname))
        end
    else
        et.G_Print(string.format("%s: No maps section found in config\n", modname))
    end

    -- Process common buildables
    if config.common_buildables then
        common_buildables = process_common_buildables(config)
        if table_count(common_buildables) == 0 then
            et.G_Print(string.format("%s: No common buildables found\n", modname))
        end
    else
        et.G_Print(string.format("%s: No common buildables section found\n", modname))
    end
end

-- Server info
local server_ip
local server_port

-- MatchID cache
local cached_match_id = nil

-- local variables
local maxClients           = 20
local mapname              = ""

local stats                = {}
local messages             = {}
local obituaries           = {}
local damageStats          = {}
local hitRegionsStats      = {}
local objstats             = {}
local objective_carriers   = { players = {}, ids = {} }
local objective_states     = {}
local recent_announcements = {}
local announcements_buffer = 5
local repair_buffer        = 2000
local MAX_OBJ_DISTANCE     = 500

-- Round timing variables
local round_start_time     = 0
local round_end_time       = 0
local current_gamestate    = -1

local intermission         = false
local saveStatsState       = { inProgress = false }
local nextStoreTime        = 0
local scheduledSaveTime    = 0
local storeTimeInterval    = 5000
local saveStatsDelay       = 3000

local playerMovementStats = {}
local playerStanceStats = {}
local playerSpawnTracking = {}
local lastFrameTime = 0

local SPAWN_TRACK_DURATION = 3000
local SPAWN_DETECTION_THRESHOLD = 50

local team_names_cache = {
    alpha_teamname = nil,
    beta_teamname = nil,
    last_updated = 0
}

local TEAM_DATA_FILE = "team_data.json"
local TEAM_DATA_CHECK_INTERVAL = 5000
local team_data_file_path = nil
local last_name_check_time = 0
local rename_in_progress = {} 

-- Rename queue
local rename_queue = {}
local rename_timer = 0
local RENAME_DELAY = 150
local player_ready_status = {}

-- Name change tracking variables
local player_names_cache = {}
local name_enforcement_active = false

-- local constants
local CON_CONNECTED        = 2
local WS_KNIFE             = 0
local WS_MAX               = 28
local PERS_SCORE           = 0

-- Constants for hit regions
local HR_HEAD              = 0
local HR_ARMS              = 1
local HR_BODY              = 2
local HR_LEGS              = 3
local HR_NONE              = -1
local HR_TYPES = {HR_HEAD, HR_ARMS, HR_BODY, HR_LEGS}
local HR_NAMES = {
    [HR_HEAD] = "HR_HEAD",
    [HR_ARMS] = "HR_ARM",
    [HR_BODY] = "HR_BODY",
    [HR_LEGS] = "HR_LEG",
    [HR_NONE] = "HR_NONE"
}

local playerClassSwitches = {}
local CLASS_LOOKUP = {
    [0] = "soldier",
    [1] = "medic",
    [2] = "engineer",
    [3] = "fieldop",
    [4] = "covertops"
}

-- state flags
local EF_DEAD             = 0x00000001
local EF_CROUCHING        = 0x00000010
local EF_MG42_ACTIVE      = 0x00000020
local EF_MOUNTEDTANK      = 0x00008000
local EF_PRONE            = 0x00080000
local EF_PRONE_MOVING     = 0x00100000
local EF_TAGCONNECT       = 0x00008000
local EF_READY            = 0x00000008
local STAT_SPRINTTIME     = 8
local PW_REDFLAG          = 5
local PW_BLUEFLAG         = 6
local PW_OPS_DISGUISED    = 7
local BODY_DOWNED         = 67108864

local SPEED_US_TO_KPH = 15.58
local SPEED_US_TO_MPH = 23.44

local MAX_SPRINT_TIME     = 20000
local LOW_STAMINA_THRESHOLD = 100

-- Constants and variables for spawn time tracking
local MAX_REINFSEEDS = 8
local REINF_BLUEDELT = 3
local REINF_REDDELT  = 2
local levelTime      = 0
local aReinfOffset   = {}

-- Caching function references
local trap_GetUserinfo = et.trap_GetUserinfo
local Info_ValueForKey = et.Info_ValueForKey
local trap_Milliseconds = et.trap_Milliseconds
local gentity_get = et.gentity_get
local table_insert = table.insert

local team_data_cache = nil
local team_data_fetched = false

-- Logging function
local log = configuration.logging_enabled and function(message)
    if not configuration.log_filepath or configuration.log_filepath:match("^%%.*%%$") then
        return
    end

    local success, err = pcall(function()
        local file, open_err = io.open(configuration.log_filepath, "a")
        if not file then
            et.G_LogPrint(string.format("game-stats-json.lua: Failed to open log file: %s\n", open_err or "unknown error"))
            return
        end
        
        local write_success, write_err = pcall(function()
            local time = et.trap_Milliseconds()
            local ms = time % 1000
            file:write(string.format("[%s.%03d] %s\n", os.date("%Y-%m-%d %H:%M:%S"), ms, message))
        end)
        
        file:close()
        
        if not write_success then
            et.G_LogPrint(string.format("game-stats-json.lua: Failed to write to log file: %s\n", write_err or "unknown error"))
        end
    end)
    
    if not success then
        et.G_LogPrint(string.format("game-stats-json.lua: Logging error: %s\n", err or "unknown error"))
    end
end or function() end

-- Utilities
function ConvertTimelimit(timelimit)
	local msec    = math.floor(tonumber(timelimit) * 60000)
	local seconds = math.floor(msec / 1000)
	local mins    = math.floor(seconds / 60)
	seconds       = math.floor(seconds - (mins * 60))
	local tens    = math.floor(seconds / 10)
	seconds       = math.floor(seconds - (tens * 10))
	
	return string.format("%i:%i%i", mins, tens, seconds)
end

local function calculateDistance3D(pos1, pos2)
    if not pos1 or not pos2 then return 0 end
    
    local ax, ay, az = pos1[1], pos1[2], pos1[3]
    local bx, by, bz = pos2[1], pos2[2], pos2[3]
    local dx = math.abs(bx - ax)
    local dy = math.abs(by - ay)
    local dz = math.abs(bz - az)
    local distance_units = math.sqrt((dx ^ 2) + (dy ^ 2) + (dz ^ 2))
    
    -- Convert game units to meters (1 meter ≈ 39.37 game units)
    return distance_units / 39.37
end

local function calculateVelocityMagnitude(velocity)
    if not velocity then return 0 end
    return math.sqrt(velocity[1]*velocity[1] + velocity[2]*velocity[2] + velocity[3]*velocity[3])
end

local function strip_colors(text)
    if not text then return "" end
    return string.gsub(text, "%^[%w]", "")
end

local function is_player_ready(clientNum)
    local eFlags = et.gentity_get(clientNum, "ps.eFlags")
    if not eFlags then
        return false
    end

    -- Check if EF_READY flag is set (bit 3 = 0x00000008)
    return (eFlags & EF_READY) ~= 0
end

local function getTeamDataFilePath()
    if team_data_file_path then
        return team_data_file_path
    end
    
    local fs_basepath = et.trap_Cvar_Get("fs_basepath")
    local fs_game = et.trap_Cvar_Get("fs_game")
    
    if not fs_basepath or not fs_game then
        log("Failed to get game paths for team data file")
        return nil
    end
    
    team_data_file_path = string.format("%s/%s/luascripts/%s", fs_basepath, fs_game, TEAM_DATA_FILE)
    return team_data_file_path
end

local function saveTeamDataToFile()
    if not team_data_cache then
        log("No team data to save")
        return false
    end

    local file_path = getTeamDataFilePath()
    if not file_path then
        log("Could not determine team data file path")
        return false
    end

    local team_data_json = {
        match_id = cached_match_id,
        alpha_teamname = team_names_cache.alpha_teamname,
        beta_teamname = team_names_cache.beta_teamname,
        match = team_data_cache,
        last_updated = trap_Milliseconds()
    }

    local json_str = json.encode(team_data_json)
    if not json_str then
        log("Failed to encode team data as JSON")
        return false
    end

    local success, err = pcall(function()
        local file, open_err = io.open(file_path, "w")
        if not file then
            error("Failed to open file: " .. (open_err or "unknown error"))
        end
        
        file:write(json_str)
        file:close()
    end)

    if success then
        log(string.format("Team data saved - Match ID: %s, Alpha: %s, Beta: %s", 
            cached_match_id or "nil",
            team_names_cache.alpha_teamname or "nil", 
            team_names_cache.beta_teamname or "nil"))
        return true
    else
        log(string.format("Failed to save team data: %s", err))
        return false
    end
end

local function loadTeamDataFromFile()
    local file_path = getTeamDataFilePath()
    if not file_path then
        log("Could not determine team data file path")
        return false
    end

    local file_check = io.open(file_path, "r")
    if not file_check then
        log("Team data file does not exist")
        return false
    end
    file_check:close()

    local success, result = pcall(function()
        local file = io.open(file_path, "r")
        if not file then
            return nil, "File not found"
        end

        local content = file:read("*all")
        file:close()

        if not content or content == "" then
            return nil, "Empty file"
        end

        local decoded = json.decode(content)
        if not decoded then
            return nil, "JSON decode failed"
        end

        return decoded
    end)

    if success and result then
        -- Load all data from file
        if result.match_id then
            cached_match_id = result.match_id
        end
        
        team_names_cache.alpha_teamname = result.alpha_teamname
        team_names_cache.beta_teamname = result.beta_teamname
        team_names_cache.last_updated = result.last_updated or 0
        team_data_cache = result.match 
        team_data_fetched = true

        log(string.format("Data loaded from file - Match ID: %s, Alpha: %s, Beta: %s", 
            cached_match_id or "nil",
            team_names_cache.alpha_teamname or "nil", 
            team_names_cache.beta_teamname or "nil"))
        return true
    else
        log(string.format("Failed to load team data from file: %s", result or "unknown error"))
        return false
    end
end

local function wipeTeamDataFile()
    local file_path = getTeamDataFilePath()
    if not file_path then
        return false
    end

    local success, err = pcall(function()
        os.remove(file_path)
    end)

    if success then
        log("Team data file wiped")
        return true
    else
        log(string.format("Failed to wipe team data file: %s", err or "unknown error"))
        return false
    end
end

local function queuePlayerRename(clientNum, newName, reason)
    table.insert(rename_queue, {
        clientNum = clientNum,
        newName = newName,
        reason = reason,
        timestamp = trap_Milliseconds()
    })
    
    log(string.format("Queued rename for player %d: %s (reason: %s)", 
        clientNum, newName, reason))
end

local function renamePlayer(clientNum, newName)
    local clientInfo = trap_GetUserinfo(clientNum)
    clientInfo = et.Info_SetValueForKey(clientInfo, "name", newName)
    et.trap_SetUserinfo(clientNum, clientInfo)
    et.ClientUserinfoChanged(clientNum)
end

local function processRenameQueue(currentTime)
    if #rename_queue == 0 then return end
    
    if currentTime < rename_timer then return end

    local rename_data = table.remove(rename_queue, 1)
    if rename_data then
        if et.gentity_get(rename_data.clientNum, "pers.connected") == CON_CONNECTED then
            renamePlayer(rename_data.clientNum, rename_data.newName)
            log(string.format("Processed rename: Player %d -> %s (%s)", 
                rename_data.clientNum, rename_data.newName, rename_data.reason))
        else
            log(string.format("Skipped rename for disconnected player %d", rename_data.clientNum))
        end

        rename_timer = currentTime + RENAME_DELAY
    end
end

-- Fetch and add GUID+team to cache
local clientGuids = setmetatable({}, {
    __index = function(t, clientNum)
        -- Validate client number
        if not clientNum or type(clientNum) ~= "number" then
            return { guid = "WORLD", team = 0 }
        end

        -- Fetch guid and team if not in table
        if clientNum >= 0 and clientNum < maxClients then
            local userinfo = trap_GetUserinfo(clientNum)
            if userinfo and userinfo ~= "" then
                local guid = string.upper(Info_ValueForKey(userinfo, "cl_guid"))
                local sessionTeam = tonumber(et.gentity_get(clientNum, "sess.sessionTeam")) or 0
                if guid and guid ~= "" then
                    t[clientNum] = { guid = guid, team = sessionTeam }
                    return t[clientNum]
                end
            end
        end

        return { guid = "WORLD", team = 0 }
    end
})

local function findPlayerNameByGuid(guid)
    if not team_data_cache then
        return nil
    end

    -- Search both teams
    for _, team_name in pairs({"alpha_team", "beta_team"}) do
        local team = team_data_cache[team_name]
        if team then
            for _, player in ipairs(team) do
                if player.GUID then
                    for _, player_guid in ipairs(player.GUID) do
                        if string.upper(player_guid) == string.upper(guid) then
                            return player.name
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

function et_ClientDisconnect(clientNum)
    local guid = clientGuids[clientNum]
    if guid and guid.guid ~= "WORLD" then
        playerMovementStats[guid.guid] = nil
        playerStanceStats[guid.guid] = nil
    end
    clientGuids[clientNum] = nil
    player_ready_status[clientNum] = nil
    rename_in_progress[clientNum] = nil
end

local function enforcePlayerName(clientNum)
    if not configuration.force_names then return end
    if not team_data_cache or not team_names_cache.alpha_teamname or not team_names_cache.beta_teamname then return end
    if rename_in_progress[clientNum] then return end

    local userinfo = trap_GetUserinfo(clientNum)
    if not userinfo or userinfo == "" then return end

    local guid = string.upper(Info_ValueForKey(userinfo, "cl_guid"))
    local current_name = Info_ValueForKey(userinfo, "name")
    if not guid or guid == "" or not current_name then return end

    local correct_name = findPlayerNameByGuid(guid)
    if not correct_name then return end

    if strip_colors(current_name):lower() ~= strip_colors(correct_name):lower() then
        local trimmed = correct_name
        if #trimmed > 35 then
            trimmed = trimmed:sub(1, 35)
        end
        log(string.format("Enforcing name for %d: '%s' -> '%s'", clientNum, current_name, trimmed))
        rename_in_progress[clientNum] = true
        renamePlayer(clientNum, trimmed)
    end
end

local function getFirstColorCode(name)
    local code = string.match(name, "(%^%w)")
    return code
end

local function checkAllPlayersNamesGameplay(currentTime)
    if not configuration.force_names then
        return
    end

    if currentTime < last_name_check_time + TEAM_DATA_CHECK_INTERVAL then
        return
    end

    last_name_check_time = currentTime

    if not team_data_cache or not team_names_cache.alpha_teamname or not team_names_cache.beta_teamname then
        return
    end

    for clientNum = 0, maxClients - 1 do
        if et.gentity_get(clientNum, "pers.connected") == CON_CONNECTED and not rename_in_progress[clientNum] then
            local sessionTeam = tonumber(et.gentity_get(clientNum, "sess.sessionTeam")) or 0
            if sessionTeam == 1 or sessionTeam == 2 then
                enforcePlayerName(clientNum)
            end
        end
    end
end

local function validateAllPlayerNames()
    if not configuration.force_names then return end
    if not team_data_cache or not team_names_cache.alpha_teamname or not team_names_cache.beta_teamname then
        log("Team data not available, skipping mass validation")
        return
    end

    log("Performing mass validation check on all connected players")

    local spectator_teamname = team_data_cache.spectator_teamname

    for clientNum = 0, maxClients - 1 do
        if et.gentity_get(clientNum, "pers.connected") == CON_CONNECTED then
            local userinfo = trap_GetUserinfo(clientNum)
            if userinfo and userinfo ~= "" then
                local sessionTeam = tonumber(et.gentity_get(clientNum, "sess.sessionTeam")) or 0
                if sessionTeam == 1 or sessionTeam == 2 then
                    enforcePlayerName(clientNum)
                end
            end
        end
    end
end

local function checkPlayerReadyStatus()
    if not configuration.force_names then
        return
    end

    for clientNum = 0, maxClients - 1 do
        if et.gentity_get(clientNum, "pers.connected") == CON_CONNECTED then
            local is_ready = is_player_ready(clientNum)
            local was_ready = player_ready_status[clientNum]

            if is_ready and not was_ready then
                log(string.format("Player %d readied up", clientNum))

                if not team_data_cache or not team_names_cache.alpha_teamname or not team_names_cache.beta_teamname then
                    log("First ready detected, fetching team data")
                    -- Don't fetch from API in JSON version
                end

                enforcePlayerName(clientNum)
            end

            player_ready_status[clientNum] = is_ready
        end
    end
end

local function initializePlayerTracking(clientNum)
    local guid = clientGuids[clientNum]
    if not guid or guid.guid == "WORLD" then return end

    local team = guid.team or tonumber(et.gentity_get(clientNum, "sess.sessionTeam")) or 0
    if team ~= et.TEAM_AXIS and team ~= et.TEAM_ALLIES then 
        return
    end
    
    if not playerMovementStats[guid.guid] then
        playerMovementStats[guid.guid] = {
            distance_travelled = 0,
            last_position = nil,
            distance_travelled_spawn = 0,
            spawn_count = 0,
            speed_samples = {},
            peak_speed_ups = 0,
            total_speed_samples = 0,
            total_speed_sum = 0
        }
    end
    
    if not playerStanceStats[guid.guid] then
        playerStanceStats[guid.guid] = {
            in_prone = 0,
            in_crouch = 0,
            in_mg = 0,
            in_lean = 0,
            in_objcarrier = 0,      
            in_vehiclescort = 0,    
            in_disguise = 0,        
            in_sprint = 0,          
            in_turtle = 0,          
            is_downed = 0,
            last_stance_check = 0,
            last_sprint_time = MAX_SPRINT_TIME
        }
    end

    if not playerSpawnTracking[guid.guid] then
        playerSpawnTracking[guid.guid] = {
            tracking_active = false,
            tracking_end_time = 0,
            spawn_position = nil,
            distance_travelled = 0,
            last_detected_spawn_time = 0
        }
    end
end

local function trackPlayerStanceAndMovement(gameFrameLevelTime)
    local frameTime = gameFrameLevelTime - lastFrameTime
    if frameTime <= 0 then return end

    for guid, spawnTrack in pairs(playerSpawnTracking) do
        if spawnTrack.tracking_active and gameFrameLevelTime >= spawnTrack.tracking_end_time then
            spawnTrack.tracking_active = false

            if playerMovementStats[guid] then
                playerMovementStats[guid].distance_travelled_spawn = 
                    playerMovementStats[guid].distance_travelled_spawn + spawnTrack.distance_travelled
            end
        end
    end

    for clientNum = 0, maxClients - 1 do
        if et.gentity_get(clientNum, "pers.connected") == CON_CONNECTED then
            local guid = clientGuids[clientNum]
            if guid and guid.guid ~= "WORLD" then
                -- player is on an active team
                local team = guid.team or tonumber(et.gentity_get(clientNum, "sess.sessionTeam")) or 0
                if team == et.TEAM_AXIS or team == et.TEAM_ALLIES then
                    initializePlayerTracking(clientNum)

                    local health = tonumber(et.gentity_get(clientNum, "health")) or 0
                    local eFlags = tonumber(et.gentity_get(clientNum, "ps.eFlags")) or 0
                    local body = tonumber(et.gentity_get(clientNum, "r.contents")) or 0

                    local isDead = (eFlags & EF_DEAD) ~= 0
                    local isDowned = (health < 0 and body == BODY_DOWNED)
                    local isAlive = health > 0
                    local isNotDowned = not isDowned

                    -- Track stance stats for all players
                    local stanceStats = playerStanceStats[guid.guid]
                    if stanceStats then
                        local currentTime = gameFrameLevelTime
                        local timeDelta = currentTime - (stanceStats.last_stance_check or currentTime)
                        
                        if isAlive and isNotDowned then
                            local sprintTime = tonumber(et.gentity_get(clientNum, "ps.stats", 8)) or MAX_SPRINT_TIME
                            local lastSpawnTime = tonumber(et.gentity_get(clientNum, "pers.lastSpawnTime")) or 0
                            local spawnTrack = playerSpawnTracking[guid.guid]

                            if lastSpawnTime > 0 and 
                            (currentTime - lastSpawnTime) < SPAWN_DETECTION_THRESHOLD and
                            (not spawnTrack.last_detected_spawn_time or lastSpawnTime > spawnTrack.last_detected_spawn_time) then

                                local currentPos = et.gentity_get(clientNum, "ps.origin")
                                if currentPos then
                                    spawnTrack.tracking_active = true
                                    spawnTrack.tracking_end_time = currentTime + SPAWN_TRACK_DURATION
                                    spawnTrack.spawn_position = {currentPos[1], currentPos[2], currentPos[3]}
                                    spawnTrack.last_detected_spawn_time = lastSpawnTime
                                    spawnTrack.distance_travelled = 0
                                    playerMovementStats[guid.guid].spawn_count = (playerMovementStats[guid.guid].spawn_count or 0) + 1
                                end
                            end

                            if timeDelta > 0 then
                                local isCrouching = (eFlags & EF_CROUCHING) ~= 0
                                local isProne = (eFlags & EF_PRONE_MOVING) ~= 0 or (eFlags & EF_PRONE) ~= 0
                                local isMounted = (eFlags & EF_MG42_ACTIVE) ~= 0 or (eFlags & EF_MOUNTEDTANK) ~= 0
                                local weapon = tonumber(et.gentity_get(clientNum, "ps.weapon")) or 0
                                if weapon == 47 or weapon == 50 then  -- WP_MOBILE_MG42_SET = 47, WP_MOBILE_BROWNING_SET = 50
                                    isMounted = true
                                end

                                -- ps.leanf is non-zero when leaning
                                local leanf = tonumber(et.gentity_get(clientNum, "ps.leanf")) or 0
                                local isLeaning = leanf ~= 0

                                local isVehicleConnected = (eFlags & EF_TAGCONNECT) ~= 0

                                local isCarryingObj = false
                                local redFlagTime = tonumber(et.gentity_get(clientNum, "ps.powerups", PW_REDFLAG)) or 0
                                local blueFlagTime = tonumber(et.gentity_get(clientNum, "ps.powerups", PW_BLUEFLAG)) or 0
                                if redFlagTime > 0 or blueFlagTime > 0 then
                                    isCarryingObj = true
                                end

                                local disguiseTime = tonumber(et.gentity_get(clientNum, "ps.powerups", PW_OPS_DISGUISED)) or 0
                                local isDisguised = disguiseTime > 0

                                local lastSprintTime = stanceStats.last_sprint_time or MAX_SPRINT_TIME
                                local sprintDelta = lastSprintTime - sprintTime
                                local STAMINA_CHANGE_THRESHOLD = 50

                                local isSprinting = sprintDelta > STAMINA_CHANGE_THRESHOLD
                                local isTurtle = (sprintTime == 0) or 
                                                (sprintTime == MAX_SPRINT_TIME) or 
                                                (sprintDelta < -STAMINA_CHANGE_THRESHOLD)

                                if isProne then
                                    stanceStats.in_prone = stanceStats.in_prone + (timeDelta / 1000)
                                end

                                if isMounted then
                                    stanceStats.in_mg = stanceStats.in_mg + (timeDelta / 1000)
                                end

                                if isCrouching and not isProne and not isMounted then
                                    stanceStats.in_crouch = stanceStats.in_crouch + (timeDelta / 1000)
                                end

                                if isLeaning and not isProne and not isMounted then
                                    stanceStats.in_lean = stanceStats.in_lean + (timeDelta / 1000)
                                end

                                if isCarryingObj then
                                    stanceStats.in_objcarrier = stanceStats.in_objcarrier + (timeDelta / 1000)
                                end

                                if isVehicleConnected then
                                    stanceStats.in_vehiclescort = stanceStats.in_vehiclescort + (timeDelta / 1000)
                                end

                                if isDisguised then
                                    stanceStats.in_disguise = stanceStats.in_disguise + (timeDelta / 1000)
                                end

                                if isSprinting then
                                    stanceStats.in_sprint = stanceStats.in_sprint + (timeDelta / 1000)
                                end

                                if isTurtle then
                                    stanceStats.in_turtle = stanceStats.in_turtle + (timeDelta / 1000)
                                end

                                stanceStats.last_sprint_time = sprintTime
                                stanceStats.last_stance_check = currentTime
                            end

                            -- Track distance travelled and speed
                            local movementStats = playerMovementStats[guid.guid]
                            if movementStats then
                                local currentPos = et.gentity_get(clientNum, "ps.origin")
                                local velocity = et.gentity_get(clientNum, "ps.velocity")
                                
                                if velocity then
                                    local speed_ups = math.sqrt(velocity[1]*velocity[1] + velocity[2]*velocity[2] + velocity[3]*velocity[3])

                                    if speed_ups > movementStats.peak_speed_ups then
                                        movementStats.peak_speed_ups = speed_ups
                                    end
                                    
                                    if speed_ups > 10 then
                                        movementStats.total_speed_samples = movementStats.total_speed_samples + 1
                                        movementStats.total_speed_sum = movementStats.total_speed_sum + speed_ups
                                    end
                                end

                                if currentPos and movementStats.last_position then
                                    local distance_meters = calculateDistance3D(movementStats.last_position, currentPos)
                                    if distance_meters > 0.025 then
                                        movementStats.distance_travelled = movementStats.distance_travelled + distance_meters

                                        if spawnTrack.tracking_active then
                                            spawnTrack.distance_travelled = spawnTrack.distance_travelled + distance_meters
                                        end
                                    end
                                end
                                movementStats.last_position = currentPos and {currentPos[1], currentPos[2], currentPos[3]} or nil
                            end

                        elseif isDowned then
                            if timeDelta > 0 then
                                stanceStats.is_downed = stanceStats.is_downed + (timeDelta / 1000)
                                stanceStats.last_stance_check = currentTime
                            end
                        end
                    end
                end
            end
        end
    end
    lastFrameTime = gameFrameLevelTime
end

-- Objective tracking utilities
local function match_any_pattern(text, patterns)
    if type(patterns) ~= "table" then 
        if type(patterns) == "string" then
            return string.find(normalize_key(text), normalize_key(patterns))
        end
        return false 
    end
    
    local normalized_text = normalize_key(text)
    for _, pattern in ipairs(patterns) do
        if string.find(normalized_text, normalize_key(pattern)) then
            return true
        end
    end
    return false
end

local function contains(tbl, element)
    for _, value in pairs(tbl) do
        if value == element then
            return true
        end
    end
    return false
end

local function resetGameState()
    damageStats = {}
    obituaries = {}
    objstats = {}
    messages = {}
    playerClassSwitches = {}
    playerMovementStats = {}
    playerStanceStats = {}
    playerSpawnTracking = {}
    clientGuids = {}
    player_ready_status = {}
    player_names_cache = {}
    objective_carriers = { players = {}, ids = {} }
    objective_states = {}
    recent_announcements = {}
    round_start_time = 0
    round_end_time = 0
    saveStatsState.inProgress = false
    scheduledSaveTime = 0
    cached_match_id = nil
end

local function get_base_map_name(full_mapname)
    full_mapname = string.lower(full_mapname)
    
    -- Strip common prefixes
    local prefixes = {"etl_", "et_", "mp_", "sw_"}
    for _, prefix in ipairs(prefixes) do
        if string.sub(full_mapname, 1, string.len(prefix)) == prefix then
            full_mapname = string.sub(full_mapname, string.len(prefix) + 1)
            break
        end
    end
    
    -- Strip common suffixes
    local suffixes = {"_b%d+", "_v%d+", "_final", "_te", "_sw"}
    for _, suffix in ipairs(suffixes) do
        full_mapname = string.gsub(full_mapname, suffix .. "$", "")
    end
    
    return full_mapname
end

function parseReinforcementTimes()
    local reinfSeedString = et.trap_GetConfigstring(et.CS_REINFSEEDS)
    local reinfSeeds = {}
    local aReinfSeeds = { 11, 3, 13, 7, 2, 5, 1, 17 }
    for seed in string.gmatch(reinfSeedString, "%d+") do
        table.insert(reinfSeeds, tonumber(seed))
    end

    local offsets = {}
    offsets[et.TEAM_ALLIES] = reinfSeeds[1] >> REINF_BLUEDELT
    offsets[et.TEAM_AXIS]   = math.floor(reinfSeeds[2] / (1 << REINF_REDDELT))

    for i = et.TEAM_AXIS, et.TEAM_ALLIES do
        for j = 1, MAX_REINFSEEDS do
            if (j-1) == offsets[i] then
                aReinfOffset[i] = math.floor(reinfSeeds[j + 2] / aReinfSeeds[j])
                aReinfOffset[i] = aReinfOffset[i] * 1000
                break
            end
        end
    end
end

function calculateReinfTime(team)
    -- if game is paused then that CS is being updated every 500ms
    local levelStartTime = et.trap_GetConfigstring(et.CS_LEVEL_START_TIME)
    local dwDeployTime

    if team == et.TEAM_AXIS then
        dwDeployTime = tonumber(et.trap_Cvar_Get("g_redlimbotime"))
    elseif team == et.TEAM_ALLIES then
        dwDeployTime = tonumber(et.trap_Cvar_Get("g_bluelimbotime"))
    else
        return
    end
    return (dwDeployTime - ((aReinfOffset[team] + levelTime - levelStartTime) % dwDeployTime)) * 0.001
end

function et_ClientUserinfoChanged(clientNum)
    local userinfo = trap_GetUserinfo(clientNum)
    if userinfo and userinfo ~= "" then
        local guid = string.upper(Info_ValueForKey(userinfo, "cl_guid"))
        local sessionTeam = tonumber(et.gentity_get(clientNum, "sess.sessionTeam")) or 0

        if guid and guid ~= "" then
            clientGuids[clientNum] = { guid = guid, team = sessionTeam }

            if rename_in_progress[clientNum] then
                rename_in_progress[clientNum] = nil
                log(string.format("Rename completed for client %d", clientNum))
            else
                if current_gamestate == et.GS_PLAYING then
                    enforcePlayerName(clientNum)
                end
            end

            local playerType = tonumber(et.gentity_get(clientNum, "sess.playerType"))

            if playerType ~= nil and (sessionTeam == 1 or sessionTeam == 2) then
                if not playerClassSwitches[guid] then
                    playerClassSwitches[guid] = {}
                end

                local previousClass = nil
                if #playerClassSwitches[guid] > 0 then
                    previousClass = playerClassSwitches[guid][#playerClassSwitches[guid]].toClass
                end

                if previousClass ~= playerType then
                    table.insert(playerClassSwitches[guid], {
                        timestamp = trap_Milliseconds(),
                        fromClass = previousClass,
                        toClass = playerType
                    })

                    log(string.format("Player %s switched class from %s to %s", 
                        guid, 
                        previousClass and CLASS_LOOKUP[previousClass] or "none",
                        CLASS_LOOKUP[playerType] or "unknown"
                    ))
                end
            end
        end
    end
end

-- Objective state management
local function add_recent_announcement(text, timestamp)
    table.insert(recent_announcements, 1, {
        text = text,
        timestamp = timestamp
    })
    
    if #recent_announcements > announcements_buffer then
        table.remove(recent_announcements)
    end
end

local function record_obj_stat(guid, event_type, objective, timestamp, killer_info)
    if not guid then
        log("Missing GUID in record_obj_stat")
        return
    end

    if not event_type then
        log("Missing event_type in record_obj_stat")
        return
    end

    -- Initialize objstat entry if needed
    if not objstats[guid] then
        objstats[guid] = {
            obj_planted = {},
            obj_destroyed = {},
            obj_taken = {},
            obj_returned = {},
            obj_secured = {},
            obj_repaired = {},
            obj_defused = {},
            obj_carrierkilled = {},
            obj_flagcaptured = {},
            obj_misc = {},
            obj_escort = {},
            shoves_given = {},
            shoves_received = {}
        }
    end
    
    -- Handle carrier killed events differently
    if event_type == "obj_carrierkilled" and killer_info then
        objstats[guid][event_type][timestamp] = {
            victim = killer_info.guid,
            weapon = killer_info.weapon,
            objective = killer_info.objective
        }
    else
        objstats[guid][event_type][timestamp] = objective or "unknown"
    end
    
    log(string.format("Recorded objective event - GUID: %s, Event: %s, Objective: %s", 
        guid,
        event_type,
        objective or "unknown"
    ))
end

local function update_objective_state(obj_name, action, guid, normalized_text)
    objective_states[obj_name] = objective_states[obj_name] or {
        last_popup = "",
        last_announce = "",
        last_action = "",
        timestamp = 0
    }
    
    local timestamp = trap_Milliseconds()
    objective_states[obj_name].timestamp = timestamp
    objective_states[obj_name].last_action = action
    
    if normalized_text then
        objective_states[obj_name].last_announce = normalized_text
    end
    
    if guid and action == "planted" then
        objective_states[obj_name].planter_guid = guid.guid
    end

    return timestamp
end

-- Get list of covies
local function get_active_covert_ops()
    local COVERT_OPS = 4
    local AXIS = 1
    local ALLIES = 2
    local covert_ops_clients = {}

    for clientNum = 0, maxClients - 1 do
        local client = clientGuids[clientNum]
        if client then
            local sessionTeam = client.team
            local playerType = tonumber(et.gentity_get(clientNum, "sess.playerType"))

            if (sessionTeam == AXIS or sessionTeam == ALLIES) and playerType == COVERT_OPS then
                table.insert(covert_ops_clients, clientNum)
                log(string.format("Found covert ops: Player %d (GUID: %s)", clientNum, client.guid))
            end
        end
    end    
    return covert_ops_clients
end

local function handle_destroyer_attribution(obj_name)
    local destroyer_guid, valid_destroyer_found = nil, false

    -- Check for planter first
    if objective_states[obj_name] and 
       objective_states[obj_name].planter_guid then
        destroyer_guid = objective_states[obj_name].planter_guid
        valid_destroyer_found = true
        log(string.format("Destroy: %s attributed to planter: %s", obj_name, destroyer_guid))

    -- Try to attribute to covert ops
    else
        local covert_ops = get_active_covert_ops()
        if #covert_ops == 1 then
            destroyer_guid = clientGuids[covert_ops[1]].guid
            valid_destroyer_found = true
            log(string.format("%s destroyed by covert: %s", obj_name, destroyer_guid))
        elseif #covert_ops > 1 then
            log(string.format("%s: multiple coverts active", obj_name))
        end
    end

    return destroyer_guid, valid_destroyer_found
end

local function handle_buildable_destruction(obj_name, normalized_text)       
    local destroyer_guid, valid_destroyer_found = handle_destroyer_attribution(obj_name)
    
    if valid_destroyer_found and destroyer_guid then
        record_obj_stat(destroyer_guid, "obj_destroyed", obj_name, trap_Milliseconds())
        log(string.format("Destruction: %s by %s", obj_name, destroyer_guid))
    end

    update_objective_state(obj_name, "destroyed", nil, normalized_text)
end

local function check_recent_construction(obj_name, patterns, obj_config, current_time)
    -- Validate buildable configuration
    if not obj_config then
        return false
    end

    -- Check both current state and recent announcements
    local matched = false

    -- First check current state
    if objective_states[obj_name] and 
       objective_states[obj_name].last_announce and
       (current_time - objective_states[obj_name].timestamp) < repair_buffer then

        local last_announce = objective_states[obj_name].last_announce

        -- Handle map-specific buildables
        if type(obj_config) == "table" and obj_config.construct_pattern then
            matched = string.match(normalize_key(last_announce), normalize_key(obj_config.construct_pattern)) ~= nil
            log(string.format("Map-specific pattern check for %s: '%s' against '%s' = %s", 
                obj_name,
                normalize_key(last_announce),
                normalize_key(obj_config.construct_pattern),
                tostring(matched)))

        -- Handle common buildables
        elseif type(obj_config) == "table" and obj_config.enabled then
            if type(patterns) == "table" and patterns.construct then
                matched = match_any_pattern(last_announce, patterns.construct)
            end
        end
    end

    -- If no match in current state, check recent announcements
    if not matched then
        for _, announcement in ipairs(recent_announcements) do
            if (current_time - announcement.timestamp) < repair_buffer then
                -- Handle common buildables
                if type(obj_config) == "table" and obj_config.enabled then
                    if type(patterns) == "table" and patterns.construct then
                        matched = match_any_pattern(announcement.text, patterns.construct)
                    end

                -- Handle map-specific buildables
                elseif type(obj_config) == "table" and obj_config.construct_pattern then
                    matched = string.find(normalize_key(announcement.text), normalize_key(obj_config.construct_pattern)) ~= nil
                end

                if matched then
                    update_objective_state(obj_name, "constructed", nil, announcement.text)
                    break
                end
            end
        end
    end

    return matched
end

-- clear previous objective entries
local function clear_previous_objective_entries(guid, objective_name, timestamp)
    if not objstats[guid] then return end
    
    local new_taken = {}
    for entry_timestamp, obj in pairs(objstats[guid].obj_taken or {}) do
        if obj ~= objective_name or entry_timestamp >= timestamp then
            new_taken[entry_timestamp] = obj
        end
    end
    
    if objstats[guid].obj_taken then
        objstats[guid].obj_taken = new_taken
    end
end

-- calculate distance between two 3D points
local function calculate_distance(point1, point2)
    local x1, y1, z1 = point1[1], point1[2], point1[3]
    local x2, y2, z2 = point2[1], point2[2], point2[3]
    return math.sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2)
end

local function getEntityCoordinates(entityId)
    if not entityId then return nil end
    
    local origin = et.gentity_get(entityId, "origin")
    if not origin then return nil end
    
    -- Format coordinates as string
    return string.format("%d %d %d", origin[1], origin[2], origin[3])
end

-- Function to find and get flag coordinates
local function getFlagCoordinates()
    local flags = {}
    
    -- Scan through possible entity IDs
    for i = 64, 1021 do
        local classname = et.gentity_get(i, "classname")
        if classname == "team_WOLF_checkpoint" then
            local coords = getEntityCoordinates(i)
            if coords then
                -- Store coordinates for both teams since it's the same point
                flags["allies_flag"] = {
                    flag_pattern = "The Allies have captured the forward bunker!",
                    flag_coordinates = coords
                }
                flags["axis_flag"] = {
                    flag_pattern = "The Axis have captured the forward bunker!",
                    flag_coordinates = coords
                }
                break -- We found what we needed
            end
        end
    end
    
    return flags
end

-- parse coordinates string into a table
local function parse_coordinates(coord_string)
    local x, y, z = coord_string:match("([%-%.%d]+)%s+([%-%.%d]+)%s+([%-%.%d]+)")
    return x and {tonumber(x), tonumber(y), tonumber(z)} or nil
end

-- find all players near obj coordinates
local function find_nearest_players(coordinates, team)
    local coord_table = parse_coordinates(coordinates)
    if not coord_table then 
        log("Failed to parse coordinates: " .. tostring(coordinates))
        return nil 
    end

    local nearest_players = {}
    local nearest_distance = math.huge

    for clientNum = 0, maxClients - 1 do
        local client = clientGuids[clientNum]
        if client and client.team == team then
            local health = tonumber(gentity_get(clientNum, "health"))
            local body = tonumber(gentity_get(clientNum, "r.contents"))
            
            if health > 0 or (health <= 0 and body == 67108864) then
                local origin = gentity_get(clientNum, "r.currentOrigin")
                if origin then
                    local distance = calculate_distance(coord_table, origin)
                
                    if distance <= MAX_OBJ_DISTANCE then
                        if distance < nearest_distance then
                            nearest_distance = distance
                            nearest_players = {clientNum}
                        elseif distance == nearest_distance then
                            table.insert(nearest_players, clientNum)
                        end
                    end
                end
            end
        end
    end

    if #nearest_players > 1 then
        local guids = {}
        for _, clientNum in ipairs(nearest_players) do
            table.insert(guids, clientGuids[clientNum].guid)
        end
        log(string.format("Multiple players at same distance: %s", table.concat(guids, ", ")))
    elseif #nearest_players == 0 then
        log("No players within range of objective")
    end

    return nearest_players
end

function et_Print(text)
    local map_config = map_configs[mapname]
    if not map_config then return end

    -- Handle Objective_Destroyed messages
    if string.find(text, "Objective_Destroyed:") then
        local id, obj_text = text:match("^Objective_Destroyed: (%d+) (.+)$")
        if id and obj_text then
            local normalized_text = normalize_key(obj_text:match("^%s*(.-)%s*$"))

            if map_config.buildables then
                for obj_name, obj_config in pairs(map_config.buildables) do
                    if type(obj_config) == "table" and 
                       obj_config.destruct_pattern and 
                       obj_config.destruct_pattern ~= "" and 
                       string.find(normalized_text, normalize_key(obj_config.destruct_pattern)) then
                        handle_buildable_destruction(obj_name, normalized_text)
                        break
                    end
                end
            end
        end
    end

    -- Handle announcements
    if string.find(text, "legacy announce:") then
        local clean_text = strip_colors(text:match("legacy announce: \"(.+)\""))
        local normalized_text = normalize_key(clean_text)
        local current_time = trap_Milliseconds()

        add_recent_announcement(normalized_text, current_time)

        -- Process common buildables
        for obj_name, common_config in pairs(common_buildables) do
            if map_config.buildables[obj_name] and 
               type(map_config.buildables[obj_name]) == "table" and 
               map_config.buildables[obj_name].enabled then

                if match_any_pattern(normalized_text, common_config.patterns.construct) then
                    update_objective_state(obj_name, "constructed", nil, normalized_text)
                    log(string.format("Construction: %s", obj_name))
                elseif match_any_pattern(normalized_text, common_config.patterns.destruct) then
                    handle_buildable_destruction(obj_name, normalized_text)
                end
            end
        end

        -- Process map-specific buildables
        if map_config.buildables then
            for obj_name, obj_config in pairs(map_config.buildables) do
                if type(obj_config) == "table" then
                    if obj_config.construct_pattern and 
                       obj_config.construct_pattern ~= "" and
                       string.find(normalized_text, normalize_key(obj_config.construct_pattern)) then
                        update_objective_state(obj_name, "constructed", nil, normalized_text)
                        log(string.format("Construction: %s", obj_name))
                    elseif obj_config.destruct_pattern and 
                           obj_config.destruct_pattern ~= "" and
                           string.find(normalized_text, normalize_key(obj_config.destruct_pattern)) then
                        if not (objective_states[obj_name] and 
                               objective_states[obj_name].last_action == "destroyed" and
                               (current_time - objective_states[obj_name].timestamp) < 1000) then
                            handle_buildable_destruction(obj_name, normalized_text)
                        end
                    end
                end
            end
        end
        
        -- Process flag captures
        if map_config.flags then
            -- Check Allies flag capture
            if map_config.flags.allies_flag and
               string.find(normalized_text, normalize_key(map_config.flags.allies_flag.flag_pattern)) then
                local nearest_allies = find_nearest_players(
                    map_config.flags.allies_flag.flag_coordinates,
                    2  -- For Allies
                )
                if nearest_allies and #nearest_allies > 0 then
                    for _, clientNum in ipairs(nearest_allies) do
                        local guid = clientGuids[clientNum].guid
                        record_obj_stat(guid, "obj_flagcaptured", "allies_flag", current_time)
                        log(string.format("Allies flag capture attributed to: %s", guid))
                    end
                end
            end
        
            -- Check Axis flag capture
            if map_config.flags.axis_flag and
               string.find(normalized_text, normalize_key(map_config.flags.axis_flag.flag_pattern)) then
                local nearest_axis = find_nearest_players(
                    map_config.flags.axis_flag.flag_coordinates,
                    1  -- For Axis
                )
                if nearest_axis and #nearest_axis > 0 then
                    for _, clientNum in ipairs(nearest_axis) do
                        local guid = clientGuids[clientNum].guid
                        record_obj_stat(guid, "obj_flagcaptured", "axis_flag", current_time)
                        log(string.format("Axis flag capture attributed to: %s", guid))
                    end
                end
            end
        end

        if map_config.misc then
            for misc_name, misc_data in pairs(map_config.misc) do
                if string.find(normalized_text, normalize_key(misc_data.misc_pattern)) then
                    local nearest_allies = find_nearest_players(
                        misc_data.misc_coordinates,
                        2  -- For Allies, since these are typically Allies actions
                    )
                    if nearest_allies and #nearest_allies > 0 then
                        for _, clientNum in ipairs(nearest_allies) do
                            local guid = clientGuids[clientNum].guid
                            record_obj_stat(guid, "obj_misc", misc_name, current_time)
                            log(string.format("Misc event '%s' attributed to: %s", misc_name, guid))
                        end
                    end
                    break
                end
            end
        end

        if map_config.escort then
            for escort_name, escort_data in pairs(map_config.escort) do
                if string.find(normalized_text, normalize_key(escort_data.escort_pattern)) then
                    local nearest_allies = find_nearest_players(
                        escort_data.escort_coordinates,
                        2  -- For Allies, since these are typically Allies actions
                    )
                    if nearest_allies and #nearest_allies > 0 then
                        for _, clientNum in ipairs(nearest_allies) do
                            local guid = clientGuids[clientNum].guid
                            record_obj_stat(guid, "obj_escort", escort_name, current_time)
                            log(string.format("Escort event '%s' attributed to: %s", escort_name, guid))
                        end
                    end
                    break
                end
            end
        end
    end

        -- Handle objectives and popups
    if string.find(text, "legacy popup:") then
        local normalized_text = normalize_key(strip_colors(text))

        if map_config.objectives then
            for _, obj in pairs(map_config.objectives) do
                if string.find(normalized_text, normalize_key(obj.steal_pattern)) then
                    objective_states[obj.name].last_popup = normalized_text
                    objective_states[obj.name].timestamp = trap_Milliseconds()
                    break
                elseif string.find(normalized_text, normalize_key(obj.return_pattern)) then
                    local returner_guid = objective_states[obj.name].carrier_id and 
                                        clientGuids[objective_states[obj.name].carrier_id] or "WORLD"

                    record_obj_stat(returner_guid, "obj_returned", obj.name, trap_Milliseconds())
                    log(string.format("Return: %s by %s", obj.name, returner_guid))

                    -- Clear carrier state
                    if objective_states[obj.name].carrier_id then
                        objective_carriers.players[objective_states[obj.name].carrier_id] = nil
                        objective_states[obj.name].carrier_id = nil
                    end
                end
            end
        end
    end

    -- Handle dynamite events
    local function handle_dynamite_event(event_type, text, action_name)
        local id, event_text = text:match("^" .. event_type .. ": (%d+) (.+)$")
        if id and event_text then
            local guid = clientGuids[tonumber(id)]
            local normalized_text = normalize_key(event_text:match("^%s*(.-)%s*$"))
    
            -- Check common buildables first
            for obj_name, common_config in pairs(common_buildables) do
                if map_config.buildables[obj_name] and 
                   match_any_pattern(normalized_text, common_config.patterns.plant) then
                    record_obj_stat(guid.guid, "obj_" .. action_name, obj_name, trap_Milliseconds())
                    log(string.format("%s: %s by %s", action_name, obj_name, guid.guid))
                    update_objective_state(obj_name, action_name, guid)
                    return
                end
            end
    
            -- Then check map-specific buildables
            for obj_name, obj_config in pairs(map_config.buildables) do
                if type(obj_config) ~= "boolean" and 
                   obj_config.plant_pattern and 
                   obj_config.plant_pattern ~= "" and
                   string.find(normalized_text, normalize_key(obj_config.plant_pattern)) then
                    record_obj_stat(guid.guid, "obj_" .. action_name, obj_name, trap_Milliseconds())
                    log(string.format("%s: %s by %s", action_name, obj_name, guid.guid))
                    update_objective_state(obj_name, action_name, guid)
                    break
                end
            end
        end
    end

    if string.find(text, "Dynamite_Plant:") then
        handle_dynamite_event("Dynamite_Plant", text, "planted")
    elseif string.find(text, "Dynamite_Diffuse:") then
        handle_dynamite_event("Dynamite_Diffuse", text, "defused")
    end

    -- Handle repairs
    if string.find(text, "Repair:") then
        local id = string.match(text, "^Repair: (%d+)")
        if id then
            local guid = clientGuids[tonumber(id)]
            local objective_name = "Unknown Repair"
            local current_time = trap_Milliseconds()
            -- Check common buildables first
            for obj_name, common_config in pairs(common_buildables) do
                if map_config.buildables[obj_name] and 
                   check_recent_construction(obj_name, common_config.patterns, map_config.buildables[obj_name], current_time) then
                    objective_name = obj_name
                    break
                end
            end
    
            -- Only check map-specific if no common match
            if objective_name == "Unknown Repair" then
                for obj_name, obj_config in pairs(map_config.buildables) do
                    if type(obj_config) == "table" and 
                       obj_config.construct_pattern and 
                       obj_config.construct_pattern ~= "" and
                       check_recent_construction(obj_name, nil, obj_config, current_time) then
                        objective_name = obj_name
                        break
                    end
                end
            end
            record_obj_stat(guid.guid, "obj_repaired", objective_name, current_time)
        end
    end

    -- Handle flag/item pickups
    if string.find(text, "Item:") and 
       (string.find(text, "team_CTF_redflag") or string.find(text, "team_CTF_blueflag")) then
        local id = tonumber(string.match(text, "Item: (%d+)"))
        if id then
            for _, obj in pairs(map_config.objectives) do
                if objective_states[obj.name] and 
                   objective_states[obj.name].last_popup and 
                   (trap_Milliseconds() - objective_states[obj.name].timestamp) < 1000 then
                    local normalized_popup = normalize_key(strip_colors(objective_states[obj.name].last_popup))

                    if string.find(normalized_popup, normalize_key(obj.steal_pattern)) then
                        local client = clientGuids[id]
                        if client then
                            record_obj_stat(client.guid, "obj_taken", obj.name, trap_Milliseconds())
                            log(string.format("Steal: %s by %s", obj.name, client.guid))
    
                            objective_carriers.players[id] = obj.name
                            objective_states[obj.name].carrier_id = id
                            if not contains(objective_carriers.ids, id) then
                                table.insert(objective_carriers.ids, id)
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    -- Handle objective securing
    if string.find(text, "secure") or string.find(text, "escap") or 
       string.find(text, "transmit") or string.find(text, "capture") or 
       string.find(text, "transport") then
        local normalized_text = normalize_key(strip_colors(text))
        local first_sentence = normalized_text:match("[^.]+")

        if first_sentence and map_config.objectives then
            for _, obj in ipairs(map_config.objectives) do
                if obj.secured_pattern and string.find(first_sentence, obj.secured_pattern) then
                    for carrier_id, carried_obj in pairs(objective_carriers.players) do
                        if carried_obj == obj.name then
                            local guid = clientGuids[carrier_id]
                            local timestamp = trap_Milliseconds()

                            record_obj_stat(guid.guid, "obj_secured", obj.name, timestamp)
                            log(string.format("Secure: %s by %s", obj.name, guid.guid))

                            -- Clear carrier states
                            objective_carriers.players[carrier_id] = nil
                            for i, v in ipairs(objective_carriers.ids) do
                                if v == carrier_id then
                                    table.remove(objective_carriers.ids, i)
                                    break
                                end
                            end

                            update_objective_state(obj.name, "secured")
                            break
                        end
                    end
                    break
                end
            end
        end
    end

    -- Handle shoves
    if configuration.collect_shovestats then
        local shover, target = string.match(text, "^Shove: (%d+) (%d+)")
        if shover and target then
            local shover_guid = clientGuids[tonumber(shover)].guid
            local target_guid = clientGuids[tonumber(target)].guid
            local timestamp = trap_Milliseconds()
            
            if shover_guid and target_guid then
                record_obj_stat(shover_guid, "shoves_given", target_guid, timestamp)
                record_obj_stat(target_guid, "shoves_received", shover_guid, timestamp)
            end
        end
    end
end

-- JSON file output functions
local function save_to_json(final_data)
    if not configuration.json_output_enabled then
        return false
    end

    local output_dir = configuration.json_output_directory
    if not output_dir or output_dir:match("^%%.*%%$") then
        log("JSON output disabled: Invalid directory path")
        return false
    end

    -- Create directory if it doesn't exist
    os.execute("mkdir -p " .. output_dir)

    -- Generate filename with timestamp
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local mapname = final_data.round_info.mapname or "unknown"
    local round = final_data.round_info.round or 1
    local filename = string.format("%s%s_round%d_%s.json", output_dir, mapname, round, timestamp)

    local success, err = pcall(function()
        local file, open_err = io.open(filename, "w")
        if not file then
            error("Failed to open file: " .. (open_err or "unknown error"))
        end
        
        local json_str = json.encode(final_data)
        if not json_str then
            error("Failed to encode data as JSON")
        end
        
        file:write(json_str)
        file:close()
    end)

    if success then
        log("Data successfully saved to JSON file: " .. filename)
        return true
    else
        log("JSON save error: " .. tostring(err))
        return false
    end
end

local function cleanup_old_json_files()
    if not configuration.json_output_enabled or not configuration.json_retention_days then
        return
    end

    local output_dir = configuration.json_output_directory
    if not output_dir then return end

    local success, err = pcall(function()
        local cutoff_time = os.time() - (configuration.json_retention_days * 24 * 60 * 60)
        
        -- Use platform-specific command to delete old files
        if package.config:sub(1,1) == "\\" then -- Windows
            -- This is a simplified approach for Windows
            for file in io.popen('dir "'..output_dir..'" /b'):lines() do
                if file:match("%.json$") then
                    local path = output_dir .. file
                    local mod_time = io.popen('for %I in ("'..path..'") do @echo %~tI'):read("*a")
                    -- Parse mod_time and compare with cutoff_time
                    -- Implementation depends on your needs
                end
            end
        else -- Unix/Linux
            os.execute("find " .. output_dir .. " -name \"*.json\" -mtime +" .. 
                      configuration.json_retention_days .. " -delete")
        end
        
        log("Cleaned up old JSON files (older than " .. configuration.json_retention_days .. " days)")
    end)
    
    if not success then
        log("JSON cleanup error: " .. tostring(err))
    end
end

-- Capture obituaries
function et_Obituary(target, attacker, meansOfDeath)
    if configuration.collect_obituaries then
        local victimRespawnTime = 0
        local attackerRespawnTime = 0

        -- Only get respawn time for valid players
        if attacker ~= 1022 and attacker >= 0 and attacker < maxClients then      
            victimRespawnTime = calculateReinfTime(et.gentity_get(attacker, "sess.sessionTeam"))
        end

        if target >= 0 and target < maxClients then
            attackerRespawnTime = calculateReinfTime(et.gentity_get(target, "sess.sessionTeam"))        
        end

        table_insert(obituaries, {
            timestamp = trap_Milliseconds(),
            target = clientGuids[target].guid,
            attacker = clientGuids[attacker].guid,
            meansOfDeath = meansOfDeath,
            attackerRespawnTime = attackerRespawnTime,
            victimRespawnTime = victimRespawnTime
        })
    end

    -- obj_carrier death handling
    if not configuration.collect_objstats then return end
    local map_config = map_configs[mapname]
    if not map_config then return end

    for obj_name, state in pairs(objective_states) do
        if state.carrier_id == target then
            local victim_guid = clientGuids[target].guid
            local killer_guid = clientGuids[attacker].guid

            record_obj_stat(victim_guid, "obj_carrierkilled", obj_name, trap_Milliseconds(), {
                guid = killer_guid,
                weapon = meansOfDeath,
                objective = obj_name
            })

            -- Clear carrier state
            objective_carriers.players[target] = nil
            state.carrier_id = nil
            state.last_action = "killed"
        end
    end
end

-- Intercept client commands for messages
function et_ClientCommand(clientNum, command)
    if not configuration.collect_messages then return 0 end

    local gamestate = tonumber(et.trap_Cvar_Get("gamestate"))
    if not gamestate or gamestate > 2 then return 0 end

    local commands_to_intercept = {
        ["say"] = true,
        ["say_team"] = true,
        ["say_teamNL"] = true,
        ["say_buddy"] = true,
        ["vsay"] = true,
        ["vsay_team"] = true,
        ["vsay_buddy"] = true
    }

    if commands_to_intercept[command] then
        local client_data = clientGuids[clientNum]
        if not client_data or not client_data.guid then
            return 0
        end

        table_insert(messages, {
            timestamp = trap_Milliseconds(),
            guid = client_data.guid,
            command = command,
            message = et.trap_Argv(1)
        })
    end
    return 0
end

local function getAllHitRegions(clientNum)
    if not clientNum or type(clientNum) ~= "number" then
        return {}
    end

    local regions = {}
    for _, hitType in ipairs(HR_TYPES) do
        local success, count = pcall(function()
            return et.gentity_get(clientNum, "pers.playerStats.hitRegions", hitType)
        end)
        -- If we can't get the hit region count, default to 0
        regions[hitType] = (success and count) or 0
    end       
    return regions
end

-- Function to determine the hit type
local function getHitRegion(clientNum)
    if not clientNum or type(clientNum) ~= "number" then
        return HR_NONE
    end

    -- Get current hit regions
    local playerHitRegions = getAllHitRegions(clientNum)
    
    -- Initialize hit regions data if not exists
    if not hitRegionsStats[clientNum] then
        hitRegionsStats[clientNum] = playerHitRegions
        return HR_NONE
    end

    -- Compare with previous hit regions to determine which region was hit
    for _, hitType in ipairs(HR_TYPES) do
        if playerHitRegions[hitType] > (hitRegionsStats[clientNum][hitType] or 0) then
            hitRegionsStats[clientNum] = playerHitRegions
            return hitType
        end     
    end

    -- Update stored hit regions and return no hit
    hitRegionsStats[clientNum] = playerHitRegions
    return HR_NONE
end

-- Capture damage events
function et_Damage(target, attacker, damage, damageFlags, meansOfDeath)
    if not configuration.collect_damageStats then return end
    
    local hitRegion = getHitRegion(attacker)
    table_insert(damageStats, {
        timestamp = trap_Milliseconds(),
        target = clientGuids[target].guid,
        attacker = clientGuids[attacker].guid,
        damage = damage or 0,
        damageFlags = damageFlags or 0,
        meansOfDeath = meansOfDeath or 0,
        hitRegion = HR_NAMES[hitRegion]
    })
end

-- char *G_createStats(gentity_t *ent) g_match.c
function StoreStats()
	for i = 0, maxClients - 1 do
	    if gentity_get(i, "pers.connected") == CON_CONNECTED then
			local dwWeaponMask = 0
			local aWeaponStats = {}
			local weaponStats  = ""

			for j = WS_KNIFE, WS_MAX - 1 do
				aWeaponStats[j] = gentity_get(i, "sess.aWeaponStats", j)

				local atts      = aWeaponStats[j][1]
				local deaths    = aWeaponStats[j][2]
				local headshots = aWeaponStats[j][3]
				local hits      = aWeaponStats[j][4]
				local kills     = aWeaponStats[j][5]

				if atts ~= 0 or hits ~= 0 or deaths ~= 0 or kills ~= 0 then
					weaponStats  = string.format("%s %d %d %d %d %d", weaponStats, hits, atts, kills, deaths, headshots)
					dwWeaponMask = dwWeaponMask | (1 << j)
				end
			end

			if dwWeaponMask ~= 0 then
				local userinfo = trap_GetUserinfo(i)
				local guid     = string.upper(Info_ValueForKey(userinfo, "cl_guid"))
				local name     = gentity_get(i, "pers.netname")
				local rounds   = gentity_get(i, "sess.rounds")
				local team     = gentity_get(i, "sess.sessionTeam")

				local damageGiven        = gentity_get(i, "sess.damage_given")
				local damageReceived     = gentity_get(i, "sess.damage_received")
				local teamDamageGiven    = gentity_get(i, "sess.team_damage_given")
				local teamDamageReceived = gentity_get(i, "sess.team_damage_received")
				local gibs               = gentity_get(i, "sess.gibs")
				local selfkills          = gentity_get(i, "sess.self_kills")
				local teamkills          = gentity_get(i, "sess.team_kills")
				local teamgibs           = gentity_get(i, "sess.team_gibs")
				local timeAxis           = gentity_get(i, "sess.time_axis")
				local timeAllies         = gentity_get(i, "sess.time_allies")
				local timePlayed         = gentity_get(i, "sess.time_played")
				local xp                 = gentity_get(i, "ps.persistant", PERS_SCORE)

				timePlayed               = timeAxis + timeAllies == 0 and 0 or (100.0 * timePlayed / (timeAxis + timeAllies))
				
				stats[guid] = string.format("%s\\%s\\%d\\%d\\%d%s", string.sub(guid, 1, 8), name, rounds, team, dwWeaponMask, weaponStats)
				stats[guid] = string.format("%s %d %d %d %d %d %d %d %d %0.1f %d\n", stats[guid], damageGiven, damageReceived, teamDamageGiven, teamDamageReceived, gibs, selfkills, teamkills, teamgibs, timePlayed, xp)
			end
		end
	end
end

function SaveStats()
    -- Guard against multiple calls
    if saveStatsState.inProgress then
        log("SaveStats already in progress, skipping")
        return
    end
    saveStatsState.inProgress = true

    local mapname = Info_ValueForKey(et.trap_GetConfigstring(et.CS_SERVERINFO), "mapname")
    local round = tonumber(et.trap_Cvar_Get("g_currentRound")) == 0 and 2 or 1

    log(string.format("Saving stats - Map: %s, Round: %d", mapname, round))

    -- header data
    local header_json = {
        servername = et.trap_Cvar_Get("sv_hostname"),
        config = et.trap_Cvar_Get("g_customConfig"),
        defenderteam = tonumber(isEmpty(Info_ValueForKey(et.trap_GetConfigstring(et.CS_MULTI_INFO), "d"))) + 1,
        winnerteam = tonumber(isEmpty(Info_ValueForKey(et.trap_GetConfigstring(et.CS_MULTI_MAPWINNER), "w"))) + 1,
        timelimit = ConvertTimelimit(et.trap_Cvar_Get("timelimit")),
        nextTimeLimit = ConvertTimelimit(et.trap_Cvar_Get("g_nextTimeLimit")),
        mapname = mapname,
        round = round,
        matchID = "N/A",  -- Not using match ID in JSON version
        server_ip = server_ip,
        server_port = server_port,
        round_start = round_start_time,
        round_end = round_end_time
    }

    if configuration.collect_obituaries then
        header_json.obituaries = obituaries
    end

    if configuration.collect_damageStats then
        header_json.damageStats = damageStats
    end

    if configuration.collect_messages then
        header_json.messages = messages
    end

    -- Convert stats to JSON format
    local stats_json = {}
    for guid, player_stats_str in pairs(stats) do
        local player_stats_arr = {}
        for stat in string.gmatch(player_stats_str, "[^\\]+") do
            table_insert(player_stats_arr, stat)
        end

        local weaponStats_arr = {}
        for stat in string.gmatch(player_stats_arr[5], "[^%s]+") do
            table_insert(weaponStats_arr, stat)
        end

        stats_json[guid] = {
            guid = player_stats_arr[1],
            name = player_stats_arr[2],
            rounds = player_stats_arr[3],
            team = player_stats_arr[4],
            weaponStats = weaponStats_arr
        }

        -- Add movement and stance stats
        if playerMovementStats[guid] then
            stats_json[guid].distance_travelled_meters = math.floor(playerMovementStats[guid].distance_travelled * 10) / 10
            if playerMovementStats[guid].distance_travelled_spawn > 0 then
                stats_json[guid].distance_travelled_spawn = math.floor(playerMovementStats[guid].distance_travelled_spawn * 10) / 10

                if playerMovementStats[guid].spawn_count and playerMovementStats[guid].spawn_count > 0 then
                    stats_json[guid].spawn_count = playerMovementStats[guid].spawn_count
                    stats_json[guid].distance_travelled_spawn_avg = math.floor((playerMovementStats[guid].distance_travelled_spawn / playerMovementStats[guid].spawn_count) * 10) / 10
                end
            end

            if playerMovementStats[guid].total_speed_samples > 0 then
                local avg_speed_ups = playerMovementStats[guid].total_speed_sum / playerMovementStats[guid].total_speed_samples
                local peak_speed_ups = playerMovementStats[guid].peak_speed_ups

                stats_json[guid].player_speed = {
                    ups_avg = math.floor(avg_speed_ups * 10) / 10,
                    ups_peak = math.floor(peak_speed_ups * 10) / 10,
                    kph_avg = math.floor((avg_speed_ups / SPEED_US_TO_KPH) * 10) / 10,
                    kph_peak = math.floor((peak_speed_ups / SPEED_US_TO_KPH) * 10) / 10,
                    mph_avg = math.floor((avg_speed_ups / SPEED_US_TO_MPH) * 10) / 10,
                    mph_peak = math.floor((peak_speed_ups / SPEED_US_TO_MPH) * 10) / 10
                }
            end
        end

        if playerStanceStats[guid] then
            stats_json[guid].stance_stats_seconds = {
                in_prone = math.floor(playerStanceStats[guid].in_prone),
                in_crouch = math.floor(playerStanceStats[guid].in_crouch),
                in_mg = math.floor(playerStanceStats[guid].in_mg),
                in_lean = math.floor(playerStanceStats[guid].in_lean),
                in_objcarrier = math.floor(playerStanceStats[guid].in_objcarrier),
                in_vehiclescort = math.floor(playerStanceStats[guid].in_vehiclescort),
                in_disguise = math.floor(playerStanceStats[guid].in_disguise),
                in_sprint = math.floor(playerStanceStats[guid].in_sprint),
                in_turtle = math.floor(playerStanceStats[guid].in_turtle),
                is_downed = math.floor(playerStanceStats[guid].is_downed),
            }
        end

        -- Add objective stats
        if configuration.collect_objstats and objstats[guid] then
            for stat_type, stat_data in pairs(objstats[guid]) do
                if next(stat_data) then  -- Only add non-empty stat categories
                    stats_json[guid][stat_type] = stat_data
                end
            end
        end

        -- Add class switch stats
        if playerClassSwitches[guid] and #playerClassSwitches[guid] > 0 then
            local formattedSwitches = {}
            for i, switch in ipairs(playerClassSwitches[guid]) do
                table.insert(formattedSwitches, {
                    timestamp = switch.timestamp,
                    fromClass = switch.fromClass and CLASS_LOOKUP[switch.fromClass] or nil,
                    toClass = switch.toClass and CLASS_LOOKUP[switch.toClass] or "unknown"
                })
            end
            stats_json[guid].class_switches = formattedSwitches
        end
    end

    -- Combine and sanitize
    local final_data = {
        round_info = header_json,
        player_stats = stats_json
    }

    -- Save to JSON
    if configuration.json_output_enabled then
        local success = save_to_json(final_data)
        if success then
            cleanup_old_json_files()
        else
            log("Failed to save data to JSON file")
        end
    end

    -- Reset tables
    resetGameState()

    log("SaveStats completed")
end

function et_RunFrame(gameFrameLevelTime)
    local gamestate = tonumber(et.trap_Cvar_Get("gamestate"))
    handle_gamestate_change(gamestate)

    levelTime = gameFrameLevelTime
    trackPlayerStanceAndMovement(gameFrameLevelTime)

    if configuration.force_names and gamestate == et.GS_WARMUP then
        checkPlayerReadyStatus()
    elseif configuration.force_names and gamestate == et.GS_PLAYING then
        checkAllPlayersNamesGameplay(gameFrameLevelTime)
    end

    processRenameQueue(gameFrameLevelTime)

    -- store stats in case player leaves prematurely
    if gameFrameLevelTime >= nextStoreTime then
        StoreStats()
        nextStoreTime = gameFrameLevelTime + storeTimeInterval
    end

    if gamestate == et.GS_INTERMISSION then
        if not intermission then
            log("Entering intermission")
            intermission = true
            StoreStats()
            scheduledSaveTime = gameFrameLevelTime + saveStatsDelay
        elseif gameFrameLevelTime >= scheduledSaveTime and scheduledSaveTime > 0 and not saveStatsState.inProgress then
            SaveStats()
        end
    else
        if intermission then
            log("Leaving intermission")
            intermission = false
            scheduledSaveTime = 0
            saveStatsState.inProgress = false
        end
    end
end

local function validateConfiguration()
    -- Check map configuration
    if not map_configs then
        log("Configuration error: map_configs is nil")
        return false, "No map configuration found"
    end
    
    if table_count(map_configs) == 0 then
        log("Configuration error: No map configurations loaded")
        return false, "No map configurations loaded"
    end
    
    if not common_buildables or not next(common_buildables) then
        log("Configuration error: No common buildables configuration")
        return false, "No common buildables configuration loaded"
    end
    
    return true
end

function et_InitGame()
    et.RegisterModname(string.format("%s %s", modname, version))
    parseReinforcementTimes()

    local config_valid, error_message = validateConfiguration()
    if not config_valid then
        et.G_Print(string.format("\n%s Configuration Error: %s\n", modname, error_message))
        return
    end
    
    local init_success = initializeServerInfo()
    lastFrameTime = et.trap_Milliseconds()
    current_gamestate = tonumber(et.trap_Cvar_Get("gamestate")) or -1

    -- Initialize clientGuids cache for all connected players
    for clientNum = 0, maxClients - 1 do
        if et.gentity_get(clientNum, "pers.connected") == CON_CONNECTED then
            local userinfo = trap_GetUserinfo(clientNum)
            if userinfo and userinfo ~= "" then
                local guid = string.upper(Info_ValueForKey(userinfo, "cl_guid"))
                local sessionTeam = tonumber(et.gentity_get(clientNum, "sess.sessionTeam")) or 0
                if guid and guid ~= "" then
                    clientGuids[clientNum] = { guid = guid, team = sessionTeam }
                    log(string.format("Initialized client %d - GUID: %s, Team: %d", clientNum, guid, sessionTeam))
                    initializePlayerTracking(clientNum)
                end
            end
        end
    end
    
    log(string.rep("-", 50))
    log(string.format("%s v%s initialized %s", modname, version, init_success and "successfully" or "with warnings"))
end