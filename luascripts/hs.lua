Version = "1.6"
Author  = "^wMicha^0!"
Description = "^7Hide^1&^7Seek"
Homepage = "^7..."
Irc = "^7#..."

-------------------------------------------------------
-- Updated July 2024
--  Changelog:
--    1.6:
--      Updated for ETL cvar support 
--
--    1.5:
--		Disabled forcetapout command
--		Disabled lock command
--
--    1.4:
--		Disabled kill command
--
--    1.3:	
--		Added unlimited Stamina
--		Added Message
--
--    1.2:
--		Corrected Text
--
--    1.1:
--		Made Configable
-- 
--    1.0:
--        	Known bugs u still get a knife
--        	initial release
--
-------------------------------------------------------
 
--global vars
et.MAX_WEAPONS = 50
samplerate = 200
--

--note sme got no comments because it arent weapons
weapons = {
	nil,		--// 1
	false,	--WP_LUGER,				// 2
	false,	--WP_MP40,				// 3
	false,	--WP_GRENADE_LAUNCHER,		// 4
	false,	--WP_PANZERFAUST,			// 5
	false,	--WP_FLAMETHROWER,		// 6
	true,		--WP_COLT,				// 7	// equivalent american weapon to german luger
	false,	--WP_THOMPSON,			// 8	// equivalent american weapon to german mp40
	false,	--WP_GRENADE_PINEAPPLE,	/	// 9
	false,	--WP_STEN,				// 10	// silenced sten sub-machinegun
	true,		--WP_MEDIC_SYRINGE,		// 11	// JPW NERVE -- broken out from CLASS_SPECIAL per Id request
	true,		--WP_AMMO,				// 12	// JPW NERVE likewise
	false,	--WP_ARTY,				// 13
	false,	--WP_SILENCER,			// 14	// used to be sp5
	false,	--WP_DYNAMITE,			// 15
	nil,		--// 16
	nil,		--// 17
	nil,		--// 18
	true,		--WP_MEDKIT,			// 19
	false,	--WP_BINOCULARS,			// 20
	nil,		--// 21
	nil,		--// 22
	false,	--WP_KAR98,				// 23	// WolfXP weapons
	false,	--WP_CARBINE,			// 24
	false,	--WP_GARAND,			// 25
	false,	--WP_LANDMINE,			// 26
	false,	--WP_SATCHEL,			// 27
	false,	--WP_SATCHEL_DET,			// 28
	nil,		--// 29
	false,	--WP_SMOKE_BOMB,			// 30
	false,	--WP_MOBILE_MG42,			// 31
	false,	--WP_K43,				// 32
	false,	--WP_FG42,				// 33
	nil,		--// 34
	false,	--WP_MORTAR,			// 35
	nil,		--// 36
	false,	--WP_AKIMBO_COLT,			// 37
	false,	--WP_AKIMBO_LUGER,		// 38
	nil,		--// 39
	nil,		--// 40
	false,	--WP_SILENCED_COLT,		// 41
	false,	--WP_GARAND_SCOPE,		// 42
	false,	--WP_K43_SCOPE,			// 43
	false,	--WP_FG42SCOPE,			// 44
	false,	--WP_MORTAR_SET,			// 45
	false,	--WP_MEDIC_ADRENALINE,		// 46
	false,	--WP_AKIMBO_SILENCEDCOLT,	// 47
	false		--WP_AKIMBO_SILENCEDLUGER,	// 48
}

function et_InitGame(levelTime,randomSeed,restart)
	maxclients = tonumber( et.trap_Cvar_Get( "sv_maxClients" ) )   --gets the maxclients
	et.G_Print("[H&S] Version:"..Version.." Loaded\n")
   	et.RegisterModname("H&S by Micha!")
	et.trap_SendServerCommand(-1, "b 8 \""..Description.." ^1[^7LUA^1] ^7powered by "..Author.." ^0^7Visit "..Homepage.." ^7Idle^1&^7Stay "..Irc.." \n\"" )
		count = {}
			for i = 0, mclients - 1 do
			count[i] = 0	
	end	
end

-- called every server frame
function et_RunFrame( levelTime )
    
   if math.mod(levelTime, samplerate) ~= 0 then return end
   -- for all clients
   for j = 0, (maxclients - 1) do
      for k=1, (et.MAX_WEAPONS - 1), 1 do
          if not weapons[k] then
            et.gentity_set(j, "ps.ammoclip", k, 0)
            et.gentity_set(j, "ps.ammo", k, 0)
            et.gentity_set(j, "ps.ammo", 7, 150)
	    et.gentity_set(j, "ps.ammo", 11, 150)
	    et.gentity_set(j, "ps.powerups", 12, levelTime + 10000 )
         end
      end      
   end
      
function et_ClientBegin( clientNum )
   et.trap_SendServerCommand(clientNum, "cp \"^wHide ^1& ^wSeek\"\n" )
end

end

function et_ClientCommand(client, command)
  if string.lower(command) == "kill" then
    et.trap_SendServerCommand( client, "cp \"^1Sorry^z, ^wit's ^1disabled ^won this server^z.\n\"" )
    return 1 
  end
  if string.lower(command) == "forcetapout" then
    et.trap_SendServerCommand( clientNum, "cp \"^1Sorry, outtapping is disabled on this server.\n\"" )
    return 1
  end
  if string.lower(command) == "lock" then
    et.trap_SendServerCommand( clientNum, "cpm \"^1Sorry, this command is disabled on this server.\n\"" )
    return 1
  end
end