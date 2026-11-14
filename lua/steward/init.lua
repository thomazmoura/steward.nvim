-- steward.nvim: the environment's settings, edited as text in Neovim: the project folders the
-- tmux session pickers offer (projects.json, :Steward projects) and the tmux theme colours
-- (themes.json, :Steward themes).
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

--- The themes screen
function M.themes()
  return require("steward.themes").open()
end

return M
