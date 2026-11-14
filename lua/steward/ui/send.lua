-- The keys that save a steward screen, as on workhorse.nvim's (its ui/send.lua):
--   <leader><leader>  normal mode (buffer-local: it overrides a global mapping that saves all)
--   <C-CR>            insert mode
--
-- :w does nothing: the screens are acwrite buffers whose BufWriteCmd does nothing, so an
-- auto-save plugin never saves a half-typed path. 'modified' keeps tracking pending edits.
local M = {}

--- Map the save keys of `bufnr` to `fn`; insert mode is left first
function M.map(bufnr, fn, desc)
  local opts = { buffer = bufnr, silent = true, nowait = true, desc = "Steward: " .. desc }
  vim.keymap.set("n", "<leader><leader>", fn, opts)
  vim.keymap.set("i", "<C-CR>", function()
    vim.cmd("stopinsert")
    fn()
  end, opts)
end

--- Make :w do nothing on `bufnr` (which has to be 'acwrite', or :w would write a file)
function M.ignore_write(bufnr, group)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = bufnr,
    callback = function() end,
  })
end

return M
