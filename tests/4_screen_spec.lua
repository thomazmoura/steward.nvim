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

T.test("opens on the file's entries below a read-only header", function()
  T.mkdirs("code/a", "code/clients/x", "code/clients/y")
  T.write(file(), '{"parents": ["clients"], "folders": ["~/notes"]}')
  local bufnr = fresh().projects()
  T.eq(content(bufnr), { "Parent directories", "  clients", "", "Individual directories", "  ~/notes" })
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
  local size = require("steward.ui.header").size(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, size + 1, size + 1, false, { "  clients" })
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
  T.eq(content(bufnr), { "Parent directories", "", "Individual directories" })
  require("steward.projects").save(bufnr)
  T.eq(vim.json.decode(T.read(file())), { version = 1, parents = {}, folders = {} })
end)
