-- steward's options (setup(opts)): every one is optional
local M = {}

local function config_home()
  local xdg = vim.env.XDG_CONFIG_HOME
  return (xdg and xdg ~= "") and xdg or vim.fn.expand("~/.config")
end

local defaults = {
  projects = {
    -- The project folders file; nil is $XDG_CONFIG_HOME/dev-environment/projects.json, where
    -- dev-environment's tmux pickers read it (resolved when used, so $XDG_CONFIG_HOME may change)
    file = nil,
    -- The code folder: a path, a function returning one, or nil for $CODE_FOLDER, else the tmux
    -- server's $CODE_FOLDER, else the first of ~/code, ~/git and /Git (paths.code_folder)
    code_folder = nil,
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local file = M.options.projects.file
  if file ~= nil and type(file) ~= "string" then
    vim.notify("steward: projects.file must be a path", vim.log.levels.WARN)
    M.options.projects.file = nil
  end
end

--- The projects file's path
function M.projects_file()
  local file = M.options.projects.file
  if file then
    return vim.fn.expand(file)
  end
  return config_home() .. "/dev-environment/projects.json"
end

return M
