-- Completion of the lines of a screen (a key, a theme, a folder) from a list of choices, shown
-- like a dropdown while typing (blink.cmp, see steward.ui.blink, or the native menu). Ported
-- from paperboy.nvim's choices.lua (itself from workhorse.nvim's ui/choices.lua), so the
-- completion looks and behaves the same.
--
-- A buffer attaches a source: { choices = fn(bufnr, lnum) -> list|nil, true for a
-- comma-separated list completed one item at a time; start = fn(line, lnum) -> 0-based column
-- where the value starts, optional: by default the value follows the first ":" of the line }.
-- A choice is the text to insert, or { word = text to insert, menu = what it is } (a theme's
-- colour, "session", "folder"), matched on the word and shown with the menu beside it
local M = {}

-- [bufnr] = source, plus the completion state: engine ("blink"|"native"), completed
local sources = {}

local function choices(bufnr, lnum)
  local source = sources[bufnr]
  if not source then
    return nil
  end
  return source.choices(bufnr, lnum)
end

-- Column (0-based) where the value of `line` starts, nil when it has none
local function value_start(bufnr, line, lnum)
  local source = sources[bufnr]
  local start = source.start and source.start(line, lnum)
  if start then
    return start
  end
  local colon = line:find(":")
  if not colon then
    return nil
  end
  return colon + #(line:sub(colon + 1):match("^%s*"))
end

--- omnifunc of the attached buffers (<C-x><C-o> on lines with choices)
function M.omnifunc(findstart, base)
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  if findstart == 1 then
    local start = sources[bufnr] and value_start(bufnr, line, lnum)
    if not start then
      return -3
    end
    local _, list = choices(bufnr, lnum)
    if list then
      -- Complete the item after the last comma before the cursor
      local before = line:sub(start + 1, vim.api.nvim_win_get_cursor(0)[2])
      local after_comma = before:match(".*,()")
      if after_comma then
        start = start + after_comma - 1 + #(before:sub(after_comma):match("^%s*"))
      end
    end
    return start
  end
  -- Values starting with the text, then containing it, then fuzzy matches (best first). The
  -- menu is left out: it names what a value is ("folder"), so it would match every value
  local prefix, rest, seen = {}, {}, {}
  local query = base:lower()
  local list = choices(bufnr, lnum) or {}
  local texts, by_text = {}, {}
  for _, choice in ipairs(list) do
    local text = M.word(choice)
    local lower = text:lower()
    if lower:find(query, 1, true) == 1 then
      table.insert(prefix, choice)
      seen[choice] = true
    elseif lower:find(query, 1, true) then
      table.insert(rest, choice)
      seen[choice] = true
    end
    table.insert(texts, text)
    by_text[text] = by_text[text] or choice
  end
  vim.list_extend(prefix, rest)
  if query ~= "" then
    for _, text in ipairs(vim.fn.matchfuzzy(texts, base)) do
      local choice = by_text[text]
      if not seen[choice] then
        table.insert(prefix, choice)
        seen[choice] = true
      end
    end
  end
  return prefix
end

--- The text a choice inserts (see the top of this file)
---@param choice string|table
---@return string
function M.word(choice)
  return type(choice) == "table" and choice.word or choice
end

--- Choices matching the value typed before the cursor of the current window, for a line with
--- choices: { start = 0-based column of the value, base = typed text, matches = {...} } or nil
--- (another buffer, a free-text line, the cursor before the value)
function M.choice_completion()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if not sources[bufnr] or not choices(bufnr, cursor[1]) then
    return nil
  end
  local start = M.omnifunc(1, "")
  if start < 0 or cursor[2] < start then
    return nil
  end
  local base = vim.api.nvim_get_current_line():sub(start + 1, cursor[2])
  local matches = M.omnifunc(0, base)
  -- Nothing to offer once the value is exactly the only match (e.g. right after accepting it)
  if #matches == 1 and M.word(matches[1]):lower() == base:lower() then
    matches = {}
  end
  return { start = start, base = base, matches = matches }
end

-- Whether blink.cmp drives the completion (see steward.ui.blink), loading it if installed
-- but not loaded yet
local function use_blink()
  local ok, blink = pcall(require, "blink.cmp")
  return ok and type(blink.add_source_provider) == "function" and require("steward.ui.blink").register()
end

-- Native menu: open (or narrow) it while typing a value with choices, so they show up like a
-- dropdown
local function autocomplete(bufnr)
  local source = sources[bufnr]
  if not source or source.engine ~= "native" or vim.fn.mode() ~= "i" then
    return
  end
  local completion = M.choice_completion()
  if not completion then
    return
  end
  -- Moving through the menu inserts the selected item, and going back to the typed text
  -- repeats it: neither is typing, so leave the menu as is
  local typed = vim.api.nvim_win_get_cursor(0)[1] .. ":" .. completion.base
  if vim.fn.pumvisible() == 1 then
    if typed == source.completed or vim.fn.complete_info({ "selected" }).selected ~= -1 then
      return
    end
  end
  source.completed = typed
  if #completion.matches > 0 or vim.fn.pumvisible() == 1 then
    vim.fn.complete(completion.start + 1, completion.matches)
  end
end

--- Show the choices again after they changed (e.g. finished loading) while typing
function M.refresh(bufnr)
  local source = sources[bufnr]
  if not source or vim.api.nvim_get_current_buf() ~= bufnr or vim.fn.mode() ~= "i" then
    return
  end
  if source.engine == "native" then
    source.completed = nil
    autocomplete(bufnr)
  elseif source.engine == "blink" then
    local completion = M.choice_completion()
    if completion and #completion.matches > 0 then
      local blink = require("blink.cmp")
      if blink.is_menu_visible() then
        pcall(blink.hide)
      end
      vim.schedule(function()
        pcall(blink.show)
      end)
    end
  end
end

-- Pick the completion engine on the first insert: blink.cmp when available, the native menu
-- otherwise (with blink.cmp, if loaded, kept out of the way)
local function setup_engine(bufnr)
  local source = sources[bufnr]
  if not source or source.engine then
    return
  end
  source.engine = use_blink() and "blink" or "native"
  if source.engine == "native" then
    -- Nothing selected until <Tab>, which inserts the item as it goes; <CR> takes the first
    -- item when none is selected
    vim.b[bufnr].completion = false
    vim.bo[bufnr].completeopt = "menuone,noselect"
  end
end

--- Keys moving in the open completion menu (blink.cmp or native) to its next (dir = 1) or
--- previous item, nil when no menu is open
function M.menu_key(dir)
  local blink = package.loaded["blink.cmp"]
  if blink and blink.is_menu_visible and blink.is_menu_visible() then
    return ("<Cmd>lua require('blink.cmp').select_%s()<CR>"):format(dir > 0 and "next" or "prev")
  end
  if vim.fn.pumvisible() == 1 then
    return dir > 0 and "<C-n>" or "<C-p>"
  end
end

--- Insert-mode <CR> (expr mapping): accept the selected item, or the first one when none is
--- selected; a plain <CR> without a menu
function M.insert_cr()
  local blink = package.loaded["blink.cmp"]
  if blink and blink.is_menu_visible and blink.is_menu_visible() then
    return "<Cmd>lua require('blink.cmp').select_and_accept()<CR>"
  end
  if vim.fn.pumvisible() == 0 then
    return "<CR>"
  end
  return vim.fn.complete_info({ "selected" }).selected == -1 and "<C-n><C-y>" or "<C-y>"
end

--- The insert-mode keys of the completion menu on `bufnr`: <Tab>/<S-Tab> move in it (or insert a
--- tab), <CR> accepts (see M.insert_cr)
function M.map(bufnr)
  local function map(lhs, fn, desc)
    vim.keymap.set("i", lhs, fn, { buffer = bufnr, silent = true, expr = true, desc = "Steward: " .. desc })
  end
  map("<CR>", M.insert_cr, "Accept the completion")
  map("<Tab>", function()
    return M.menu_key(1) or "<Tab>"
  end, "Next completion")
  map("<S-Tab>", function()
    return M.menu_key(-1) or "<S-Tab>"
  end, "Previous completion")
end

--- Complete the values of `bufnr` from `source` (see the top of this file), until it is wiped
function M.attach(bufnr, source)
  sources[bufnr] = source
  vim.bo[bufnr].omnifunc = "v:lua.require'steward.ui.choices'.omnifunc"
  local group = vim.api.nvim_create_augroup("steward_choices_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      setup_engine(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      autocomplete(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      sources[bufnr] = nil
      vim.schedule(function()
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end)
    end,
  })
end

return M
