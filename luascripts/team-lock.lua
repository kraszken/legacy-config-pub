--[[
    Author: mAxPower
    Contributors:
    License: MIT

    Description:    In ETLegacy stopwatch, teams are unlocked when there is a gamestate change.
                    This script solves the issue by locking each team using referee commands when there
                    is a start to a round or a gamestate change from pause/unpause.
]]--

-- version info

local modname = "team-lock"
local version = "1.0"

-- local flags

local roundStarted = false

function et_InitGame(levelTime, randomSeed, restart)
    et.RegisterModname(modname .. " " .. version)
end

function et_RunFrame(levelTime)
    if et.trap_Cvar_Get("gamestate") == "0" then -- Game is running
        if not roundStarted then
            et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref lock r\n")
            et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref lock b\n")
            roundStarted = true
        end
    else
        roundStarted = false
    end
end

function et_ClientCommand(clientNum, command)
    local cmd = string.lower(et.trap_Argv(0))
    if cmd == "pause" then
        et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref unlock r\n")
        et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref unlock b\n")
    elseif cmd == "unpause" then
        roundStarted = false -- This will allow the lock commands to be reissued when the game resumes
    end
end
