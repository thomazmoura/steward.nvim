-- Header of steward's screens, in workhorse.nvim's style (its ui/header.lua, trimmed): the
-- screen's name with its action right-aligned, read-only information lines, then the
-- "───── ◇ ─────" rule, with the editable content right below it:
--
--   Project folders                                                 Reload
--   Code folder  ~/code  (read-only)
--   ─────────────────────────── ◇ ───────────────────────────
--   Parent directories
--
-- The header lines are empty and all their text is virtual: it never ends up in yanks, searches
-- or the parsed lines, and what it shows (the code folder) cannot be edited. A header line that
-- was typed on or deleted blocks saving (M.check). <CR> on a header line runs its action.
local M = {}

local ns = vim.api.nvim_create_namespace("steward_header")

-- Buffer -> header (see M.new), plus the width it was drawn for
local headers = {}

--- The "───── ◇ ─────" rule across `width` columns, as virtual text chunks
---@param width number
---@return table
function M.rule(width)
  local side = math.max(math.floor((width - 3) / 2), 1)
  return {
    { string.rep("─", side) .. " ◇ " .. string.rep("─", math.max(width - 3 - side, 1)), "StewardSeparator" },
  }
end

--- A header: `title`, `info` (a list of lines, each a list of { text, hl } chunks) and `action`
--- ({ text, fn(bufnr) }, shown right-aligned on the title's line and run by <CR> there)
---@param title string
---@param info table|nil
---@param action table|nil
---@return table
function M.new(title, info, action)
  info = info or {}
  return { title = title, info = info, action = action, size = #info + 2 }
end

--- The header's (empty) lines followed by `lines`, to set as the buffer's content
---@param header table
---@param lines string[]
---@return string[]
function M.with(header, lines)
  local result = {}
  for _ = 1, header.size do
    table.insert(result, "")
  end
  return vim.list_extend(result, lines)
end

--- Text width of the narrowest window showing a buffer (minus number/sign columns)
---@param bufnr number
---@return number
function M.width(bufnr)
  local width
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local info = vim.fn.getwininfo(win)[1]
    local w = info.width - info.textoff
    width = width and math.min(width, w) or w
  end
  return width or vim.o.columns
end

--- Draw the header on the buffer's first lines (each only while it is still empty: typed text
--- shows as it is, and blocks saving)
---@param bufnr number
function M.draw(bufnr)
  local header = headers[bufnr]
  if not (header and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  header.width = M.width(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, header.size, false)
  local function draw(lnum, opts)
    if lines[lnum] == "" then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, opts)
    end
  end
  draw(1, { virt_text = { { header.title, "StewardHeader" } }, virt_text_pos = "overlay" })
  if header.action then
    draw(1, { virt_text = { { header.action[1], "StewardAction" } }, virt_text_pos = "right_align" })
  end
  for index, chunks in ipairs(header.info) do
    draw(index + 1, { virt_text = chunks, virt_text_pos = "overlay" })
  end
  draw(header.size, { virt_text = M.rule(header.width), virt_text_pos = "overlay" })
end

--- Show `header` on the first lines of `bufnr`, whose content the screen sets with M.with.
--- Attaching again (new information) replaces it.
---@param bufnr number
---@param header table
function M.attach(bufnr, header)
  local attached = headers[bufnr] ~= nil
  headers[bufnr] = vim.tbl_extend("force", {}, header)
  if not attached then
    -- Every change moves the header's marks: draw it again once it is done
    local pending = false
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = function()
        if not headers[bufnr] then
          return true
        end
        if not pending then
          pending = true
          vim.schedule(function()
            pending = false
            M.draw(bufnr)
          end)
        end
      end,
      on_detach = function()
        headers[bufnr] = nil
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        headers[bufnr] = nil
      end,
    })
  end
  M.draw(bufnr)
end

--- Number of header lines of a buffer (0 without a header)
function M.size(bufnr)
  return headers[bufnr] and headers[bufnr].size or 0
end

--- What <CR> on a line runs (called with the buffer), when it is the header's title line
function M.action(bufnr, lnum)
  local header = headers[bufnr]
  if header and header.action and lnum == 1 then
    return header.action[2]
  end
end

--- Error blocking a save when the header lines were edited, nil when they are intact
---@param bufnr number
---@return string|nil
function M.check(bufnr)
  local header = headers[bufnr]
  if not header then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, header.size, false)
  for lnum = 1, header.size do
    if not (lines[lnum] or ""):match("^%s*$") then
      return "The header above the list was edited (line " .. lnum .. "): undo it, or <leader>R reloads"
    end
  end
  return nil
end

-- The rule spans the window: draw it again when the width changes
local resize_events = { "VimResized" }
if vim.fn.exists("##WinResized") == 1 then
  table.insert(resize_events, "WinResized")
end
local group = vim.api.nvim_create_augroup("steward_header", { clear = true })
vim.api.nvim_create_autocmd(resize_events, {
  group = group,
  callback = function()
    for bufnr, header in pairs(headers) do
      if vim.api.nvim_buf_is_valid(bufnr) and M.width(bufnr) ~= header.width then
        M.draw(bufnr)
      end
    end
  end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    local header = headers[args.buf]
    if header and M.width(args.buf) ~= header.width then
      M.draw(args.buf)
    end
  end,
})

return M
