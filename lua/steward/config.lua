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
  themes = {
    -- The themes file; nil is $XDG_CONFIG_HOME/dev-environment/themes.json, where
    -- dev-environment's tmux theme scripts read it
    file = nil,
    -- What saving runs (with -g -a) to draw the open tmux sessions in their new colours at once:
    -- nil is dev-environment's ~/.modules/tmux/scripts/Set-SessionTheme.sh, false runs nothing
    -- (tmux then picks the file up on the next session switch or prefix+u)
    apply = nil,
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  for _, name in ipairs({ "projects", "themes" }) do
    local file = M.options[name].file
    if file ~= nil and type(file) ~= "string" then
      vim.notify("steward: " .. name .. ".file must be a path", vim.log.levels.WARN)
      M.options[name].file = nil
    end
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

--- The themes file's path
function M.themes_file()
  local file = M.options.themes.file
  if file then
    return vim.fn.expand(file)
  end
  return config_home() .. "/dev-environment/themes.json"
end

--- The themes steward ships (defaults/themes.json in the plugin), shown while there is no file
function M.default_themes_file()
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  local root = vim.fn.fnamemodify(source, ":p:h:h:h")
  return root .. "/defaults/themes.json"
end

return M
