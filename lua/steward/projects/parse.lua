-- The projects screen's text, both ways: the lines it shows for the code folder and
-- projects.json (render) and the entries read back from the edited lines (parse), with what
-- blocks a save (validate).
--
--   Code folder                   the one folder everything else is relative to (saved apart,
--      /Git                       in the code-folder file): ~/... or absolute, and it must exist
--
--   Parent directories            a section title, as rendered (case aside)
--      clients                    one path a line, indented one level (the screen draws tree
--      ~/work                     guides over the indentation: ├─ clients, └─ ~/work)
--
--   Individual directories
--      ~/notes
local M = {}

local paths = require("steward.paths")

M.SECTIONS = {
  { key = "code_folder", title = "Code folder", hint = "where the projects are", single = true },
  { key = "parents", title = "Parent directories", hint = "their folders are listed" },
  { key = "folders", title = "Individual directories", hint = "listed themselves" },
}

local INDENT = require("steward.ui.guides").prefix(1)

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

--- The screen's lines for `data` ({ code_folder, parents, folders }), sections in order, a blank
--- line between
---@param data table
---@return string[]
function M.render(data)
  local lines = {}
  for index, section in ipairs(M.SECTIONS) do
    if index > 1 then
      table.insert(lines, "")
    end
    table.insert(lines, section.title)
    local value = data[section.key]
    if section.single then
      value = (value and value ~= "") and { value } or {}
    end
    for _, entry in ipairs(value or {}) do
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

--- The entries of the edited lines: { code_folder = { { entry, lnum } }, parents = ..., folders =
--- ... } and the errors that block saving. `first` is the buffer line number of lines[1].
---@param lines string[]
---@param first number|nil
---@return table entries
---@return string[] errors
function M.parse(lines, first)
  first = first or 1
  local entries = { code_folder = {}, parents = {}, folders = {} }
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

--- The state of `path`: "folder", "missing" or "file"
local function state_of(path)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return not stat and "missing" or (stat.type == "directory" and "folder" or "file")
end

--- The code folder's entry checked: it gains `path` and `state`, and the errors that block saving
--- are added to `errors`. The code folder is the base of every other path, so it must be one
--- folder that exists, written ~/... or absolute (relative to itself means nothing).
local function validate_code_folder(entries, errors)
  local items = entries.code_folder
  if #items == 0 then
    table.insert(errors, "The code folder is empty: write the folder under its title")
  end
  for index, item in ipairs(items) do
    item.path = M.resolve_code_folder(item.entry)
    item.state = item.path and state_of(item.path) or "relative"
    if index > 1 then
      item.duplicate = true
      table.insert(errors, ("Line %d: there is one code folder, already on line %d"):format(item.lnum, items[1].lnum))
    elseif item.state == "relative" then
      table.insert(errors, ("Line %d: the code folder is written ~/... or absolute"):format(item.lnum))
    elseif item.state == "missing" then
      table.insert(errors, ("Line %d: %s does not exist"):format(item.lnum, item.entry))
    elseif item.state == "file" then
      table.insert(errors, ("Line %d: %s is a file, not a folder"):format(item.lnum, item.entry))
    end
  end
end

--- A code folder entry as an absolute path (~ expanded, links resolved when it exists), or nil
--- when it is relative
---@param entry string
---@return string|nil
function M.resolve_code_folder(entry)
  entry = vim.trim(entry)
  if not entry:match("^[/~]") or (entry:sub(1, 1) == "~" and entry ~= "~" and entry:sub(1, 2) ~= "~/") then
    return nil
  end
  local path = paths.resolve(entry, "/")
  return (vim.uv or vim.loop).fs_realpath(path) or path
end

--- What each entry's path is, for the screen's hints and the save: entries gain `path` (resolved)
--- and `state` ("folder", "missing" or "file"; "relative" for a code folder written so). The
--- other paths are relative to the code folder as edited when it is a folder, else to `root`.
--- Returns the errors that block saving and the code folder used.
---@param entries table From M.parse
---@param root string The code folder as loaded
---@return string[] errors
---@return string root
function M.validate(entries, root)
  local errors = {}
  validate_code_folder(entries, errors)
  local edited = entries.code_folder[1]
  if edited and edited.state == "folder" then
    root = edited.path
  end
  for _, section in ipairs(M.SECTIONS) do
    if section.single then
      goto continue
    end
    local seen = {}
    for _, item in ipairs(entries[section.key]) do
      item.path = paths.resolve(item.entry, root)
      item.state = state_of(item.path)
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
    ::continue::
  end
  return errors, root
end

--- The entries' texts, by section: what the code-folder file (code_folder, nil when there is
--- none) and projects.json (parents, folders) are written with
---@param entries table
---@return table { code_folder = string|nil, parents = string[], folders = string[] }
function M.values(entries)
  local values = {}
  for _, section in ipairs(M.SECTIONS) do
    local texts = vim.tbl_map(function(item)
      return item.entry
    end, entries[section.key])
    values[section.key] = section.single and texts[1] or texts
  end
  return values
end

return M
