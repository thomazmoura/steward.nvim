-- steward's command and highlights. Available before setup(), which is optional.
if vim.g.loaded_steward then
  return
end
vim.g.loaded_steward = true

local subcommands = {
  projects = function()
    require("steward").projects()
  end,
}

vim.api.nvim_create_user_command("Steward", function(opts)
  local name = opts.fargs[1] or "projects"
  local run = subcommands[name]
  if not run then
    vim.notify(
      ("Steward: unknown subcommand %q (%s)"):format(name, table.concat(vim.tbl_keys(subcommands), ", ")),
      vim.log.levels.ERROR
    )
    return
  end
  run(opts)
end, {
  nargs = "?",
  desc = "Steward: edit the environment's settings (projects: the tmux pickers' project folders)",
  complete = function(lead)
    return vim.tbl_filter(function(name)
      return name:find(lead, 1, true) == 1
    end, vim.tbl_keys(subcommands))
  end,
})

-- Links to standard groups, so the screens follow the colorscheme; a group the colorscheme or
-- the user already defines is left alone.
local function setup_highlights()
  local groups = {
    StewardHeader = { link = "Title" },
    StewardAction = { link = "Function" },
    StewardSeparator = { link = "Comment" },
    StewardSection = { link = "Title" },
    StewardKey = { link = "Identifier" },
    StewardValue = { link = "String" },
    StewardHint = { link = "Comment" },
    StewardCount = { link = "Number" },
    StewardNew = { link = "DiagnosticOk" },
    StewardWarn = { link = "DiagnosticWarn" },
    StewardError = { link = "DiagnosticError" },
  }
  for name, spec in pairs(groups) do
    if vim.fn.hlexists(name) == 0 or vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = name })) then
      spec.default = true
      vim.api.nvim_set_hl(0, name, spec)
    end
  end
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("steward_highlights", { clear = true }),
  callback = setup_highlights,
})
