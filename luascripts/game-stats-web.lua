--[[
    ET: Legacy
    Copyright (C) 2012-2022 ET:Legacy team <mail@etlegacy.com>

    This file is part of ET: Legacy - http://www.etlegacy.com

    ET: Legacy is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    ET: Legacy is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with ET: Legacy. If not, see <http://www.gnu.org/licenses/>.
]]--

--[[ 
    Changelog:
        01.01.1970: v1.0.0 -- MaxPower
            - And he said let there be light. Date probably accurate. 

        24-12-2024: v1.0.1 -- Oksii
            - Added local logging

        26-12-2024: v1.0.2 -- Oksii
            - Moved variables to local configuration for easier control
            - Allows us dynamic updating via docker's entrypoint script too.
            - Using placeholder variables as I update them via docker env now.

        29-12-2024: v1.0.3 -- Oksii (Max' idea, I'm just impatient)
            - Moved matchid to remote host, fetch it just before stats submit
            - Use net_ip and net_port as identifiers against the remote host,
            - I intend to use dynamic routes but you could probably just package it
              as a json too. 
            - Implement few retries just in case
            - Fetch IP from public API if net_ip returns 0.0.0.0 
              as not everyone will have a binding set.
            - Default to unixtime if matchid can't be retrieved.

        30-12-2024: v1.0.4 -- Oksii 
            - Added server_ip and server_port to json output to be more easily 
              identifiable when custom games are submitted that no matchid exists for

        31-12-2024: v1.0.5 -- OKsii
            - Added obituaries (et_Obituary( target, attacker, meansOfDeath ))
            - Added damageStats (et_Damage( target, attacker, damage, damageFlags, meansOfDeath))
              See: damageFlags https://etlegacy-lua-docs.readthedocs.io/en/latest/misc.html#damage-bitflags
                   meansOfDeath https://etlegacy-lua-docs.readthedocs.io/en/latest/constants.html#mod-constants
            - Added message capture for all chats
            - Made all toggleable via configuration table
        
        01-01-2025: v1.0.6 -- Oksii
            - Sanitize message log, we think chat binds may have caused the json to malform over special characters
            - Added some more robustness and error handling around stat submission
            - Fetch userinfo and cache guid on first event for faster table lookups
            - Remove player from cache upon disconnect
            - Replace client id with guid in obituaries, messages and damageStats
            - Added CURL retries for more robustness and better error handling

        02-01-2025: v1.0.7 -- Oksii
            - Clean up code, improve for performance and memory optimization 
            - Sanitize SaveStats all in a single pass
            - Set string length limit of 256 chars. Chat is limited to 150, what else would even get close?
            - Added LOG_FORMAT for consistent log formatting
            - Config validation
            - Fixed initialization order and removed duplicate maxClients/max_clients
            - Standardized maxClients variable usage throughout
            - Refactor executeCurlCommand to save json content to temp file and save as binary data rather than string
            - Refactor executeCurlCommand to use several additional command options and simplify GET's 
            - Added lastSpawnTime to obituaries
            - Added HitRegions to damageSats
            - Removed debug logging and json dumps
        
        07-01-2025: v1.0.8 -- Oksii
            - Improved error handling with logger to catch path/perm issues gracefully

        08-01-2025: v1.0.9 -- Oksii
            - Added 3-second delay before SaveStats() to prevent lag spikes during gamestate transition
        
        11-01-2025: v1.0.10 -- MaxPower
            - Added function SaveStatstoFile for local output of JSON stats data
            - Added (back) local configuration variable dump_stats_data for manual toggle of local output
            - Added local configuration variable json_filepath for directing location of json output
            - Added condition to output local json file if there is an error in API call

        15-01-2025: v1.0.11 -- Oksii
            - Fixed invalid gentity field error by properly accessing hitRegions through indexed parameters
]]--

local modname = "game-stats-web-api"
local version = "1.0.11"

-- Required libraries
local json = require("dkjson")

-- Configuration
local configuration = {
    api_token            = "%CONF_STATS_API_TOKEN%",
    api_url_matchid      = "%CONF_STATS_API_URL_MATCHID%",
    api_url_submit       = "%CONF_STATS_API_URL_SUBMIT%",
    log_filepath         = "%CONF_STATS_API_PATH%/game_stats.log",
    json_filepath        = "%CONF_STATS_API_PATH%/",
    logging_enabled      = %CONF_STATS_API_LOG%,            -- Toggle logging on/off
    collect_obituaries   = %CONF_STATS_API_OBITUARIES%,
    collect_messages     = %CONF_STATS_API_MESSAGELOG%,
    collect_damageStats  = %CONF_STATS_API_DAMAGESTAT%,
    dump_stats_data      = %CONF_STATS_API_DUMPJSON%,
}

-- Server info
local server_ip
local server_port

-- local variables
local LOG_FORMAT         = "[%s UTC] %s\n" 
local maxClients         = 20
local intermission       = false
local stats              = {}
local messages           = {}
local obituaries         = {}
local damageStats        = {}
local hitRegionsData     = {}
local nextStoreTime      = 0
local storeTimeInterval  = 5000 -- how often we store players stats
local saveStatsDelay     = 3000 -- wait for intermission screen before sending stats
local scheduledSaveTime  = 0

-- local constants
local CON_CONNECTED      = 2
local WS_KNIFE           = 0
local WS_MAX             = 28
local PERS_SCORE         = 0

-- Constants for hit regions
local HR_HEAD            = 0
local HR_ARMS            = 1
local HR_BODY            = 2
local HR_LEGS            = 3
local HR_NONE            = -1
local HR_TYPES = {HR_HEAD, HR_ARMS, HR_BODY, HR_LEGS}

-- Lookup table for hit region names
local HR_NAMES = {
    [HR_HEAD] = "HR_HEAD",
    [HR_ARMS] = "HR_ARMS",
    [HR_BODY] = "HR_BODY",
    [HR_LEGS] = "HR_LEGS",
    [HR_NONE] = "HR_NONE"
}

-- Caching function references
local trap_GetUserinfo = et.trap_GetUserinfo
local Info_ValueForKey = et.Info_ValueForKey
local trap_Milliseconds = et.trap_Milliseconds
local gentity_get = et.gentity_get
local table_insert = table.insert

-- Logging function
local log = configuration.logging_enabled and function(message)
    if not configuration.log_filepath or configuration.log_filepath:match("^%%.*%%$") then
        return
    end

    local success, err = pcall(function()
        local file, open_err = io.open(configuration.log_filepath, "a")
        if not file then
            et.G_LogPrint(string.format("game-stats-web.lua: Failed to open log file: %s\n", open_err or "unknown error"))
            return
        end
        
        local write_success, write_err = pcall(function()
            file:write(string.format(LOG_FORMAT, os.date("%Y-%m-%d %H:%M:%S"), message))
        end)
        
        file:close()
        
        if not write_success then
            et.G_LogPrint(string.format("game-stats-web.lua: Failed to write to log file: %s\n", write_err or "unknown error"))
        end
    end)
    
    if not success then
        et.G_LogPrint(string.format("game-stats-web.lua: Logging error: %s\n", err or "unknown error"))
    end
end or function() end  -- No-op if logging disabled

function ConvertTimelimit(timelimit)
	local msec    = math.floor(tonumber(timelimit) * 60000)
	local seconds = math.floor(msec / 1000)
	local mins    = math.floor(seconds / 60)
	seconds       = math.floor(seconds - (mins * 60))
	local tens    = math.floor(seconds / 10)
	seconds       = math.floor(seconds - (tens * 10))
	
	return string.format("%i:%i%i", mins, tens, seconds)
end

function isEmpty(str)
	if str == nil or str == '' then
		return 0
	end
	return str
end

-- Fetch and add GUID to cache
local clientGuids = setmetatable({}, {
    __index = function(t, clientNum)
        -- Validate client number
        if not clientNum or type(clientNum) ~= "number" then
            return "WORLD"
        end

        -- Fetch guid and cache if not in table
        if clientNum >= 0 and clientNum < maxClients then
            local userinfo = trap_GetUserinfo(clientNum)
            if userinfo and userinfo ~= "" then
                local guid = string.upper(Info_ValueForKey(userinfo, "cl_guid"))
                if guid and guid ~= "" then
                    t[clientNum] = guid  -- Cache it
                    return guid
                end
            end
        end

        return "WORLD"  -- Fallback
    end
})

-- Remove GUIDs from cache on disconnect
function et_ClientDisconnect(clientNum)
    local guid = clientGuids[clientNum]
    clientGuids[clientNum] = nil
end

local SANITIZE_PATTERNS = {
    ['"'] = '\\"',          -- Escape double quotes for JSON
    ["'"] = "\\'",          -- Escape single quotes
    ['\n'] = '\\n',         -- newlines
    ['\r'] = '\\r',         -- carriage returns
    ['\t'] = '\\t',         -- tabs
    ['\0'] = '',            -- remove null bytes
    ['%z'] = '',            -- remove null bytes
    ['%c'] = ''             -- remove other control characters
}

local function sanitizeData(data, maxLength)
    maxLength = maxLength or 256
    
    local dataType = type(data)
    
    if dataType == "string" then
        -- First handle the basic escapes
        local sanitized = data:gsub('["\'\n\r\t%z%c]', SANITIZE_PATTERNS)
        
        -- Then handle non-ASCII characters
        sanitized = sanitized:gsub('[^%g%s]', function(c)
            -- Convert any non-ASCII character to \u{hex} format
            return string.format('\\u{%x}', string.byte(c))
        end)
        
        if #sanitized > maxLength then
            return sanitized:sub(1, maxLength) .. "..."
        end
        return sanitized
        
    elseif dataType == "table" then
        local sanitized = {}
        for k, v in pairs(data) do
            local sanitizedKey = type(k) == "string" and sanitizeData(k, maxLength) or k
            sanitized[sanitizedKey] = sanitizeData(v, maxLength)
        end
        return sanitized
        
    elseif dataType == "number" or dataType == "boolean" then
        return data
        
    else
        return ""
    end
end

local function SaveStatsToFile(payload, file_path)
    -- Ensure the directory path exists
    local dir_path = file_path:match("^(.*)/[^/]+$") -- Extract directory from the file path
    if dir_path then
        os.execute("mkdir -p " .. dir_path) -- Create the directory if it doesn't exist
    end

    -- Open the file for writing
    local file, err = io.open(file_path, "w")
    if not file then
        log(string.format("Error opening file for writing: %s. Error: %s", file_path, err))
        return false, "Failed to open file"
    end

    -- Write the payload
    local success, write_err = pcall(function()
        file:write(payload)
    end)

    -- Close the file
    file:close()

    -- Handle write errors
    if not success then
        log(string.format("Error writing to file: %s. Error: %s", file_path, write_err))
        return false, "Failed to write file"
    end

    log(string.format("JSON data successfully written to: %s", file_path))
    return true
end

local function executeCurlCommand(curl_cmd, payload, expected_code)
    expected_code = expected_code or "2[0-9][0-9]"
    
    -- If payload provided, handle it separately
    local temp_file
    if payload then
        temp_file = os.tmpname() .. ".json"
        local f = io.open(temp_file, "w")
        if not f then
            return nil, "Failed to create temp file"
        end
        f:write(payload)
        f:close()
        
        -- Modify curl command to read from file
        curl_cmd = string.format('%s --data-binary @%s', curl_cmd, temp_file)
    end

    -- Add curl options
    if not curl_cmd:find("--retry") then
        curl_cmd = curl_cmd .. " -H 'Content-Type: application/json'"
        curl_cmd = curl_cmd .. " --compressed --max-time 30"
        curl_cmd = curl_cmd .. " --retry 5 --retry-delay 1 --retry-max-time 30"
        curl_cmd = curl_cmd .. " --silent"
    end
    
    -- Execute curl command
    local handle = io.popen(curl_cmd, 'r')
    if not handle then
        if temp_file then os.remove(temp_file) end
        return nil, "Failed to create process"
    end
    
    local result = handle:read("*a")
    handle:close()
    
    -- Clean up temp file if it exists
    if temp_file then
        os.remove(temp_file)
    end

    -- Try to decode JSON response
    if result and result ~= "" then
        local success, decoded = pcall(json.decode, result)
        if success then
            return decoded
        end
        -- If JSON decode fails, return the raw result
        return result
    end
    
    return nil, "No response body"
end

local function getPublicIP()
    local curl_cmd = 'curl -s https://api.ipify.org?format=json'
    local result, err = executeCurlCommand(curl_cmd)
    
    if result and result.ip then
        return result.ip
    end
    
    log("Failed to fetch public IP: " .. (err or "unknown error"))
    return "0.0.0.0"
end

local function initializeServerInfo()
    local net_ip = et.trap_Cvar_Get("net_ip")
    local net_port = et.trap_Cvar_Get("net_port")
    
    -- If net_ip is ::0 or 0.0.0.0, fetch public IP
    if net_ip == "0.0.0.0" or net_ip == "::0" then
        server_ip = getPublicIP()
    else
        server_ip = net_ip
    end
    
    server_port = net_port
    log(string.format("Initialized server info - IP: %s, Port: %s", server_ip, server_port))
end

local function fetchMatchIDFromAPI()
    local url = string.format("%s/%s/%s", configuration.api_url_matchid, server_ip, server_port)

    local curl_cmd = string.format(
        'curl -H "Authorization: Bearer %s" %s',
        configuration.api_token,
        url
    )
    
    local result, err = executeCurlCommand(curl_cmd, nil, "200")
    
    if result and result.match_id then
        return result.match_id
    end
    
    log("Failed to fetch match ID from API: " .. (err or "unknown error"))
    return tostring(os.time())
end

-- Capture obituaries
function et_Obituary(target, attacker, meansOfDeath)
    if configuration.collect_obituaries then
        table_insert(obituaries, {
            timestamp = trap_Milliseconds(),
            target = clientGuids[target],
            attacker = clientGuids[attacker],
            meansOfDeath = meansOfDeath,
            attacker_lastSpawnTime = gentity_get(attacker, "pers.lastSpawnTime"),
            target_lastSpawnTime = gentity_get(target, "pers.lastSpawnTime")
        })
    end
end

-- Intercept client commands for messages
function et_ClientCommand(clientNum, command)
    local commands_to_intercept = {
        ["say"] = true,
        ["say_team"] = true,
        ["say_teamNL"] = true,
        ["say_buddy"] = true,
        ["vsay"] = true,
        ["vsay_team"] = true,
        ["vsay_buddy"] = true
    }

    if configuration.collect_messages and commands_to_intercept[command] then
        table_insert(messages, {
            timestamp = trap_Milliseconds(),
            guid = clientGuids[clientNum],
            command = command,
            message = et.trap_Argv(1)
        })
        return 0
    end
    return 0
end

local function getAllHitRegions(clientNum)
    local regions = {}
    for _, hitType in ipairs(HR_TYPES) do
        regions[hitType] = et.gentity_get(clientNum, "pers.playerStats.hitRegions", hitType) or 0
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
    if not hitRegionsData[clientNum] then
        hitRegionsData[clientNum] = playerHitRegions
        return HR_NONE
    end

    -- Compare with previous hit regions to determine which region was hit
    for _, hitType in ipairs(HR_TYPES) do
        if playerHitRegions[hitType] > (hitRegionsData[clientNum][hitType] or 0) then
            hitRegionsData[clientNum] = playerHitRegions
            return hitType
        end     
    end

    -- Update stored hit regions and return no hit
    hitRegionsData[clientNum] = playerHitRegions
    return HR_NONE
end

-- Capture damage events
function et_Damage(target, attacker, damage, damageFlags, meansOfDeath)
    if configuration.collect_damageStats then
        local hitRegion = getHitRegion(attacker)
        table_insert(damageStats, {
            timestamp = trap_Milliseconds(),
            target = clientGuids[target],
            attacker = clientGuids[attacker],
            damage = damage or 0,
            damageFlags = damageFlags or 0,
            meansOfDeath = meansOfDeath or 0,
            hitRegion = HR_NAMES[hitRegion]
        })
    end
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
    local matchID = fetchMatchIDFromAPI(2)
    local mapname = Info_ValueForKey(et.trap_GetConfigstring(et.CS_SERVERINFO), "mapname")
    local round = tonumber(et.trap_Cvar_Get("g_currentRound")) == 0 and 2 or 1

    log(string.format("Saving stats - MatchID: %s, Map: %s, Round: %d", matchID, mapname, round))

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
        matchID = matchID,
        server_ip = server_ip,
        server_port = server_port
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
    end

    -- Combine and sanitize all data at once
    local final_data = sanitizeData({
        round_info = header_json,
        player_stats = stats_json
    })

    -- JSON encode the sanitized data
    local json_str = json.encode(final_data)
    if not json_str then
        log("Error: Failed to encode JSON data")
        return
    end

    -- Construct the curl command
    local curl_cmd = string.format(
        'curl -X POST -H "Authorization: Bearer %s" %s',
        configuration.api_token,
        configuration.api_url_submit
    )

    -- Execute with payload
    local result, err = executeCurlCommand(curl_cmd, json_str, "201")    

    if err then
        log("Error submitting stats: " .. err)
    else
        log("Stats submitted successfully")
    end

    -- Dump Stats Data to local JSON file
    if configuration.dump_stats_data or err then
        -- Make JSON readable
        local json_str_indented = json.encode(final_data, { indent = true })
        if not json_str_indented then
            log("Error: Failed to encode JSON data for file writing")
            return
        end
        -- Build JSON file name
        if not string.match(configuration.json_filepath, "/$") then
            configuration.json_filepath = configuration.json_filepath .. "/"
        end
        local json_file = configuration.json_filepath .. string.format("gamestats-%d-%s%s-round-%d.json", matchID, os.date('%Y-%m-%d-%H%M%S-'), mapname, round)

        -- Save JSON payload to local file
        local success, err = SaveStatsToFile(json_str_indented, json_file)
        if not success then
            log(string.format("Error writing JSON to file: %s", err))
        end
    end

    -- Clear data
    obituaries = {}
    messages = {}
    damageStats = {}
    clientGuids = {}

    if not result or not (type(result) == "table" and result.message == "Request logged successfully") then
        log("Warning: Stats submission failed or returned unexpected response")
    end
end

function et_RunFrame(levelTime)
    local gamestate = tonumber(et.trap_Cvar_Get("gamestate"))
    
    -- store stats in case player leaves prematurely
    if levelTime >= nextStoreTime then
        StoreStats()
        nextStoreTime = levelTime + storeTimeInterval
    end

    if gamestate == et.GS_INTERMISSION and not intermission then
        intermission = true
        StoreStats()
        scheduledSaveTime = levelTime + saveStatsDelay
    elseif gamestate == et.GS_INTERMISSION and intermission and levelTime >= scheduledSaveTime and scheduledSaveTime > 0 then
        SaveStats()
        scheduledSaveTime = 0
    end

    if gamestate ~= et.GS_INTERMISSION then
        intermission = false
        scheduledSaveTime = 0
    end
end

local function validateConfiguration()
    -- Check required API configuration
    if not configuration.api_token or configuration.api_token:match("^%%.*%%$") then
        return false, "Invalid or missing API token"
    end
    
    if not configuration.api_url_matchid or 
       not configuration.api_url_matchid:match("^https?://") or 
       configuration.api_url_matchid:match("^%%.*%%$") then
        return false, "Invalid matchid API URL"
    end
    
    if not configuration.api_url_submit or 
       not configuration.api_url_submit:match("^https?://") or 
       configuration.api_url_submit:match("^%%.*%%$") then
        return false, "Invalid submit API URL"
    end
    
    return true
end

function et_InitGame()
    et.RegisterModname(string.format("%s %s", modname, version))
    
    -- Validate configuration
    local config_valid, error_message = validateConfiguration()
    if not config_valid then
        et.G_Print(string.format("\n%s Configuration Error: %s\n", modname, error_message))
        return
    end
    
    -- Initialize local variables
    maxClients = tonumber(et.trap_Cvar_Get("sv_maxClients")) or maxClients

    initializeServerInfo()

    local et_version = et.trap_Cvar_Get("mod_version")
    local mapname = et.trap_Cvar_Get("mapname")
    local round = tonumber(et.trap_Cvar_Get("g_currentRound")) == 0 and 1 or 2
    
    -- Log initialization
    log(string.rep("-", 50))
    log(string.format("Server Started"))
    log(string.format("ET:Legacy Version: %s", et_version))
    log(string.format("Server: %s:%s", server_ip, server_port))
    log(string.format("Map: %s, Round: %d", mapname, round))
    log(string.rep("-", 50))
    
    log(string.format("%s v%s initialized successfully", modname, version))
end