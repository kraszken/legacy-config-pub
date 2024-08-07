local modname = "spawn-invul-1sec"
local version = "0.1"

local function removeSpawnShield(clientNum)
    et.gentity_set(clientNum, "ps.powerups", et.PW_INVULNERABLE, 0)
end

function et_ClientSpawn(clientNum, revived)
    if not revived then
        et.gentity_set(clientNum, "ps.powerups", et.PW_INVULNERABLE, 1)
        et.G_Timer(1000, function()
            removeSpawnShield(clientNum)
        end)
    else
        et.gentity_set(clientNum, "ps.powerups", et.PW_INVULNERABLE, 1)
        et.G_Timer(1000, function()
            removeSpawnShield(clientNum)
        end)
    end
end

function et_InitGame()
    et.RegisterModname(modname .. " " .. version)
end
