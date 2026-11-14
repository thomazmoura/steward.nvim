-- steward.nvim: the environment's settings, edited as text in Neovim. For now the project
-- folders the tmux session pickers offer (projects.json, :Steward projects).
local M = {}

local config = require("steward.config")

--- Optional: every option has a default (see config.lua)
function M.setup(opts)
  config.setup(opts)
end

--- The project folders screen
function M.projects()
  return require("steward.projects").open()
end

return M
