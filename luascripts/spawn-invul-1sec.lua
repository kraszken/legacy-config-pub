spawnShield = 1 -- seconds
levelTime = 0
hs_maps = {"purefrag", "et_headshot2_b2", "mp_sillyctf", "ctf_multi", "multi_huntplace", "badplace4_rc", "te_valhalla"}
flag = false

function has_value (tab, val)
	for index, value in ipairs(tab) do
		if value == val then
			return true
		end
	end
	return false
end

function et_InitGame(levelTime, randomSeed, restart)
	et.RegisterModname("spawnshield.lua "..et.FindSelf())
	mapname = et.trap_Cvar_Get("mapname")
	if has_value(hs_maps, string.lower(mapname)) then
		flag = true
	end
end

function et_RunFrame(lvltime)
	levelTime = lvltime
end

function et_ClientSpawn(clientNum, revived)
	if flag == true then
		et.gentity_set(clientNum, "ps.powerups", 1, levelTime + spawnShield * 1000)
	end
end