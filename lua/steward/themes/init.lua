-- The themes screen (:Steward themes): themes.json as an editable buffer, in the style of the
-- projects screen.
--
--   Tmux themes                                                     Reload
--   Saved in     ~/.config/dev-environment/themes.json
--   ─────────────────────────── ◇ ───────────────────────────
--   Themes   a name and its #rrggbb accent colour
--   ├─ moon: #00abab  ██  used by 1
--   └─ gold: #ffb86c  ██  unused
--
--   Assignments   default, default (ssh|docker), Directory, SessionName, Directory@Host, SessionName@Host
--   ├─ default: moon  ██  fallback
--   ├─ ApolloEnv: gold  ██  named session              (a prefix+$ label, or a session's name)
--   ├─ clients/acme: gold  ██  path-based session
--   └─ ~/later: gold  ██  path-based session (missing)  muted: no effect until it exists
--
-- dev-environment's tmux draws each session's bar in the theme its most specific key picks (see
-- parse.lua for the keys). Adding, changing and removing a theme or an assignment is editing the
-- text; <leader><leader> saves, and then runs dev-environment's Set-SessionTheme.sh -g -a, which
-- draws every open session in its new colour at once. While there is no file, steward's defaults
-- (defaults/themes.json) are shown, and saving writes them.
local M = {}

local choices = require("steward.ui.choices")
local config = require("steward.config")
local guides = require("steward.ui.guides")
local header = require("steward.ui.header")
local parse = require("steward.themes.parse")
local paths = require("steward.paths")
local send = require("steward.ui.send")
local store = require("steward.store")

local NAME = "Steward|themes"
local ns = vim.api.nvim_create_namespace("steward_themes")

-- Buffer -> { root, file, loaded = { [section\0id] = true }, extra, broken, defaults }
local buffers = {}

local function notify(message, level)
  vim.notify("Steward: " .. message, level or vim.log.levels.INFO)
end

local function home_short(path)
  return (vim.fn.fnamemodify(path, ":~"))
end

local function content_lines(bufnr)
  local size = header.size(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, size, -1, false), size + 1
end

--- The highlight group drawing text in `color` (#rrggbb), defined the first time it is asked for
local swatches = {}
local function swatch(color)
  local group = "StewardSwatch_" .. color:sub(2)
  if not swatches[group] then
    vim.api.nvim_set_hl(0, group, { fg = color })
    swatches[group] = color
  end
  return group
end

-- A colorscheme clears the groups: define them again
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("steward_themes_swatches", { clear = true }),
  callback = function()
    for group, color in pairs(swatches) do
      vim.api.nvim_set_hl(0, group, { fg = color })
    end
  end,
})

--- Every name a SessionName key can match, as parse.validate takes them: local sessions by name
--- and by prefix+$ label (dev-environment's Set-SessionLabel.sh), and ssh/Docker ones as
--- name@host, with their whole target or only its host. Asked of tmux once per load.
local function known_names()
  local names = {}
  local function remote(name, target)
    if name ~= "" and target ~= "" then
      names[name .. "@" .. target] = true
      names[name .. "@" .. target:gsub("^.*@", "")] = true
    end
  end
  for _, label in ipairs(require("steward.tmux").labels()) do
    if label.target == "" then
      names[label.label] = true
    else
      remote(label.label, label.target)
    end
  end
  for _, session in ipairs(require("steward.tmux").sessions()) do
    if session.target == "" then
      names[session.name] = true
    else
      remote(session.name, session.target)
      remote(session.ssh_name, session.target)
    end
  end
  return names
end

--- The entries of the buffer as edited, checked: entries, errors
local function read(bufnr)
  local state = buffers[bufnr]
  local lines, first = content_lines(bufnr)
  local entries, errors = parse.parse(lines, first)
  vim.list_extend(errors, parse.validate(entries, state.root, state.names))
  return entries, errors
end

--- Section titles in bold, and hints after each line: the colour's swatch, how many assignments
--- use a theme, what session a key is about, and errors and "new" as on the projects screen
local function decorate(bufnr)
  local state = buffers[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local lines, first = content_lines(bufnr)
  guides.draw(bufnr, first, parse.section_of)
  for index, line in ipairs(lines) do
    local section = parse.section_of(line)
    local lnum = first + index - 2
    if section then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, { end_col = #line, hl_group = "StewardSection" })
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, { virt_text = { { "  " .. section.hint, "StewardHint" } } })
    else
      -- The key (or a theme's name) in its own colour, up to the ":"
      local indent, key, _, colon = parse.split(line)
      if key and key ~= "" then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, indent, { end_col = colon - 1, hl_group = "StewardKey" })
      end
    end
  end
  local entries = read(bufnr)
  local function put(item, chunks)
    vim.api.nvim_buf_set_extmark(bufnr, ns, item.lnum - 1, 0, { virt_text = chunks })
  end
  local function add(chunks, text, hl)
    table.insert(chunks, { "  " .. text, hl })
  end
  for _, theme in ipairs(entries.themes) do
    local chunks = {}
    if theme.valid then
      add(chunks, "██", swatch(theme.valid))
    else
      add(chunks, "not #rrggbb", "StewardError")
    end
    if theme.duplicate then
      add(chunks, "duplicate", "StewardError")
    elseif theme.uses > 0 then
      add(chunks, "used by " .. theme.uses, "StewardCount")
    else
      add(chunks, "unused", "StewardHint")
    end
    if not state.loaded["themes\0" .. theme.name] then
      add(chunks, "new", "StewardNew")
    end
    put(theme, chunks)
  end
  for _, item in ipairs(entries.assignments) do
    local chunks = {}
    if item.color then
      add(chunks, "██", swatch(item.color))
    elseif item.unknown then
      add(chunks, "no such theme", "StewardError")
    end
    local kind, idle = parse.describe(item)
    add(chunks, kind, idle and "StewardMuted" or "StewardKind")
    if item.duplicate then
      add(chunks, "duplicate", "StewardError")
    elseif item.state == "file" then
      add(chunks, "not a folder", "StewardError")
    elseif item.error and not item.unknown then
      add(chunks, "invalid key", "StewardError")
    end
    -- Where a directory relative to the code folder is
    if item.path and not item.subject:match("^[/~]") then
      add(chunks, home_short(item.path), "StewardHint")
    end
    if not state.loaded["assignments\0" .. item.key] then
      add(chunks, "new", "StewardNew")
    end
    put(item, chunks)
  end
end

local function info(state)
  local chunks = {
    { { "Saved in     ", "StewardKey" }, { home_short(state.file), "StewardHint" } },
  }
  if state.defaults then
    table.insert(chunks, {
      { "Not saved    ", "StewardKey" },
      { "showing steward's defaults; saving writes them", "StewardWarn" },
    })
  end
  if state.broken then
    table.insert(chunks, { { "Not read     ", "StewardKey" }, { state.broken, "StewardError" } })
  end
  return chunks
end

--- The defaults steward ships, or an empty list with just a default when they cannot be read
local function defaults()
  local data = store.load_themes(config.default_themes_file())
  return data or { themes = { { name = "moon", color = "#00abab" } }, assignments = { { match = "default", theme = "moon" } } }
end

--- Fill the buffer from the file (what is saved, dropping any edit), or the defaults without one
local function load(bufnr)
  local state = buffers[bufnr]
  state.root = paths.code_folder(config.options.projects.code_folder)
  state.file = config.themes_file()
  state.names = known_names()
  local data, missing, err = store.load_themes(state.file)
  state.broken = err
  state.defaults = missing
  state.extra = data and data.extra or {}
  data = data or defaults()
  state.loaded = {}
  for _, theme in ipairs(data.themes) do
    state.loaded["themes\0" .. theme.name] = true
  end
  for _, assignment in ipairs(data.assignments) do
    state.loaded["assignments\0" .. assignment.match] = true
  end
  local HEADER = header.new("Tmux themes", info(state), {
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

--- Save the edited themes and assignments to themes.json
function M.save(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffers[bufnr]
  if not state then
    return
  end
  local entries, errors = read(bufnr)
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
  values.extra = state.extra
  local ok, err = store.save_themes(state.file, values)
  if not ok then
    notify("could not save " .. state.file .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  local view = vim.fn.winsaveview()
  load(bufnr)
  vim.fn.winrestview(view)
  local saved = "saved " .. home_short(state.file)
  local started = require("steward.tmux").apply_themes(config.options.themes.apply, function(ok)
    if ok then
      notify(saved .. "; the tmux sessions are in their new colours")
    else
      notify(saved .. ", but tmux could not be updated (prefix+u, or the next session switch, does it)",
        vim.log.levels.WARN)
    end
  end)
  if not started then
    notify(saved .. " (tmux picks it up on the next session switch, or prefix+u)")
  end
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

--- The section the cursor's line is in (the last title above it), or nil
local function section_at_cursor(bufnr)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, header.size(bufnr), lnum, false)
  for index = #lines, 1, -1 do
    local section = parse.section_of(lines[index])
    if section then
      return section
    end
  end
end

--- What a key can be, for completion: { word, menu } in this order: default, the connection
--- defaults (default (ssh), default (docker)), the tmux
--- sessions (local ones by name, ssh/Docker ones as name@target and folder@target), then the
--- folders the session pickers offer (the code folder's and what projects.json adds), as the
--- projects screen shows them. Keys already assigned are left out. A folder shown with no / is
--- written ./name, so it does not read as a session name.
---@param bufnr number
---@return table[]
function M.key_candidates(bufnr)
  local state = buffers[bufnr]
  if not state then
    return {}
  end
  local used = {}
  local entries = parse.parse((content_lines(bufnr)))
  for _, item in ipairs(entries.assignments) do
    used[item.key] = true
  end
  local candidates, seen = {}, {}
  local function add(word, menu)
    if word ~= "" and not used[word] and not seen[word] then
      seen[word] = true
      table.insert(candidates, { word = word, menu = menu })
    end
  end
  add("default", "fallback")
  for _, connection in ipairs(parse.CONNECTIONS) do
    add("default (" .. connection.name .. ")", "fallback for " .. connection.label .. " sessions")
  end
  for _, label in ipairs(require("steward.tmux").labels()) do
    if not label.label:find("[/@]") then
      if label.target == "" then
        add(label.label, "named session")
      else
        add(label.label .. "@" .. label.target, "named session on a host")
      end
    end
  end
  for _, session in ipairs(require("steward.tmux").sessions()) do
    if session.target == "" then
      -- A name with a / or an @ cannot be written as a SessionName key
      if not session.name:find("[/@]") and session.name:sub(1, 1) ~= "~" then
        add(session.name, "session")
      end
    else
      local name = session.ssh_name ~= "" and session.ssh_name or session.name
      if not name:find("[/@]") then
        add(name .. "@" .. session.target, "ssh session")
      end
      if session.dir:sub(1, 1) == "/" then
        add(session.dir .. "@" .. session.target, "ssh folder")
      end
    end
  end
  local projects = store.load(config.projects_file()) or { parents = {}, folders = {} }
  for _, path in ipairs(paths.projects(state.root, projects)) do
    local shown = paths.shown(path, state.root)
    if parse.key_kind(shown) ~= "directory" then
      shown = "./" .. shown
    end
    add(shown, "folder")
  end
  return candidates
end

--- Where the completed text of the cursor's line starts (0-based): the key, from the indent, until
--- the text before the cursor has a ": "; the theme, after it, once it has
local function completion_start(line)
  local before = line:sub(1, vim.api.nvim_win_get_cursor(0)[2])
  local indent = #(before:match("^%s*") or "")
  local after = before:sub(indent + 1):match(".*:%s+()")
  return after and indent + after - 1 or indent
end

--- What the cursor's line offers, in Assignments (nil elsewhere): a key (see M.key_candidates,
--- and any folder once the key starts with / or ~), or a theme's name after the key
local function line_choices(bufnr, lnum)
  local section = buffers[bufnr] and section_at_cursor(bufnr)
  if not (section and section.key == "assignments") then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  local start = completion_start(line)
  if start > #(line:match("^%s*") or "") then
    local result = {}
    for _, theme in ipairs(parse.parse((content_lines(bufnr))).themes) do
      table.insert(result, { word = theme.name, menu = theme.color })
    end
    return result
  end
  local result = M.key_candidates(bufnr)
  -- Any folder, by path
  local base = line:sub(start + 1, vim.api.nvim_win_get_cursor(0)[2])
  local first = base:sub(1, 1)
  if first == "/" or first == "~" then
    local listed = {}
    for _, candidate in ipairs(result) do
      listed[candidate.word] = true
    end
    for _, folder in ipairs(vim.fn.getcompletion(base, "dir")) do
      folder = #folder > 1 and folder:gsub("/+$", "") or folder
      if not listed[folder] then
        listed[folder] = true
        table.insert(result, { word = folder, menu = "folder" })
      end
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
  end, "Save themes.json")
  map("n", "<leader>R", function()
    M.reload(bufnr)
  end, "Reload themes.json")
  map("n", "<CR>", function()
    local action = header.action(bufnr, vim.api.nvim_win_get_cursor(0)[1])
    if action then
      action(bufnr)
    end
  end, "Run the header's action")
  choices.map(bufnr)
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
  local group = vim.api.nvim_create_augroup("steward_themes_" .. bufnr, { clear = true })
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
  vim.bo[bufnr].filetype = "steward-themes"
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
