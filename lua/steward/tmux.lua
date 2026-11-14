-- What steward asks the tmux server it runs under. Nothing outside tmux, or when tmux does not
-- answer in time.
local M = {}

local SEPARATOR = "\31"

--- The server's sessions: { name, path, target, dir, ssh_name } (target, dir and ssh_name are
--- dev-environment's @ssh_target, @ssh_dir and @ssh_name, "" on a local session)
---@return table[]
function M.sessions()
  if vim.fn.executable("tmux") == 0 then
    return {}
  end
  local format = table.concat({ "#{session_name}", "#{session_path}", "#{@ssh_target}", "#{@ssh_dir}", "#{@ssh_name}" }, SEPARATOR)
  local ok, result = pcall(function()
    return vim.system({ "tmux", "list-sessions", "-F", format }, { text = true }):wait(2000)
  end)
  if not ok or result.code ~= 0 then
    return {}
  end
  local sessions = {}
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    local fields = vim.split(line, SEPARATOR, { plain = true })
    table.insert(sessions, {
      name = fields[1] or "",
      path = fields[2] or "",
      target = fields[3] or "",
      dir = fields[4] or "",
      ssh_name = fields[5] or "",
    })
  end
  return sessions
end

--- The file dev-environment's Set-SessionLabel.sh keeps the sessions' prefix+$ names in
function M.labels_file()
  local cache = vim.env.XDG_CACHE_HOME
  cache = (cache and cache ~= "") and cache or vim.fn.expand("~/.cache")
  return cache .. "/tmux/session-names"
end

--- The sessions' prefix+$ names (labels), open or not: { key, label, target, dir }. key is the
--- session's name (without the user@ an ssh one may have), target its ssh target ("" for a local
--- session) and dir its folder. themes.json can name a session by its label.
---@return table[]
function M.labels()
  local labels = {}
  local handle = io.open(M.labels_file(), "r")
  if not handle then
    return labels
  end
  for line in handle:lines() do
    local fields = vim.split(line, "\t", { plain = true })
    if (fields[1] or "") ~= "" and (fields[2] or "") ~= "" then
      table.insert(labels, { key = fields[1], label = fields[2], target = fields[3] or "", dir = fields[4] or "" })
    end
  end
  handle:close()
  return labels
end

--- The script that themes the open sessions again (dev-environment's Set-SessionTheme.sh), or
--- nil when it is not there
---@param setting string|false|nil config.options.themes.apply
---@return string|nil
function M.apply_script(setting)
  if setting == false then
    return nil
  end
  local path = vim.fn.expand(setting or "~/.modules/tmux/scripts/Set-SessionTheme.sh")
  if vim.fn.executable(path) == 1 then
    return path
  end
end

--- Draw every open session in the colour themes.json now picks for it (and the global bar in
--- its default), in the background; on_done(ok) when it finished. False when there is no script
--- or no tmux to run it against.
---@param setting string|false|nil config.options.themes.apply
---@param on_done fun(ok: boolean)|nil
---@return boolean
function M.apply_themes(setting, on_done)
  local script = M.apply_script(setting)
  if not script or vim.fn.executable("tmux") == 0 then
    return false
  end
  local ok = pcall(vim.system, { script, "-g", "-a" }, { text = true }, function(result)
    if on_done then
      vim.schedule(function()
        on_done(result.code == 0)
      end)
    end
  end)
  return ok
end

return M
