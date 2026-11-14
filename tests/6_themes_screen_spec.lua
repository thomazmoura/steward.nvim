-- The themes screen end to end, headless
local function fresh()
  for name in pairs(package.loaded) do
    if name == "steward" or name:match("^steward%.") then
      package.loaded[name] = nil
    end
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(bufnr):match("Steward|themes$") then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  dofile(T.root .. "/plugin/steward.lua")
  return require("steward")
end

local function file()
  return T.dir .. "/config/dev-environment/themes.json"
end

local function content(bufnr)
  local size = require("steward.ui.header").size(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, size, -1, false)
end

T.test("with no file it shows the defaults, unmodified, and saving writes them", function()
  T.mkdirs("code")
  local bufnr = fresh().themes()
  local lines = content(bufnr)
  T.eq(lines[1], "Themes")
  T.ok(vim.tbl_contains(lines, "   moon: #00abab"), vim.inspect(lines))
  T.eq(lines[#lines], "   default: moon")
  T.eq(vim.bo[bufnr].modified, false)
  T.eq(T.read(file()), nil)
  require("steward.themes").save(bufnr)
  local saved = vim.json.decode(T.read(file()))
  T.eq(#saved.themes, 11)
  T.eq(saved.assignments, { { match = "default", theme = "moon" } })
end)

T.test("an edit is saved, unknown keys kept", function()
  T.mkdirs("code/acme")
  T.write(file(), vim.json.encode({
    themes = { { name = "moon", color = "#00abab" } },
    assignments = { { match = "default", theme = "moon" } },
    theirs = true,
  }))
  local bufnr = fresh().themes()
  T.eq(content(bufnr), { "Themes", "   moon: #00abab", "", "Assignments", "   default: moon" })
  local size = require("steward.ui.header").size(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, size + 2, size + 2, false, { "   gold: FFB86C" })
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "   acme/: gold", "   ApolloEnv@prod:   gold", "   Proj@docker:x: gold" })
  require("steward.themes").save(bufnr)
  local saved = vim.json.decode(T.read(file()))
  T.eq(saved.themes, { { name = "moon", color = "#00abab" }, { name = "gold", color = "#ffb86c" } })
  T.eq(saved.assignments, {
    { match = "default", theme = "moon" },
    { match = "acme", theme = "gold" },
    { match = "ApolloEnv@prod", theme = "gold" },
    { match = "Proj@docker:x", theme = "gold" },
  })
  T.eq(saved.theirs, true)
  T.eq(vim.bo[bufnr].modified, false)
end)

T.test("errors leave the file alone", function()
  T.mkdirs("code")
  T.write(file(), '{"themes": [{"name": "moon", "color": "#00abab"}], "assignments": [{"match": "default", "theme": "moon"}]}')
  local before = T.read(file())
  local bufnr = fresh().themes()
  local messages = {}
  vim.notify = function(message)
    table.insert(messages, message)
  end
  -- Removing the theme the default uses
  local size = require("steward.ui.header").size(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, size + 1, size + 2, false, {})
  require("steward.themes").save(bufnr)
  T.eq(T.read(file()), before)
  T.ok(messages[1]:find("no theme is called moon", 1, true), messages[1])
  vim.cmd("silent! write")
  T.eq(T.read(file()), before)
end)

T.test(":Steward themes opens the screen", function()
  T.mkdirs("code")
  fresh()
  vim.cmd("Steward themes")
  T.ok(vim.api.nvim_buf_get_name(0):match("Steward|themes$"))
  T.eq(vim.bo.filetype, "steward-themes")
end)

T.test("keys complete to sessions and the pickers' folders", function()
  T.mkdirs("code/acme", "code/tools", "code/.hidden", "clients/x", "notes")
  T.write(T.dir .. "/config/dev-environment/projects.json",
    vim.json.encode({ parents = { T.dir .. "/clients" }, folders = { T.dir .. "/notes" } }))
  T.write(file(), '{"themes": [{"name": "moon", "color": "#00abab"}], "assignments": [{"match": "default", "theme": "moon"}, {"match": "./tools", "theme": "moon"}]}')
  local steward = fresh()
  require("steward.tmux").sessions = function()
    return {
      { name = "ApolloEnv", path = "/x", target = "", dir = "", ssh_name = "" },
      { name = "me@box", path = "/", target = "me@prod", dir = "/srv/app", ssh_name = "box" },
    }
  end
  local bufnr = steward.themes()
  local words = vim.tbl_map(function(candidate)
    return candidate.word
  end, require("steward.themes").key_candidates(bufnr))
  T.eq(words, {
    "ApolloEnv",
    "box@me@prod",
    "/srv/app@me@prod",
    -- In the pickers' order: by what is shown, ignoring case
    T.dir .. "/clients/x",
    T.dir .. "/notes",
    "./acme",
  })
  -- What is offered while typing "ap": starting with it first, then containing it
  local choices = require("steward.ui.choices")
  -- The cursor after the last character, as in insert mode
  vim.wo.virtualedit = "onemore"
  local function words(completion)
    return vim.tbl_map(choices.word, completion.matches)
  end
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "  ap" })
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(bufnr), 4 })
  local completion = choices.choice_completion()
  T.eq(completion.start, 2)
  T.eq(completion.base, "ap")
  T.eq(vim.list_slice(words(completion), 1, 2), { "ApolloEnv", "/srv/app@me@prod" })
  -- After the key, theme names, with their colour
  vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, { "   ApolloEnv: m" })
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(bufnr), 15 })
  completion = choices.choice_completion()
  T.eq(completion.start, 14)
  T.eq(completion.matches, { { word = "moon", menu = "#00abab" } })
  -- A key starting with / completes any folder
  local typed = T.dir .. "/not"
  vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, { "  " .. typed })
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(bufnr), 2 + #typed })
  T.eq(words(choices.choice_completion()), { T.dir .. "/notes" })
  -- Nothing outside Assignments, so the usual completion applies there
  vim.api.nvim_win_set_cursor(0, { require("steward.ui.header").size(bufnr) + 2, 0 })
  T.eq(choices.choice_completion(), nil)
  vim.wo.virtualedit = ""
end)

T.test("lines are indented under their section, guides drawn over it, keys highlighted", function()
  local guides = require("steward.ui.guides")
  local parse = require("steward.themes.parse")
  T.eq(guides.compute({ "Themes", "   a: #000000", "   b: #111111", "", "Assignments", "   default: a" }, parse.section_of),
    { [2] = "├─ ", [3] = "└─ ", [6] = "└─ " })
  T.mkdirs("code")
  T.write(file(), '{"themes": [{"name": "moon", "color": "#00abab"}], "assignments": [{"match": "default", "theme": "moon"}]}')
  local bufnr = fresh().themes()
  T.eq(vim.bo[bufnr].shiftwidth, 3)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("steward_guides"), 0, -1, { details = true })
  T.eq(#marks, 2)
  T.eq(marks[1][4].virt_text[1][1], "└─ ")
  local size = require("steward.ui.header").size(bufnr)
  local keys = vim.tbl_filter(function(mark)
    return mark[4].hl_group == "StewardKey"
  end, vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("steward_themes"), { size, 0 }, -1, { details = true }))
  T.eq(vim.tbl_map(function(mark)
    return { mark[3], mark[4].end_col }
  end, keys), { { 3, 7 }, { 3, 10 } })
end)

T.test("a prefix+$ label is a named session, offered and recognised", function()
  T.mkdirs("code")
  T.write(T.dir .. "/cache/tmux/session-names",
    "dev-environment\tApolloEnv\t\t/x/dev-environment\nwork-x\tAbelha\tme@work\t/y\n")
  T.write(file(), '{"themes": [{"name": "moon", "color": "#00abab"}], "assignments": [{"match": "default", "theme": "moon"}, {"match": "ApolloEnv", "theme": "moon"}, {"match": "Ghost", "theme": "moon"}]}')
  local bufnr = fresh().themes()
  local words = vim.tbl_map(function(candidate)
    return candidate.word
  end, require("steward.themes").key_candidates(bufnr))
  T.eq(words, { "Abelha@me@work" }, "ApolloEnv and default are assigned already")
  local hints = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("steward_themes"), 0, -1, { details = true })) do
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      hints[vim.trim(chunk[1])] = chunk[2]
    end
  end
  T.eq(hints["named session"], "StewardKind")
  T.eq(hints["named session (no such name)"], "StewardMuted")
end)
