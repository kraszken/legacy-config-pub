-- ===================================================================
-- FILENAME: database.lua
-- DESCRIPTION: A reusable module to abstract all interactions with
--              the ET:Legacy built-in SQLite3 API.
-- ===================================================================

DB = {}
local _db_env = nil
local _db_conn = nil

-- SQLite3 API return codes
local SQLITE_OK = 0
local SQLITE_ROW = 100
local SQLITE_DONE = 101

-- Utility for logging database-specific errors
local function log_db_error(message)
    et.G_Print(string.format("^1^7 %s\n", message))
end

--- Connects to the SQLite database file.
-- @param filename (string) The relative path to the database file.
-- @return (boolean) True on success, false on failure.
function DB.Connect(filename)
    if _db_conn then
        log_db_error("Database is already connected.")
        return true
    end

    -- The et.trap_sqlite3_* functions are the built-in, supported way
    -- to interact with SQLite in ET:Legacy.[1]
    _db_env = et.trap_sqlite3_open_v2(filename)
    if not _db_env then
        log_db_error("Failed to create database environment for: ".. filename)
        return false
    end

    _db_conn = et.trap_sqlite3_connection(_db_env)
    if not _db_conn then
        log_db_error("Failed to establish database connection.")
        et.trap_sqlite3_close_v2(_db_env)
        _db_env = nil
        return false
    end

    -- Enable Write-Ahead Logging for better performance and concurrency.
    DB.Execute("PRAGMA journal_mode=WAL;")
    DB.Execute("PRAGMA synchronous=NORMAL;")

    et.G_Print(string.format("Successfully connected to database: %s\n", filename))
    return true
end

--- Disconnects from the database.
function DB.Disconnect()
    if _db_conn then
        et.trap_sqlite3_close_v2(_db_env)
        _db_conn = nil
        _db_env = nil
        et.G_Print("Database connection closed.\n")
    end
end

--- Executes a non-query SQL statement (INSERT, UPDATE, DELETE, CREATE).
-- @param sql (string) The SQL statement to execute.
-- @param params (table, optional) A table of parameters to bind to the statement.
-- @return (boolean) True on success, false on failure.
function DB.Execute(sql, params)
    if not _db_conn then
        log_db_error("Cannot execute query: no database connection.")
        return false
    end

    local stmt = et.trap_sqlite3_prepare_v2(_db_conn, sql)
    if not stmt then
        log_db_error("Failed to prepare statement: ".. et.trap_sqlite3_errmsg(_db_conn))
        return false
    end

    if params then
        for i, v in ipairs(params) do
            local rc
            if type(v) == "number" then
                if math.floor(v) == v then
                    rc = et.trap_sqlite3_bind_int64(stmt, i, v)
                else
                    rc = et.trap_sqlite3_bind_double(stmt, i, v)
                end
            elseif type(v) == "string" then
                rc = et.trap_sqlite3_bind_text(stmt, i, v)
            elseif v == nil then
                rc = et.trap_sqlite3_bind_null(stmt, i)
            else -- boolean, etc.
                rc = et.trap_sqlite3_bind_text(stmt, i, tostring(v))
            end
            if rc ~= SQLITE_OK then
                log_db_error("Failed to bind parameter #".. i.. ": ".. et.trap_sqlite3_errmsg(_db_conn))
                et.trap_sqlite3_finalize(stmt)
                return false
            end
        end
    end

    local rc = et.trap_sqlite3_step(stmt)
    if rc ~= SQLITE_DONE and rc ~= SQLITE_ROW then
        log_db_error("Failed to execute statement: ".. et.trap_sqlite3_errmsg(_db_conn))
        et.trap_sqlite3_finalize(stmt)
        return false
    end

    et.trap_sqlite3_finalize(stmt)
    return true
end

--- Executes a query and returns the first resulting row.
-- @param sql (string) The SQL SELECT statement.
-- @param params (table, optional) A table of parameters to bind to the statement.
-- @return (table or nil) A table representing the row if found, otherwise nil.
function DB.QueryRow(sql, params)
    if not _db_conn then
        log_db_error("Cannot execute query: no database connection.")
        return nil
    end

    local stmt = et.trap_sqlite3_prepare_v2(_db_conn, sql)
    if not stmt then
        log_db_error("Failed to prepare statement: ".. et.trap_sqlite3_errmsg(_db_conn))
        return nil
    end

    if params then
        for i, v in ipairs(params) do
            local rc = et.trap_sqlite3_bind_text(stmt, i, tostring(v))
            if rc ~= SQLITE_OK then
                log_db_error("Failed to bind parameter #".. i.. ": ".. et.trap_sqlite3_errmsg(_db_conn))
                et.trap_sqlite3_finalize(stmt)
                return nil
            end
        end
    end

    local rc = et.trap_sqlite3_step(stmt)
    local row = nil
    if rc == SQLITE_ROW then
        row = {}
        local col_count = et.trap_sqlite3_column_count(stmt)
        for i = 0, col_count - 1 do
            local col_name = et.trap_sqlite3_column_name(stmt, i)
            local col_type = et.trap_sqlite3_column_type(stmt, i)
            if col_type == 1 then -- INTEGER
                row[col_name] = et.trap_sqlite3_column_int64(stmt, i)
            elseif col_type == 2 then -- FLOAT
                row[col_name] = et.trap_sqlite3_column_double(stmt, i)
            elseif col_type == 3 then -- TEXT
                row[col_name] = et.trap_sqlite3_column_text(stmt, i)
            else -- NULL or BLOB
                row[col_name] = nil
            end
        end
    end

    et.trap_sqlite3_finalize(stmt)
    return row
end

--- Executes a query and returns the ID of the last inserted row.
-- @return (number or nil) The last insert row ID, or nil on failure.
function DB.LastInsertRowId()
    if not _db_conn then
        log_db_error("Cannot get last insert ID: no database connection.")
        return nil
    end
    return et.trap_sqlite3_last_insert_rowid(_db_conn)
end