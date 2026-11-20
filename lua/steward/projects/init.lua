-- The project folders screen (:Steward projects): the code folder and projects.json as an
-- editable buffer, in the style of workhorse.nvim's repository screens.
--
--   Project folders                                                 Reload
--   Saved in     ~/.config/dev-environment/code-folder
--                ~/.config/dev-environment/projects.json
--   ─────────────────────────── ◇ ───────────────────────────
--   Code folder
--   └─ /Git  24 folders
--
--   Parent directories
--   ├─ clients  12 folders  ~/code/clients
--   └─ ~/work  missing
--
--   Individual directories
--   └─ ~/notes  new
--
-- The tmux session pickers (dev-environment's prefix+/, and prefix+N on a linked machine) list
-- the first level of the code folder, the first level of every parent directory and every
-- individual directory. A path is relative to the code folder, ~/..., or absolute. Adding,
-- changing and removing one is editing the text; <leader><leader> saves.
--
-- The code folder is saved apart, as one line in the code-folder file, which every shell on the
-- machine exports as $CODE_FOLDER (dev-environment's code-folder-env.sh, from ~/.bashrc); saving
-- also hands it to the tmux server, for its new panes. It must be a folder that exists: nothing is
-- saved until it is. Before it was ever saved, the screen shows the one worked out
-- (paths.code_folder), and saving keeps it.
local M = {}

local choices = require("steward.ui.choices")
local config = require("steward.config")
local guides = require("steward.ui.guides")
local header = require("steward.ui.header")
local parse = require("steward.projects.parse")
local paths = require("steward.paths")
local send = require("steward.ui.send")
local store = require("steward.store")

local NAME = "Steward|projects"
local ns = vim.api.nvim_create_namespace("steward_projects")

-- Buffer -> { root, file, code_folder_file, code_folder (saved, or nil), code_folder_hint (why it
-- is shown when it is not the saved one), loaded = { [path] = true }, extra, broken }
local buffers = {}

local function notify(message, level)
  vim.notify("Steward: " .. message, level or vim.log.levels.INFO)
end

local function plural(count, word)
  return ("%d %s%s"):format(count, word, count == 1 and "" or "s")
end

local function home_short(path)
  return (vim.fn.fnamemodify(path, ":~"))
end

local function content_lines(bufnr)
  local size = header.size(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, size, -1, false), size + 1
end

--- The entries of the buffer as edited, resolved: entries, errors and the code folder as edited
--- (the loaded one while the edited one is not a folder)
local function read(bufnr)
  local state = buffers[bufnr]
  local lines, first = content_lines(bufnr)
  local entries, errors = parse.parse(lines, first)
  local invalid, root = parse.validate(entries, state.root)
  vim.list_extend(errors, invalid)
  return entries, errors, root
end

--- Section titles in bold, and a hint after each path: how many folders a parent adds, where a
--- relative path is, and whether it is missing, a file, a duplicate or new since the last load
local function decorate(bufnr)
  local state = buffers[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local lines, first = content_lines(bufnr)
  guides.draw(bufnr, first, parse.section_of)
  for index, line in ipairs(lines) do
    if parse.section_of(line) then
      local section = parse.section_of(line)
      local lnum = first + index - 2
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, { end_col = #line, hl_group = "StewardSection" })
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
        virt_text = { { "  " .. section.hint, "StewardHint" } },
      })
    end
  end
  local entries = read(bufnr)
  for _, section in ipairs(parse.SECTIONS) do
    for _, item in ipairs(entries[section.key]) do
      local chunks = {}
      local function add(text, hl)
        table.insert(chunks, { "  " .. text, hl })
      end
      if item.duplicate then
        add(section.single and "one code folder only" or "duplicate", "StewardError")
      elseif item.state == "file" then
        add("not a folder", "StewardError")
      elseif item.state == "relative" then
        add("write it ~/... or absolute", "StewardError")
      elseif item.state == "missing" then
        add("missing", section.single and "StewardError" or "StewardWarn")
      elseif section.key == "parents" or section.single then
        add(plural(#paths.children(item.path), "folder"), "StewardCount")
      end
      if section.single and state.code_folder_hint and item.entry == state.code_folder_shown then
        add(state.code_folder_hint, "StewardHint")
      end
      -- Where a path relative to the code folder is
      if not section.single and not item.entry:match("^[/~]") then
        add(home_short(item.path), "StewardHint")
      end
      if item.path and not state.loaded[section.key .. "\0" .. item.path] then
        add("new", "StewardNew")
      end
      vim.api.nvim_buf_set_extmark(bufnr, ns, item.lnum - 1, 0, { virt_text = chunks })
    end
  end
end

local function info(state)
  local chunks = {
    { { "Saved in     ", "StewardKey" }, { home_short(state.code_folder_file), "StewardHint" } },
    { { "             ", "StewardKey" }, { home_short(state.file), "StewardHint" } },
  }
  if state.broken then
    table.insert(chunks, { { "Not read     ", "StewardKey" }, { state.broken, "StewardError" } })
  end
  return chunks
end

--- Fill the buffer from the file (what is saved, dropping any edit)
local function load(bufnr)
  local state = buffers[bufnr]
  local configured = config.options.projects.code_folder
  state.root = paths.code_folder(configured)
  state.file = config.projects_file()
  state.code_folder_file = config.code_folder_file()
  state.code_folder = store.load_code_folder(state.code_folder_file)
  local data, err = store.load(state.file)
  state.broken = err
  data = data or { parents = {}, folders = {}, extra = {} }
  state.extra = data.extra
  -- The code folder as saved; else the one in use, with why it is that one
  if configured then
    state.code_folder_shown = home_short(state.root)
    state.code_folder_hint = "set in setup(): not saved here"
  elseif state.code_folder then
    state.code_folder_shown = state.code_folder
    state.code_folder_hint = nil
  else
    state.code_folder_shown = home_short(state.root)
    state.code_folder_hint = (vim.env.CODE_FOLDER or "") ~= "" and "from $CODE_FOLDER, not saved yet"
      or "guessed, not saved yet"
  end
  data.code_folder = state.code_folder_shown
  state.loaded = { ["code_folder\0" .. state.root] = true }
  for _, section in ipairs(parse.SECTIONS) do
    if not section.single then
      for _, entry in ipairs(data[section.key]) do
        state.loaded[section.key .. "\0" .. paths.resolve(entry, state.root)] = true
      end
    end
  end
  local HEADER = header.new("Project folders", info(state), {
    "\u{f021} Reload",
    function(b)
      M.reload(b)
    end,
  })
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, header.with(HEADER, parse.render(data)))
  header.attach(bufnr, HEADER)
  vim.bo[bufnr].modified = false
  decorate(bufnr)
  if err then
    notify(err .. " (saving replaces it)", vim.log.levels.WARN)
  end
end

--- Save the edited entries: the code folder to its file (and to the tmux server), the rest to
--- projects.json. Nothing is written while anything blocks saving, the code folder included.
function M.save(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffers[bufnr]
  if not state then
    return
  end
  local entries, errors, root = read(bufnr)
  local edited = header.check(bufnr)
  if edited then
    table.insert(errors, 1, edited)
  end
  if #errors > 0 then
    notify("Fix errors before saving:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
    return
  end
  if state.broken then
    local choice = vim.fn.confirm(state.file .. " could not be read. Replace it?", "&Replace\n&Cancel", 2)
    if choice ~= 1 then
      return
    end
  end
  local values = parse.values(entries)
  local saved = { home_short(state.file) }
  if not config.options.projects.code_folder and values.code_folder ~= state.code_folder then
    local ok, err = store.save_code_folder(state.code_folder_file, values.code_folder)
    if not ok then
      notify("could not save " .. state.code_folder_file .. ": " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    require("steward.tmux").set_code_folder(root)
    table.insert(saved, 1, home_short(state.code_folder_file))
  end
  local ok, err = store.save(state.file, { parents = values.parents, folders = values.folders, extra = state.extra })
  if not ok then
    notify("could not save " .. state.file .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  -- Shown as saved: the hints' "new" go, and the cursor stays where it was
  local view = vim.fn.winsaveview()
  load(bufnr)
  vim.fn.winrestview(view)
  notify("saved " .. table.concat(saved, " and "))
end

--- Load the file again, asking first when there are edits
function M.reload(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not buffers[bufnr] then
    return
  end
  if vim.bo[bufnr].modified then
    local choice = vim.fn.confirm("Discard the pending changes and reload?", "&Reload\n&Cancel", 2)
    if choice ~= 1 then
      return
    end
  end
  load(bufnr)
end

--- The section titles' line numbers, in order
local function title_lines(bufnr)
  local lines, first = content_lines(bufnr)
  local result = {}
  for index, line in ipairs(lines) do
    if parse.section_of(line) then
      table.insert(result, first + index - 1)
    end
  end
  return result
end

local function jump(bufnr, direction)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local titles = title_lines(bufnr)
  local target
  for index = direction > 0 and 1 or #titles, direction > 0 and #titles or 1, direction do
    local lnum = titles[index]
    if (direction > 0 and lnum > cursor) or (direction < 0 and lnum < cursor) then
      target = lnum
      break
    end
  end
  if target then
    vim.api.nvim_win_set_cursor(0, { target, 0 })
  end
end

--- The path on the cursor's line, resolved, or nil
local function path_at_cursor(bufnr)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  if lnum <= header.size(bufnr) or vim.trim(line) == "" or parse.section_of(line) then
    return nil
  end
  return paths.resolve(line, buffers[bufnr].root)
end

--- A float listing the folders a parent adds (or the folder itself), closed by q, <Esc> or
--- leaving it
local function preview(bufnr)
  local path = path_at_cursor(bufnr)
  if not path then
    return
  end
  if not paths.is_dir(path) then
    notify(home_short(path) .. " is not a folder", vim.log.levels.WARN)
    return
  end
  local root = buffers[bufnr].root
  local lines = {}
  for _, name in ipairs(paths.children(path)) do
    table.insert(lines, paths.shown(path .. "/" .. name, root))
  end
  if #lines == 0 then
    lines = { "(no folders)" }
  end
  local width = math.min(math.max(40, unpack(vim.tbl_map(vim.fn.strdisplaywidth, lines))) + 2, vim.o.columns - 4)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.6))
  local float = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float, 0, -1, false, lines)
  vim.bo[float].modifiable = false
  vim.bo[float].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(float, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. home_short(path) .. " ",
    title_pos = "center",
  })
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
    vim.keymap.set("n", key, close, { buffer = float, nowait = true, silent = true })
  end
  vim.api.nvim_create_autocmd("WinLeave", { buffer = float, once = true, callback = vim.schedule_wrap(close) })
end

--- Where the completed folder starts (0-based): after the indent
local function completion_start(line)
  return #(line:match("^%s*") or "")
end

--- The folders the cursor's line can be (relative paths under the code folder, or any folder
--- once it starts with / or ~), nil on a section title
local function line_choices(bufnr, lnum)
  local state = buffers[bufnr]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  if not state or not state.root or lnum <= header.size(bufnr) or parse.section_of(line) then
    return nil
  end
  local base = line:sub(completion_start(line) + 1, vim.api.nvim_win_get_cursor(0)[2])
  local absolute = base:sub(1, 1) == "/" or base:sub(1, 1) == "~"
  local query = absolute and base or (state.root .. "/" .. base)
  local result = {}
  for _, match in ipairs(vim.fn.getcompletion(query, "dir")) do
    local word = absolute and match or match:sub(#state.root + 2)
    if word ~= "" then
      table.insert(result, { word = word, menu = "folder" })
    end
  end
  return result
end

local function setup_keymaps(bufnr)
  local function map(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, fn, { buffer = bufnr, silent = true, nowait = true, desc = "Steward: " .. desc })
  end
  send.map(bufnr, function()
    M.save(bufnr)
  end, "Save the code folder and projects.json")
  map("n", "<leader>R", function()
    M.reload(bufnr)
  end, "Reload the code folder and projects.json")
  choices.map(bufnr)
  map("n", "<CR>", function()
    local action = header.action(bufnr, vim.api.nvim_win_get_cursor(0)[1])
    if action then
      action(bufnr)
    else
      preview(bufnr)
    end
  end, "Folders this line adds")
  map("n", "gf", function()
    local path = path_at_cursor(bufnr)
    if path then
      vim.cmd.edit(vim.fn.fnameescape(path))
    end
  end, "Open the folder")
  map("n", "}", function()
    jump(bufnr, 1)
  end, "Next section")
  map("n", "{", function()
    jump(bufnr, -1)
  end, "Previous section")
  for index = 1, #parse.SECTIONS do
    map("n", "g" .. index, function()
      local lnum = title_lines(bufnr)[index]
      if lnum then
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      end
    end, "Go to " .. parse.SECTIONS[index].title)
  end
end

local function setup_autocmds(bufnr)
  local group = vim.api.nvim_create_augroup("steward_projects_" .. bufnr, { clear = true })
  send.ignore_write(bufnr, group)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      decorate(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      buffers[bufnr] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

local function first_entry_line(bufnr)
  local lines, first = content_lines(bufnr)
  for index, line in ipairs(lines) do
    if vim.trim(line) ~= "" and not parse.section_of(line) then
      return first + index - 1
    end
  end
  return title_lines(bufnr)[1] or first
end

--- Open the screen (or go to it, when it is open; reload it, when it is the current buffer)
function M.open()
  for bufnr in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      if bufnr == vim.api.nvim_get_current_buf() then
        M.reload(bufnr)
      else
        vim.api.nvim_win_set_buf(0, bufnr)
      end
      return bufnr
    end
  end
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, NAME)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "steward-projects"
  guides.setup_buffer(bufnr, function(b)
    return header.size(b) + 1
  end, parse.section_of)
  choices.attach(bufnr, { choices = line_choices, start = completion_start })
  buffers[bufnr] = { loaded = {} }
  setup_keymaps(bufnr)
  setup_autocmds(bufnr)
  vim.api.nvim_win_set_buf(0, bufnr)
  load(bufnr)
  vim.api.nvim_win_set_cursor(0, { first_entry_line(bufnr), 0 })
  return bufnr
end

return M
