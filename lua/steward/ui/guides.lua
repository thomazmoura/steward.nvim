-- Tree guides of the screens, as on workhorse.nvim's (its buffer_tree/guides.lua): the lines of a
-- section are indented one level (plain spaces, WIDTH a level) under its title, and the guides
-- (├─ └─ │) are drawn over the indentation as overlay virtual text, so they never end up in yanks
-- or searches and follow the indentation as it is edited. A line gets ├─ when a sibling follows
-- it and └─ otherwise, and │ runs down while an ancestor has a sibling to come.
local M = {}

M.WIDTH = 3
local GLYPHS = { branch = "├─ ", last = "└─ ", vertical = "│  ", blank = "   " }

local ns = vim.api.nvim_create_namespace("steward_guides")

--- Indentation of a line at `level`
function M.prefix(level)
  return string.rep(" ", M.WIDTH * math.max(level or 0, 0))
end

--- Guides of `lines`: { [index] = text }, for the lines indented with spaces (a level is
--- M.WIDTH columns; a line indented less than one level gets none). `boundary(line)` tells the
--- lines that end every tree (section titles); blank lines are skipped
function M.compute(lines, boundary)
  local result = {}
  -- [level] = a line at that level follows, before any less indented line
  local has_next = {}
  for index = #lines, 1, -1 do
    local line = lines[index]
    if boundary and boundary(line) then
      has_next = {}
    elseif not line:match("^%s*$") then
      local level = math.floor(#line:match("^ *") / M.WIDTH)
      if level > 0 then
        local parts = {}
        for depth = 1, level - 1 do
          parts[depth] = has_next[depth] and GLYPHS.vertical or GLYPHS.blank
        end
        parts[level] = has_next[level] and GLYPHS.branch or GLYPHS.last
        result[index] = table.concat(parts)
      end
      has_next[level] = true
      for depth in pairs(has_next) do
        if depth > level then
          has_next[depth] = nil
        end
      end
    end
  end
  return result
end

--- Draw the guides of the lines from `first` (1-based) on (the header's lines are left out)
function M.draw(bufnr, first, boundary)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, -1, false)
  for index, text in pairs(M.compute(lines, boundary)) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, first + index - 2, 0, {
      virt_text = { { text, "StewardGuide" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end
end

-- [bufnr] = { first = fn(bufnr) -> the first line under the header, boundary = fn(line) }
local screens = {}

--- 'indentexpr' of the screens: one level for every line under a section title, none for a title
--- (and the header's lines)
function M.indent(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local screen = screens[bufnr]
  if not screen then
    return -1
  end
  if lnum < screen.first(bufnr) then
    return 0
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  return screen.boundary(line) and 0 or M.WIDTH
end

-- Put the line the cursor leaves insert mode on at its level (a path typed at the start of a line
-- goes under its section), as part of the same change
local function reindent(bufnr)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line or line:match("^%s*$") then
    return
  end
  local want = M.indent(lnum)
  local text = line:gsub("^%s*", "")
  local indented = string.rep(" ", want) .. text
  if want >= 0 and indented ~= line then
    pcall(vim.cmd.undojoin)
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { indented })
    -- The cursor stays on the same character
    vim.api.nvim_win_set_cursor(0, { lnum, math.max(0, col + #indented - #line) })
  end
end

--- Indent options of a screen: a new line under a section starts one level in (o, O and <CR>,
--- even below a title), a line left in insert mode is put at its level, >> and << move one level.
--- `first(bufnr)` is the first line under the header; `boundary(line)` tells a section title.
function M.setup_buffer(bufnr, first, boundary)
  screens[bufnr] = { first = first, boundary = boundary }
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].shiftwidth = M.WIDTH
  vim.bo[bufnr].softtabstop = M.WIDTH
  vim.bo[bufnr].autoindent = true
  vim.bo[bufnr].indentexpr = "v:lua.require'steward.ui.guides'.indent(v:lnum)"
  -- Only on new lines and =: typing a ":" (themes) must not move the line
  vim.bo[bufnr].indentkeys = "o,O"
  local group = vim.api.nvim_create_augroup("steward_guides_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      reindent(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      screens[bufnr] = nil
    end,
  })
end

return M
