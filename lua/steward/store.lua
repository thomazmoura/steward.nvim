-- The settings files steward edits. For now one: projects.json, the project folders the tmux
-- session pickers offer (dev-environment's project_folders.py reads it):
--
--   {
--     "version": 1,
--     "parents": ["clients", "~/work"],
--     "folders": ["~/notes"]
--   }
--
-- Plain JSON, so a script with no Neovim can read it. Keys steward does not know are kept as
-- they are when it saves.
local M = {}

local uv = vim.uv or vim.loop

M.VERSION = 1

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
  local handle = io.open(path, "rb")
  if not handle then
    if not uv.fs_stat(path) then
      return { parents = {}, folders = {}, extra = {} }
    end
    return nil, "cannot read " .. path
  end
  local content = handle:read("*a")
  handle:close()
  if vim.trim(content) == "" then
    return { parents = {}, folders = {}, extra = {} }
  end
  local ok, decoded = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok then
    return nil, path .. " is not valid JSON: " .. tostring(decoded)
  end
  if type(decoded) ~= "table" or vim.islist(decoded) then
    return nil, path .. " is not a JSON object"
  end
  local extra = {}
  for key, value in pairs(decoded) do
    if key ~= "version" and key ~= "parents" and key ~= "folders" then
      extra[key] = value
    end
  end
  return { parents = strings(decoded.parents), folders = strings(decoded.folders), extra = extra }
end

local function list(entries)
  if #entries == 0 then
    return "[]"
  end
  local lines = {}
  for _, entry in ipairs(entries) do
    table.insert(lines, "    " .. vim.json.encode(entry))
  end
  return "[\n" .. table.concat(lines, ",\n") .. "\n  ]"
end

--- The file's text: one entry a line, so a diff of it reads well
---@param data table { parents, folders, extra }
---@return string
function M.encode(data)
  local fields = {
    '  "version": ' .. M.VERSION,
    '  "parents": ' .. list(data.parents or {}),
    '  "folders": ' .. list(data.folders or {}),
  }
  local keys = vim.tbl_keys(data.extra or {})
  table.sort(keys)
  for _, key in ipairs(keys) do
    table.insert(fields, "  " .. vim.json.encode(key) .. ": " .. vim.json.encode(data.extra[key]))
  end
  return "{\n" .. table.concat(fields, ",\n") .. "\n}\n"
end

--- Write `data` to `path`, creating its folder: to a temporary file renamed over it, so a reader
--- (a picker opening right then) never sees half of it
---@param path string
---@param data table
---@return boolean ok
---@return string|nil err
function M.save(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local temporary = path .. ".tmp" .. uv.os_getpid()
  local handle, err = io.open(temporary, "wb")
  if not handle then
    return false, err
  end
  handle:write(M.encode(data))
  handle:close()
  local ok, rename_err = uv.fs_rename(temporary, path)
  if not ok then
    os.remove(temporary)
    return false, rename_err
  end
  return true
end

return M
