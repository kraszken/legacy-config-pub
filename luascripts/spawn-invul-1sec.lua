local modname = "spawn-invul-1sec"
local version = "0.2"

function et_ClientSpawn(clientNum, revived)
    -- Set the spawnshield duration to 1 second
    local newDuration = et.trap_Milliseconds() + 1000
    et.gentity_set(clientNum, "ps.powerups", et.PW_INVULNERABLE, newDuration)
end

function et_InitGame()
    et.RegisterModname(modname .. " " .. version)
end
