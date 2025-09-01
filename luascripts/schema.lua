-- ===================================================================
-- FILENAME: schema.lua
-- DESCRIPTION: Defines and creates the database tables required for
--              the statistics system.
-- ===================================================================

Schema = {}

local TBL_MATCHES =]

local TBL_ROUNDS =]

local TBL_PLAYERS =]

local TBL_ROUND_PLAYER_STATS =]

local TBL_OBITUARIES =]

local TBL_DAMAGE_STATS =]

local TBL_OBJECTIVE_STATS =]

local TBL_MESSAGES =]

local TBL_CLASS_SWITCHES =]

--- Initializes the database by creating all necessary tables if they do not exist.
function Schema.Initialize()
    et.G_Print("Initializing database schema...\n")
    DB.Execute(TBL_MATCHES)
    DB.Execute(TBL_ROUNDS)
    DB.Execute(TBL_PLAYERS)
    DB.Execute(TBL_ROUND_PLAYER_STATS)
    DB.Execute(TBL_OBITUARIES)
    DB.Execute(TBL_DAMAGE_STATS)
    DB.Execute(TBL_OBJECTIVE_STATS)
    DB.Execute(TBL_MESSAGES)
    DB.Execute(TBL_CLASS_SWITCHES)
    et.G_Print("Schema initialization complete.\n")
end