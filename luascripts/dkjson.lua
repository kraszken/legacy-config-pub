-- ===================================================================
-- FILENAME: dkjson.lua
-- DESCRIPTION: A pure Lua JSON encoder/decoder.
-- SOURCE: http://dkolf.de/dkjson-lua
-- ===================================================================

local json = { _version = "dkjson 2.5" }

local _toString = tostring

local function _f(s,...)
  return s:format(...)
end

local function _type(o)
  if o == nil then return "nil" end
  -- Consider every non-string, non-boolean, non-number value
  -- to be a table, which should be correct for JSON.
  local t = type(o)
  if t ~= "table" and t ~= "string" and t ~= "boolean" and t ~= "number" then
    t = "table"
  end
  return t
end

local function _isarray(t)
  if type(t) ~= "table" then return false end
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then return false end
  end
  return true
end

local function _esc(s)
  return s:gsub('[\\"]', '\\%0'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

local function _enc(o, depth)
  depth = depth + 1
  if depth > 100 then
    return nil, "nesting depth exceeded"
  end

  local t = _type(o)

  if t == "table" then
    local s = ""
    if _isarray(o) then
      s = "["
      for i = 1, #o do
        local val, err = _enc(o[i], depth)
        if not val then return nil, err end
        s = s.. val.. ","
      end
      s = s:gsub(",$", "").. "]"
    else
      s = "{"
      for k, v in pairs(o) do
        if _type(k) ~= "string" then
          return nil, "table key must be a string"
        end
        local val, err = _enc(v, depth)
        if not val then return nil, err end
        s = s.. '"'.. _esc(k).. '":'.. val.. ","
      end
      s = s:gsub(",$", "").. "}"
    end
    return s
  elseif t == "string" then
    return '"'.. _esc(o).. '"'
  elseif t == "number" then
    if o ~= o then -- is NaN
      return "null"
    elseif o == 1/0 or o == -1/0 then -- is Infinity
      return "null"
    else
      return _f("%.14g", o)
    end
  elseif t == "boolean" then
    return o and "true" or "false"
  elseif t == "nil" then
    return "null"
  else
    return nil, "unsupported type: ".. t
  end
end

function json.encode(o, opt)
  opt = opt or {}
  local val, err = _enc(o, 0)
  if not val and not opt.noerror then
    error(err)
  end
  return val, err
end

local function _dec(s, pos, null)
  pos = pos or 1
  null = null or nil

  local function _err(msg)
    return nil, pos, msg
  end

  local function _space()
    pos = s:match("^%s*", pos)
  end

  local function _char(c)
    if pos > #s then return end
    if s:sub(pos, pos) == c then
      pos = pos + 1
      return true
    end
  end

  local function _expect(c)
    if not _char(c) then
      return _err("'".. c.. "' expected")
    end
    return true
  end

  local function _string()
    _space()
    if not _char('"') then return end
    local str = ""
    while pos <= #s do
      local c = s:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return str
      elseif c == '\\' then
        pos = pos + 1
        c = s:sub(pos, pos)
        if c == "b" then str = str.. "\b"
        elseif c == "f" then str = str.. "\f"
        elseif c == "n" then str = str.. "\n"
        elseif c == "r" then str = str.. "\r"
        elseif c == "t" then str = str.. "\t"
        else str = str.. c
        end
      else
        str = str.. c
      end
      pos = pos + 1
    end
    return _err("unterminated string")
  end

  local function _number()
    _space()
    local num_str, new_pos = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if num_str then
      pos = new_pos
      return tonumber(num_str)
    end
  end

  local function _literal(name, val)
    _space()
    if s:sub(pos, pos + #name - 1) == name then
      pos = pos + #name
      return val
    end
  end

  local function _value()
    _space()
    local c = s:sub(pos, pos)
    if c == '"' then return _string() end
    if c == '{' then return _object() end
    if c == '[' then return _array() end
    if c == 't' then return _literal("true", true) end
    if c == 'f' then return _literal("false", false) end
    if c == 'n' then return _literal("null", null) end
    return _number()
  end

  function _array()
    _space()
    if not _char('[') then return end
    local arr = {}
    _space()
    if _char(']') then return arr end
    while pos <= #s do
      local val, err, msg = _value()
      if err then return nil, err, msg end
      arr[#arr + 1] = val
      _space()
      if _char(']') then return arr end
      if not _expect(',') then return end
    end
    return _err("unterminated array")
  end

  function _object()
    _space()
    if not _char('{') then return end
    local obj = {}
    _space()
    if _char('}') then return obj end
    while pos <= #s do
      local key, err, msg = _string()
      if not key then return nil, err or pos, msg or "string key expected" end
      _space()
      if not _expect(':') then return end
      local val
      val, err, msg = _value()
      if err then return nil, err, msg end
      obj[key] = val
      _space()
      if _char('}') then return obj end
      if not _expect(',') then return end
    end
    return _err("unterminated object")
  end

  local val, new_pos, msg = _value()
  if new_pos then
    return val, new_pos, msg
  end
  _space()
  if pos > #s then
    return nil, pos, "empty string"
  end
  return nil, pos, "invalid value"
end

function json.decode(s, pos, null)
  if type(s) ~= "string" then
    s = _toString(s)
  end
  local val, new_pos, msg = _dec(s, pos, null)
  if not val and msg then
    error(msg.. " at position ".. tostring(new_pos))
  end
  return val, new_pos, msg
end

return json