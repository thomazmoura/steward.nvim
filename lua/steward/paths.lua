-- Paths of the project folders: the code folder, how an entry of projects.json is resolved and
-- shown, and the folders a parent adds. The same rules as dev-environment's project_folders.py,
-- which is what the tmux pickers read the file with:
--   * an entry is relative to the code folder, ~/..., or absolute;
--   * a parent adds its first level of folders, hidden ones left out;
--   * a folder is shown relative to the code folder when it is in it, else ~/... under home.
local M = {}

local uv = vim.uv or vim.loop

local function home()
  return uv.fs_realpath(vim.fn.expand("~")) or vim.fn.expand("~")
end

local function is_dir(path)
  local stat = path and uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end
M.is_dir = is_dir

--- The tmux server's global $CODE_FOLDER (dev-environment's tmux config sets it), or nil
local function tmux_code_folder()
  if vim.fn.executable("tmux") == 0 then
    return nil
  end
  local ok, result = pcall(function()
    return vim.system({ "tmux", "show-environment", "-g", "CODE_FOLDER" }, { text = true }):wait(2000)
  end)
  if not ok or result.code ~= 0 then
    return nil
  end
  return (result.stdout or ""):match("^CODE_FOLDER=(.-)%s*$")
end

--- Where the projects are: `configured` (config.code_folder) when given, else $CODE_FOLDER, else
--- the tmux server's, else the first of ~/code, ~/git and /Git that exists, else ~. Always the
--- real path, as tmux and git see it (a ~/code linked to /Git is /Git).
---@param configured string|function|nil
---@return string
function M.code_folder(configured)
  if type(configured) == "function" then
    configured = configured()
  end
  local candidates = {}
  local first = configured or vim.env.CODE_FOLDER
  if first == nil or first == "" then
    first = tmux_code_folder()
  end
  if first and first ~= "" then
    table.insert(candidates, first)
  end
  vim.list_extend(candidates, { "~/code", "~/git", "/Git" })
  for _, candidate in ipairs(candidates) do
    local path = vim.fn.expand(candidate)
    if is_dir(path) then
      return uv.fs_realpath(path) or path
    end
  end
  return home()
end

--- An entry as an absolute, normalized path: ~ expanded, a relative one under `root`
---@param entry string
---@param root string
---@return string
function M.resolve(entry, root)
  local path = vim.trim(entry)
  if path == "~" or path:sub(1, 2) == "~/" then
    path = vim.fn.expand("~") .. path:sub(2)
  elseif path:sub(1, 1) ~= "/" then
    path = root .. "/" .. path
  end
  return vim.fs.normalize(path)
end

local function under(path, base)
  base = base:gsub("/+$", "")
  if path:sub(1, #base + 1) == base .. "/" then
    return path:sub(#base + 2)
  end
end

--- How a folder is shown: relative to `root` when in it, ~/... under home, else absolute
---@param path string
---@param root string
---@return string
function M.shown(path, root)
  local relative = under(path, root)
  if relative then
    return relative
  end
  local h = home()
  if path == h then
    return "~"
  end
  relative = under(path, h)
  return relative and ("~/" .. relative) or path
end

--- The folders a parent adds: its first level, hidden ones and unreadable links left out
---@param parent string absolute path
---@return string[] names, sorted ignoring case
function M.children(parent)
  local names = {}
  local handle = uv.fs_scandir(parent)
  if not handle then
    return names
  end
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if name:sub(1, 1) ~= "." then
      if kind == "directory" or ((kind == "link" or kind == nil) and is_dir(parent .. "/" .. name)) then
        table.insert(names, name)
      end
    end
  end
  table.sort(names, function(a, b)
    return a:lower() < b:lower()
  end)
  return names
end

--- The pickers' folders: the first level of `root`, of every parent, and every individual
--- folder (project_folders.projects). Folders reached twice, `root` itself and paths that do
--- not exist are left out.
---@param root string The code folder
---@param data table { parents, folders }, as store.load gives them
---@return string[] absolute paths, as reached (not resolved through links), sorted ignoring case
function M.projects(root, data)
  local candidates = {}
  local function children_of(parent)
    for _, name in ipairs(M.children(parent)) do
      table.insert(candidates, parent .. "/" .. name)
    end
  end
  children_of(root)
  for _, parent in ipairs(data.parents or {}) do
    children_of(M.resolve(parent, root))
  end
  for _, folder in ipairs(data.folders or {}) do
    table.insert(candidates, M.resolve(folder, root))
  end
  local real_root = uv.fs_realpath(root) or root
  local seen, result = {}, {}
  for _, candidate in ipairs(candidates) do
    local path = vim.fs.normalize(candidate)
    local real = uv.fs_realpath(path)
    if real and real ~= real_root and not seen[real] and is_dir(real) then
      seen[real] = true
      table.insert(result, path)
    end
  end
  table.sort(result, function(a, b)
    return M.shown(a, root):lower() < M.shown(b, root):lower()
  end)
  return result
end

return M
