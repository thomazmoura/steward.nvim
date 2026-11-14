-- The themes screen's text, both ways: the lines it shows for themes.json (render) and the
-- entries read back from the edited lines (parse), with what blocks a save (validate).
--
--   Themes                        a section title, as rendered (case aside)
--      moon: #00abab              a name and its accent colour, indented one level (the screen
--      gold: #ffb86c              draws tree guides over the indentation: ├─ moon, └─ gold)
--
--   Assignments
--      default: moon              a key and the name of a theme
--      clients/acme: gold         the key is everything before the last ": " (a colon and a
--      ApolloEnv@docker:x: gold   blank), so a key can hold a colon (docker:name)
--
-- Which session a key is about (key_kind; dev-environment's themes.py reads keys the same way):
--   default            whatever nothing more specific matches (required)
--   default (ssh)      an ssh session (prefix+N) no @Host key matches; default (docker) the same
--                      for a Docker one (prefix+D). Without it, such a session takes default
--   Directory          a local session in that folder or one under it; path-like: it starts with /
--                      or ~, or has a /. Relative to the code folder, as projects.json's paths
--   SessionName        a local session of that name or prefix+$ label (dev-environment's
--                      Set-SessionLabel.sh); anything not path-like
--   Directory@Host     an ssh/Docker session (prefix+N, prefix+D) in that folder of Host, which
--                      is absolute; the key is split at its first @
--   SessionName@Host   an ssh/Docker session of that name on Host
-- Host is the session's ssh target as prefix+N took it (user@host or docker:name), or its host.
-- Which wins, most specific first: SessionName, Directory, default. On an ssh/Docker session:
-- SessionName@Host, Directory@Host, default (ssh) or default (docker), default.
local M = {}

local paths = require("steward.paths")

M.SECTIONS = {
  { key = "themes", title = "Themes", hint = "a name and its #rrggbb accent colour" },
  { key = "assignments", title = "Assignments", hint = "default, default (ssh|docker), Directory, SessionName, Directory@Host, SessionName@Host" },
}

-- Between a key and its value
M.SEPARATOR = ": "

M.KINDS = {
  default = "fallback",
  connection = "fallback for a connection",
  directory = "path-based session",
  session = "named session",
  ["directory@host"] = "path-based session on a host",
  ["session@host"] = "named session on a host",
}

-- The connections a "default (<name>)" key is for, in completion's order, with how a hint names them
M.CONNECTIONS = {
  { name = "ssh", label = "ssh" },
  { name = "docker", label = "Docker" },
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

--- A colour as saved (#rrggbb, lowercase), or nil when it is not one
---@param text string
---@return string|nil
function M.color(text)
  local hex = vim.trim(text or ""):match("^#?(%x%x%x%x%x%x)$")
  return hex and ("#" .. hex:lower()) or nil
end

local function path_like(text)
  local first = text:sub(1, 1)
  return first == "/" or first == "~" or text:find("/", 1, true) ~= nil
end

--- The connection a "default (<connection>)" key names (lowercase, maybe not one of
--- M.CONNECTIONS), or nil when the key is not one. Blanks around the name are allowed.
---@param key string
---@return string|nil
local function connection_of(key)
  local name = key:match("^default%s*%(%s*(.-)%s*%)$")
  return name and name:lower()
end

--- What session a key is about: its kind (a key of M.KINDS), the part before the @ (the
--- directory or session name, or for a connection default the connection) and the host (nil
--- without an @)
---@param key string
---@return string kind
---@return string subject
---@return string|nil host
function M.key_kind(key)
  if key == "default" then
    return "default", key, nil
  end
  local connection = connection_of(key)
  if connection then
    return "connection", connection, nil
  end
  local subject, host = key:match("^([^@]*)@(.*)$")
  subject = subject or key
  local kind = path_like(subject) and "directory" or "session"
  if host then
    kind = kind .. "@host"
  end
  return kind, subject, host
end

--- The screen's lines for `data` ({ themes, assignments }): "name: colour" and "key: theme"
---@param data table
---@return string[]
function M.render(data)
  local lines = { M.SECTIONS[1].title }
  for _, theme in ipairs(data.themes or {}) do
    table.insert(lines, INDENT .. theme.name .. M.SEPARATOR .. theme.color)
  end
  table.insert(lines, "")
  table.insert(lines, M.SECTIONS[2].title)
  for _, assignment in ipairs(data.assignments or {}) do
    table.insert(lines, INDENT .. assignment.match .. M.SEPARATOR .. assignment.theme)
  end
  return lines
end

--- A line split at its separator (the last ":" followed by a blank, or ending the line): the
--- indent's width, the key (nil without a separator), the value (maybe "") and the separator's
--- column (1-based, the ":")
---@param line string
---@return number indent
---@return string|nil key
---@return string value
---@return number|nil colon
function M.split(line)
  local indent = #(line:match("^%s*"))
  local text = line:sub(indent + 1)
  local key, value = text:match("^(.*):%s+(.-)%s*$")
  if not key then
    key = text:match("^(.*):%s*$")
    value = ""
  end
  if not key then
    return indent, nil, vim.trim(text), nil
  end
  return indent, vim.trim(key), value, indent + #key + 1
end

--- A typed key as it is saved: a directory's trailing slashes dropped (but for /), a connection
--- default written as "default (<connection>)"
local function clean_key(key)
  local connection = connection_of(key)
  if connection then
    return "default (" .. connection .. ")"
  end
  local subject, host = key:match("^([^@]*)@(.*)$")
  local function strip(path)
    if #path > 1 and path_like(path) then
      path = path:gsub("/+$", "")
    end
    return path
  end
  if subject then
    return strip(subject) .. "@" .. host
  end
  return strip(key)
end

--- The entries of the edited lines and the errors that block saving. `first` is the buffer line
--- number of lines[1].
---   themes:      { { name, color (as typed), lnum } }
---   assignments: { { key, theme, lnum } }
---@param lines string[]
---@param first number|nil
---@return table entries
---@return string[] errors
function M.parse(lines, first)
  first = first or 1
  local entries = { themes = {}, assignments = {} }
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
      local _, left, right = M.split(line)
      if not current then
        table.insert(errors, ("Line %d: not under a section title"):format(lnum))
      elseif not left or left == "" or right == "" then
        local wanted = current.key == "themes" and "a name and a colour, as name: #rrggbb"
          or "a key and a theme, as key: theme"
        table.insert(errors, ("Line %d: %s"):format(lnum, wanted))
      elseif current.key == "themes" then
        table.insert(entries.themes, { name = left, color = right, lnum = lnum })
      else
        table.insert(entries.assignments, { key = clean_key(left), theme = right, lnum = lnum })
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

--- Check the entries, for the screen's hints and the save. Themes gain `valid` (the colour as
--- saved, or nil) and `uses` (how many assignments name it); assignments gain `kind`, `subject`,
--- `host`, `color` (their theme's, when it exists) and, for a local directory, `path` (resolved)
--- and `state` ("folder", "missing" or "file"); a session name (SessionName, SessionName@Host)
--- gains `known` when `names` has it. Returns the errors that block saving.
---@param entries table From M.parse
---@param root string The code folder
---@param names table|nil The session names there are: { [name] = true } for local sessions,
---  { ["name@host"] = true } for those on a host (see the themes screen's known_names)
---@return string[] errors
function M.validate(entries, root, names)
  names = names or {}
  local errors = {}
  local function fail(item, message)
    item.error = true
    table.insert(errors, ("Line %d: %s"):format(item.lnum, message))
  end

  local by_name, seen_names = {}, {}
  for _, theme in ipairs(entries.themes) do
    theme.uses = 0
    theme.valid = M.color(theme.color)
    if not theme.name:match("^[%w_.%-]+$") then
      fail(theme, ("%q: a name is letters, digits, _, . and -"):format(theme.name))
    elseif seen_names[theme.name:lower()] then
      theme.duplicate = true
      fail(theme, ("%s is already on line %d"):format(theme.name, seen_names[theme.name:lower()]))
    else
      seen_names[theme.name:lower()] = theme.lnum
      by_name[theme.name] = theme
    end
    if not theme.valid then
      fail(theme, ("%s is not a colour: #rrggbb"):format(theme.color))
    end
  end

  local seen_keys, defaults = {}, 0
  for _, item in ipairs(entries.assignments) do
    item.kind, item.subject, item.host = M.key_kind(item.key)
    local identity = item.key
    if item.kind == "default" then
      defaults = defaults + 1
    elseif item.kind == "connection" then
      local known = vim.tbl_contains(vim.tbl_map(function(connection)
        return connection.name
      end, M.CONNECTIONS), item.subject)
      if not known then
        fail(item, ("%s: the connection is ssh or docker"):format(item.key))
      end
    elseif item.subject == "" then
      fail(item, ("%s: nothing before the @"):format(item.key))
    elseif item.host == "" then
      fail(item, ("%s: no host after the @"):format(item.key))
    elseif item.host and (item.subject == "default" or connection_of(item.subject)) then
      fail(item, "a default takes no @host: it is the fallback everywhere")
    elseif item.kind == "directory@host" and item.subject:sub(1, 1) ~= "/" then
      fail(item, ("%s: a folder on a host is absolute (its ~ and code folder are not known here)"):format(item.key))
    elseif item.kind == "directory" then
      item.path = paths.resolve(item.subject, root)
      identity = item.path
      local stat = (vim.uv or vim.loop).fs_stat(item.path)
      item.state = not stat and "missing" or (stat.type == "directory" and "folder" or "file")
      if item.state == "file" then
        fail(item, ("%s is a file, not a folder"):format(item.subject))
      end
    end
    if item.kind == "session" or item.kind == "session@host" then
      item.known = names[item.key] == true
    end
    if seen_keys[identity] then
      item.duplicate = true
      fail(item, ("%s is already on line %d"):format(item.key, seen_keys[identity]))
    else
      seen_keys[identity] = item.lnum
    end
    local theme = by_name[item.theme]
    if theme then
      theme.uses = theme.uses + 1
      item.color = theme.valid
    else
      item.unknown = true
      fail(item, ("no theme is called %s"):format(item.theme))
    end
  end
  if defaults == 0 then
    table.insert(errors, 'No default: add "default: <theme>" under Assignments')
  end
  return errors
end

--- What an assignment's key is, for its hint: the text, and whether it has no effect for now
--- (a folder that does not exist yet, a name no session has), to show it muted
---@param item table An assignment, after M.validate
---@return string text
---@return boolean idle
function M.describe(item)
  if item.kind == "connection" then
    for _, connection in ipairs(M.CONNECTIONS) do
      if connection.name == item.subject then
        return "fallback for " .. connection.label .. " sessions", false
      end
    end
  end
  local text = M.KINDS[item.kind] or item.kind
  if item.host then
    text = text:gsub("a host$", function()
      return item.host
    end)
  end
  if item.kind == "directory" and item.state == "missing" then
    return text .. " (missing)", true
  end
  if (item.kind == "session" or item.kind == "session@host") and not item.known then
    return text .. " (no such name)", true
  end
  return text, false
end

--- What themes.json is written with: themes' colours as saved, assignments' keys as cleaned
---@param entries table From M.parse, after M.validate
---@return table { themes = { { name, color } }, assignments = { { match, theme } } }
function M.values(entries)
  return {
    themes = vim.tbl_map(function(theme)
      return { name = theme.name, color = theme.valid or theme.color }
    end, entries.themes),
    assignments = vim.tbl_map(function(item)
      return { match = item.key, theme = item.theme }
    end, entries.assignments),
  }
end

return M
