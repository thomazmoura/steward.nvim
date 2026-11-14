-- The projects screen's text, both ways: the lines it shows for projects.json (render) and the
-- entries read back from the edited lines (parse), with what blocks a save (validate).
--
--   Parent directories            a section title, as rendered (case aside)
--     clients                     one path a line, indented
--     ~/work
--
--   Individual directories
--     ~/notes
local M = {}

local paths = require("steward.paths")

M.SECTIONS = {
  { key = "parents", title = "Parent directories", hint = "their folders are listed" },
  { key = "folders", title = "Individual directories", hint = "listed themselves" },
}

local INDENT = "  "

--- The section a line is the title of, or nil
---@param line string
---@return table|nil
function M.section_of(line)
  local text = vim.trim(line):lower()
  for _, section in ipairs(M.SECTIONS) do
    if text == section.title:lower() then
      return section
    end
  end
end

--- The screen's lines for `data` ({ parents, folders }), sections in order, a blank line between
---@param data table
---@return string[]
function M.render(data)
  local lines = {}
  for index, section in ipairs(M.SECTIONS) do
    if index > 1 then
      table.insert(lines, "")
    end
    table.insert(lines, section.title)
    for _, entry in ipairs(data[section.key] or {}) do
      table.insert(lines, INDENT .. entry)
    end
  end
  return lines
end

--- A typed path as it is saved: trimmed, trailing slashes dropped (but for /)
local function clean(text)
  local entry = vim.trim(text)
  if #entry > 1 then
    entry = entry:gsub("/+$", "")
  end
  return entry
end

--- The entries of the edited lines: { parents = { { entry, lnum } }, folders = ... } and the
--- errors that block saving. `first` is the buffer line number of lines[1].
---@param lines string[]
---@param first number|nil
---@return table entries
---@return string[] errors
function M.parse(lines, first)
  first = first or 1
  local entries = { parents = {}, folders = {} }
  local errors = {}
  local seen_sections = {}
  local current
  for index, line in ipairs(lines) do
    local lnum = first + index - 1
    local section = M.section_of(line)
    if section then
      if seen_sections[section.key] then
        table.insert(errors, ("Line %d: a second %q title"):format(lnum, section.title))
      end
      seen_sections[section.key] = true
      current = section
    elseif vim.trim(line) ~= "" then
      if current then
        table.insert(entries[current.key], { entry = clean(line), lnum = lnum })
      else
        table.insert(errors, ("Line %d: not under a section title"):format(lnum))
      end
    end
  end
  for _, section in ipairs(M.SECTIONS) do
    if not seen_sections[section.key] then
      table.insert(errors, ("The %q title is missing: put it back, or <leader>R reloads"):format(section.title))
    end
  end
  return entries, errors
end

--- What each entry's path is, for the screen's hints and the save: entries gain `path` (resolved)
--- and `state` ("folder", "missing" or "file"); returns the errors that block saving
---@param entries table From M.parse
---@param root string The code folder
---@return string[] errors
function M.validate(entries, root)
  local errors = {}
  for _, section in ipairs(M.SECTIONS) do
    local seen = {}
    for _, item in ipairs(entries[section.key]) do
      item.path = paths.resolve(item.entry, root)
      local stat = (vim.uv or vim.loop).fs_stat(item.path)
      item.state = not stat and "missing" or (stat.type == "directory" and "folder" or "file")
      if item.state == "file" then
        table.insert(errors, ("Line %d: %s is a file, not a folder"):format(item.lnum, item.entry))
      end
      if section.key == "parents" and item.path == root then
        item.duplicate = true
        table.insert(errors, ("Line %d: the code folder is always a parent"):format(item.lnum))
      elseif seen[item.path] then
        item.duplicate = true
        table.insert(errors, ("Line %d: %s is already on line %d"):format(item.lnum, item.entry, seen[item.path]))
      else
        seen[item.path] = item.lnum
      end
    end
  end
  return errors
end

--- The entries' texts, by section: what projects.json is written with
---@param entries table
---@return table { parents = string[], folders = string[] }
function M.values(entries)
  local values = {}
  for _, section in ipairs(M.SECTIONS) do
    values[section.key] = vim.tbl_map(function(item)
      return item.entry
    end, entries[section.key])
  end
  return values
end

return M
