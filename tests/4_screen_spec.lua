-- The screen end to end, headless: open, edit as text, save, and what the file then holds
local function fresh()
  for name in pairs(package.loaded) do
    if name == "steward" or name:match("^steward%.") then
      package.loaded[name] = nil
    end
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(bufnr):match("Steward|projects$") then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  dofile(T.root .. "/plugin/steward.lua")
  return require("steward")
end

local function file()
  return T.dir .. "/config/dev-environment/projects.json"
end

local function content(bufnr)
  local size = require("steward.ui.header").size(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, size, -1, false)
end

local function code_folder_file()
  return T.dir .. "/config/dev-environment/code-folder"
end

--- The line number of a section's title
local function title(bufnr, text)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line == text then
      return index
    end
  end
  error("no " .. text .. " title")
end

--- The code folder section as the screen shows `path`
local function code_section(path)
  return { "Code folder", "   " .. path, "" }
end

local function messages_of(fn)
  local messages = {}
  local notify = vim.notify
  vim.notify = function(message)
    table.insert(messages, message)
  end
  fn()
  vim.notify = notify
  return messages
end

T.test("opens on the file's entries below a read-only header", function()
  T.mkdirs("code/a", "code/clients/x", "code/clients/y")
  T.write(file(), '{"parents": ["clients"], "folders": ["~/notes"]}')
  local bufnr = fresh().projects()
  T.eq(content(bufnr), vim.list_extend(code_section(T.dir .. "/code"),
    { "Parent directories", "   clients", "", "Individual directories", "   ~/notes" }))
  T.eq(vim.bo[bufnr].modified, false)
  T.eq(vim.bo[bufnr].buftype, "acwrite")
  local header = vim.api.nvim_buf_get_lines(bufnr, 0, require("steward.ui.header").size(bufnr), false)
  T.eq(vim.tbl_filter(function(line)
    return line ~= ""
  end, header), {}, "the header is virtual text only")
end)

T.test("an edit saved with save() is in the file, unknown keys kept", function()
  T.mkdirs("code/a", "code/clients/x", "elsewhere")
  T.write(file(), '{"parents": [], "folders": [], "theirs": true}')
  local steward = fresh()
  local bufnr = steward.projects()
  local parents = title(bufnr, "Parent directories")
  vim.api.nvim_buf_set_lines(bufnr, parents, parents, false, { "  clients" })
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "  " .. T.dir .. "/elsewhere/" })
  T.eq(vim.bo[bufnr].modified, true)
  require("steward.projects").save(bufnr)
  local saved = vim.json.decode(T.read(file()))
  T.eq(saved.parents, { "clients" })
  T.eq(saved.folders, { T.dir .. "/elsewhere" })
  T.eq(saved.theirs, true)
  T.eq(vim.bo[bufnr].modified, false)
end)

T.test("errors leave the file alone; :w does nothing", function()
  T.mkdirs("code/a")
  T.write(file(), '{"parents": [], "folders": ["a"]}')
  local before = T.read(file())
  local bufnr = fresh().projects()
  local size = require("steward.ui.header").size(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "  a" })
  vim.cmd("silent write")
  T.eq(T.read(file()), before)
  local messages = {}
  local notify = vim.notify
  vim.notify = function(message)
    table.insert(messages, message)
  end
  require("steward.projects").save(bufnr)
  vim.notify = notify
  T.eq(T.read(file()), before)
  T.ok(messages[1] and messages[1]:find("already on line", 1, true), vim.inspect(messages))
  T.ok(size > 0)
end)

T.test("a missing file opens empty and is created on save", function()
  T.mkdirs("code/a")
  local bufnr = fresh().projects()
  T.eq(content(bufnr), vim.list_extend(code_section(T.dir .. "/code"), { "Parent directories", "", "Individual directories" }))
  require("steward.projects").save(bufnr)
  T.eq(vim.json.decode(T.read(file())), { version = 1, parents = {}, folders = {} })
  T.eq(T.read(code_folder_file()), T.dir .. "/code\n", "the code folder in use, saved")
end)

T.test("typing a folder offers those under the code folder, as you type", function()
  T.mkdirs("code/clients/x", "code/clutter", "code/tools")
  T.write(file(), '{"parents": [], "folders": []}')
  local bufnr = fresh().projects()
  local choices = require("steward.ui.choices")
  local parents = title(bufnr, "Parent directories")
  -- The cursor after the last character, as in insert mode
  vim.wo.virtualedit = "onemore"
  vim.api.nvim_buf_set_lines(bufnr, parents, parents, false, { "  cl" })
  vim.api.nvim_win_set_cursor(0, { parents + 1, 4 })
  local completion = choices.choice_completion()
  T.eq(completion.start, 2)
  T.eq(completion.matches, { { word = "clients/", menu = "folder" }, { word = "clutter/", menu = "folder" } })
  -- Nothing on a section title
  vim.api.nvim_win_set_cursor(0, { parents, 0 })
  T.eq(choices.choice_completion(), nil)
  vim.wo.virtualedit = ""
  -- Insert mode picks an engine (the native menu without blink.cmp) and types without errors
  vim.api.nvim_win_set_cursor(0, { parents + 1, 4 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A<Esc>", true, false, true), "x", false)
  T.eq(vim.bo[bufnr].completeopt, "menuone,noselect")
end)

T.test("a new line under a section is indented one level, a line typed at the start goes under it", function()
  T.mkdirs("code/clients")
  T.write(file(), '{"parents": [], "folders": []}')
  local bufnr = fresh().projects()
  local parents = title(bufnr, "Parent directories")
  -- o on the "Parent directories" title, which is not indented itself
  vim.api.nvim_win_set_cursor(0, { parents, 0 })
  vim.api.nvim_feedkeys("oclients\27", "xt", false)
  T.eq(vim.api.nvim_buf_get_lines(bufnr, parents, parents + 1, false), { "   clients" })
  -- A path typed at the start of a line is put under its section on leaving insert mode
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(bufnr), 0 })
  vim.api.nvim_feedkeys("i~/notes\27", "xt", false)
  local lines = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)
  T.eq(lines, { "   ~/notes" })
  -- A title stays where it is
  T.eq(vim.api.nvim_buf_get_lines(bufnr, parents - 1, parents, false), { "Parent directories" })
end)

T.test("the code folder is edited as text and saved to its own file, not projects.json", function()
  T.mkdirs("code/a", "other/clients/x")
  T.write(file(), '{"parents": ["clients"], "folders": []}')
  T.write(code_folder_file(), T.dir .. "/code\n")
  local bufnr = fresh().projects()
  local code = title(bufnr, "Code folder") + 1
  vim.api.nvim_buf_set_lines(bufnr, code - 1, code, false, { "   " .. T.dir .. "/other/" })
  require("steward.projects").save(bufnr)
  T.eq(T.read(code_folder_file()), T.dir .. "/other\n")
  local saved = vim.json.decode(T.read(file()))
  T.eq(saved, { version = 1, parents = { "clients" }, folders = {} }, "no code folder in projects.json")
  T.eq(vim.bo[bufnr].modified, false)
  -- Shown again from the file, relative entries now under it
  T.eq(content(bufnr)[2], "   " .. T.dir .. "/other")
  T.eq(require("steward.paths").code_folder(), T.dir .. "/other")
end)

T.test("an invalid code folder blocks saving: neither file is written", function()
  T.mkdirs("code/a")
  T.write(T.dir .. "/a-file", "")
  T.write(file(), '{"parents": [], "folders": []}')
  T.write(code_folder_file(), T.dir .. "/code\n")
  local projects_before, code_before = T.read(file()), T.read(code_folder_file())
  local bufnr = fresh().projects()
  local code = title(bufnr, "Code folder") + 1
  local parents = title(bufnr, "Parent directories")
  vim.api.nvim_buf_set_lines(bufnr, parents, parents, false, { "   a" })
  for _, case in ipairs({
    { { "   " .. T.dir .. "/nowhere" }, "does not exist" },
    { { "   " .. T.dir .. "/a-file" }, "is a file" },
    { { "   code" }, "~/... or absolute" },
    { {}, "empty" },
  }) do
    local current = title(bufnr, "Code folder") + 1
    local remove = vim.api.nvim_buf_get_lines(bufnr, current - 1, current, false)[1] ~= "" and 1 or 0
    vim.api.nvim_buf_set_lines(bufnr, current - 1, current - 1 + remove, false, case[1])
    local messages = messages_of(function()
      require("steward.projects").save(bufnr)
    end)
    T.ok(messages[1] and messages[1]:find(case[2], 1, true), case[2] .. ": " .. vim.inspect(messages))
    T.eq(T.read(file()), projects_before)
    T.eq(T.read(code_folder_file()), code_before)
    T.eq(vim.bo[bufnr].modified, true)
  end
  T.ok(code > 0)
end)

T.test("a code folder set in setup() is shown and not saved", function()
  T.mkdirs("code/a", "other")
  local steward = fresh()
  steward.setup({ projects = { code_folder = T.dir .. "/other" } })
  local bufnr = steward.projects()
  T.eq(content(bufnr)[2], "   " .. T.dir .. "/other")
  require("steward.projects").save(bufnr)
  T.eq(T.read(code_folder_file()), nil)
end)
