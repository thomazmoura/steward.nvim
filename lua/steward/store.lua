-- The settings files steward edits, plain JSON or plain text so a script with no Neovim can read
-- them. Keys steward does not know are kept as they are when it saves.
--
-- code-folder, where the projects are: one line, the folder (~/... or absolute), read by every
-- shell (dev-environment's code-folder-env.sh, from ~/.bashrc, exports it as $CODE_FOLDER) and by
-- the scripts that work the code folder out (code-folder.sh, kernel-profile.ps1, tmux_link.py).
-- Plain text rather than JSON so a shell reads it with a builtin, on every ssh command:
--
--   /Git
--
-- projects.json, the project folders the tmux session pickers offer (dev-environment's
-- project_folders.py reads it):
--
--   {
--     "version": 1,
--     "parents": ["clients", "~/work"],
--     "folders": ["~/notes"]
--   }
--
-- themes.json, the tmux theme colours and which session draws in which (dev-environment's
-- themes.py reads it):
--
--   {
--     "version": 1,
--     "themes": [{ "name": "moon", "color": "#00abab" }],
--     "assignments": [{ "match": "default", "theme": "moon" }]
--   }
local M = {}

local uv = vim.uv or vim.loop

M.VERSION = 1

--- The JSON object in the file at `path`. A missing or empty file is nil and `true` (missing);
--- one that cannot be read or parsed, or is not an object, is nil, false and the error.
---@param path string
---@return table|nil decoded
---@return boolean missing
---@return string|nil err
function M.read_object(path)
  local handle = io.open(path, "rb")
  if not handle then
    if not uv.fs_stat(path) then
      return nil, true
    end
    return nil, false, "cannot read " .. path
  end
  local content = handle:read("*a")
  handle:close()
  if vim.trim(content) == "" then
    return nil, true
  end
  local ok, decoded = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok then
    return nil, false, path .. " is not valid JSON: " .. tostring(decoded)
  end
  if type(decoded) ~= "table" or vim.islist(decoded) then
    return nil, false, path .. " is not a JSON object"
  end
  return decoded, false
end

--- Write `text` to `path`, creating its folder: to a temporary file renamed over it, so a reader
--- (a picker opening right then) never sees half of it
---@param path string
---@param text string
---@return boolean ok
---@return string|nil err
function M.write_atomic(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local temporary = path .. ".tmp" .. uv.os_getpid()
  local handle, err = io.open(temporary, "wb")
  if not handle then
    return false, err
  end
  handle:write(text)
  handle:close()
  local ok, rename_err = uv.fs_rename(temporary, path)
  if not ok then
    os.remove(temporary)
    return false, rename_err
  end
  return true
end

--- The keys of `decoded` other than `known` (and version)
local function extra_of(decoded, known)
  local extra = {}
  for key, value in pairs(decoded) do
    if key ~= "version" and not vim.tbl_contains(known, key) then
      extra[key] = value
    end
  end
  return extra
end

--- `fields` (already encoded "  key: value" lines) plus the extra keys, as the file's text
local function object(fields, extra)
  local keys = vim.tbl_keys(extra or {})
  table.sort(keys)
  for _, key in ipairs(keys) do
    table.insert(fields, "  " .. vim.json.encode(key) .. ": " .. vim.json.encode(extra[key]))
  end
  return "{\n" .. table.concat(fields, ",\n") .. "\n}\n"
end

--- A JSON array of already-encoded items, one a line, so a diff of it reads well
local function list(items)
  if #items == 0 then
    return "[]"
  end
  return "[\n    " .. table.concat(items, ",\n    ") .. "\n  ]"
end

-- Projects ------------------------------------------------------------------------------------

local function strings(value)
  local result = {}
  if type(value) ~= "table" then
    return result
  end
  for _, entry in ipairs(value) do
    if type(entry) == "string" and vim.trim(entry) ~= "" then
      table.insert(result, entry)
    end
  end
  return result
end

--- The projects file at `path`: { parents, folders, extra } (extra: the keys steward does not
--- know). A missing file is an empty one; one that cannot be read or parsed is nil and the error.
---@param path string
---@return table|nil data
---@return string|nil err
function M.load(path)
  local decoded, missing, err = M.read_object(path)
  if not decoded then
    if missing then
      return { parents = {}, folders = {}, extra = {} }
    end
    return nil, err
  end
  return {
    parents = strings(decoded.parents),
    folders = strings(decoded.folders),
    extra = extra_of(decoded, { "parents", "folders" }),
  }
end

--- The projects file's text: one entry a line
---@param data table { parents, folders, extra }
---@return string
function M.encode(data)
  return object({
    '  "version": ' .. M.VERSION,
    '  "parents": ' .. list(vim.tbl_map(vim.json.encode, data.parents or {})),
    '  "folders": ' .. list(vim.tbl_map(vim.json.encode, data.folders or {})),
  }, data.extra)
end

--- Write the projects `data` to `path`
---@param path string
---@param data table
---@return boolean ok
---@return string|nil err
function M.save(path, data)
  return M.write_atomic(path, M.encode(data))
end

-- Code folder ---------------------------------------------------------------------------------

--- The code folder saved at `path`, its first line trimmed; nil when there is none
---@param path string
---@return string|nil
function M.load_code_folder(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local line = handle:read("*l")
  handle:close()
  line = line and vim.trim(line) or ""
  return line ~= "" and line or nil
end

--- Write the code folder `folder` (as typed: ~/... or absolute) to `path`
---@param path string
---@param folder string
---@return boolean ok
---@return string|nil err
function M.save_code_folder(path, folder)
  return M.write_atomic(path, folder .. "\n")
end

-- Themes --------------------------------------------------------------------------------------

local function nonempty(value)
  return type(value) == "string" and vim.trim(value) ~= ""
end

--- The themes file at `path`: { themes = { { name, color } }, assignments = { { match, theme } },
--- extra }, entries that are not both strings left out. A missing file is nil with missing =
--- true (the screen then shows the defaults); one that cannot be read or parsed is nil and the
--- error.
---@param path string
---@return table|nil data
---@return boolean missing
---@return string|nil err
function M.load_themes(path)
  local decoded, missing, err = M.read_object(path)
  if not decoded then
    return nil, missing, err
  end
  local data = { themes = {}, assignments = {}, extra = extra_of(decoded, { "themes", "assignments" }) }
  for _, theme in ipairs(type(decoded.themes) == "table" and decoded.themes or {}) do
    if type(theme) == "table" and nonempty(theme.name) and nonempty(theme.color) then
      table.insert(data.themes, { name = theme.name, color = theme.color })
    end
  end
  for _, assignment in ipairs(type(decoded.assignments) == "table" and decoded.assignments or {}) do
    if type(assignment) == "table" and nonempty(assignment.match) and nonempty(assignment.theme) then
      table.insert(data.assignments, { match = assignment.match, theme = assignment.theme })
    end
  end
  return data, false
end

--- The themes file's text: one theme or assignment a line, its keys in a fixed order
---@param data table { themes, assignments, extra }
---@return string
function M.encode_themes(data)
  local themes = vim.tbl_map(function(theme)
    return ('{ "name": %s, "color": %s }'):format(vim.json.encode(theme.name), vim.json.encode(theme.color))
  end, data.themes or {})
  local assignments = vim.tbl_map(function(assignment)
    return ('{ "match": %s, "theme": %s }'):format(vim.json.encode(assignment.match), vim.json.encode(assignment.theme))
  end, data.assignments or {})
  return object({
    '  "version": ' .. M.VERSION,
    '  "themes": ' .. list(themes),
    '  "assignments": ' .. list(assignments),
  }, data.extra)
end

--- Write the themes `data` to `path`
---@param path string
---@param data table
---@return boolean ok
---@return string|nil err
function M.save_themes(path, data)
  return M.write_atomic(path, M.encode_themes(data))
end

return M
