walkthrough = {}

function et_InitGame(levelTime, randomSeed, restart)
	et.RegisterModname("walk.lua "..et.FindSelf())
end

function et_ClientSpawn(clientNum, revived)
	if revived ~= 1 then
		local team = tonumber(et.gentity_get(clientNum, "sess.sessionTeam"))
		if team == 1 or team == 2 then
			walkthrough[clientNum] = true
		end
	end
end

function et_RunFrame(levelTime)
	if math.fmod(levelTime,50) ~= 0 then return end
	if next(walkthrough) ~= nil then
		for j=0, tonumber(et.trap_Cvar_Get("sv_maxclients"))-1 do
			local team = tonumber(et.gentity_get(j, "sess.sessionTeam"))
			if team == 1 or team == 2 then
				local health = tonumber(et.gentity_get(j, "health"))
				if health >= 100 then
					if walkthrough[j] == true then
						local spawnshield = et.gentity_get(j, "ps.powerups", 1)
						if (spawnshield > levelTime) then
							et.gentity_set(j, "r.contents", 32) -- Set to water
						else
							walkthrough[j] = nil
							et.gentity_set(j, "r.contents", 33554432) -- Body
						end
					end
				end
			end
		end
	end
end