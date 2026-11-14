-- The themes screen's text: render, parse, validate, and the themes file in the store
local parse = require("steward.themes.parse")
local store = require("steward.store")

local function check(lines)
  local entries, errors = parse.parse(lines)
  vim.list_extend(errors, parse.validate(entries, T.dir .. "/code"))
  return entries, errors
end

local function has(errors, text)
  for _, err in ipairs(errors) do
    if err:find(text, 1, true) then
      return true
    end
  end
  error(("no error with %q in %s"):format(text, vim.inspect(errors)), 2)
end

T.test("key kinds", function()
  local function kind(key)
    return { parse.key_kind(key) }
  end
  T.eq(kind("default"), { "default", "default" })
  T.eq(kind("ApolloEnv"), { "session", "ApolloEnv" })
  T.eq(kind("steward.nvim"), { "session", "steward.nvim" })
  T.eq(kind("~/notes"), { "directory", "~/notes" })
  T.eq(kind("clients/acme"), { "directory", "clients/acme" })
  T.eq(kind("/srv/app@me@prod"), { "directory@host", "/srv/app", "me@prod" })
  T.eq(kind("ApolloEnv@docker:apollo"), { "session@host", "ApolloEnv", "docker:apollo" })
end)

T.test("render then parse round-trips, colours normalised", function()
  local data = {
    themes = { { name = "moon", color = "#00abab" }, { name = "gold", color = "FFB86C" } },
    assignments = { { match = "default", theme = "moon" }, { match = "my folder/x", theme = "gold" } },
  }
  local lines = parse.render(data)
  T.eq(lines, {
    "Themes", "   moon: #00abab", "   gold: FFB86C", "",
    "Assignments", "   default: moon", "   my folder/x: gold",
  })
  local entries, errors = check(lines)
  T.eq(errors, {})
  T.eq(parse.values(entries), {
    themes = { { name = "moon", color = "#00abab" }, { name = "gold", color = "#ffb86c" } },
    assignments = { { match = "default", theme = "moon" }, { match = "my folder/x", theme = "gold" } },
  })
  T.eq(entries.themes[1].uses, 1)
  T.eq(entries.assignments[2].path, T.dir .. "/code/my folder/x")
  T.eq(entries.assignments[2].state, "missing")
end)

T.test("a line splits at its last colon followed by a blank", function()
  T.eq({ parse.split("   Proj@docker:x: gold") }, { 3, "Proj@docker:x", "gold", 17 })
  T.eq({ parse.split("   default:") }, { 3, "default", "", 11 })
  T.eq({ parse.split("   Proj@docker:x") }, { 3, nil, "Proj@docker:x", nil })
end)

T.test("a directory key loses its trailing slash", function()
  local entries = check({ "Themes", "  a: #000000", "Assignments", "  default: a", "  ~/work/: a", "  /srv/@h: a" })
  T.eq(entries.assignments[2].key, "~/work")
  T.eq(entries.assignments[3].key, "/srv@h")
end)

T.test("what blocks saving", function()
  local _, errors = check({
    "Themes",
    "  moon: #00abab",
    "  Moon: #111111",
    "  bad name: #222222",
    "  gold: #ffb86",
    "  lonely",
    "  gold #ffb86c",       -- no ": "
    "Assignments",
    "  x: nope",
    "  default@prod: moon",
    "  @prod: moon",
    "  x@: moon",
    "  ~/a@prod: moon",
    "  x: moon",
  })
  has(errors, "Moon is already on line 2")
  has(errors, "a name is letters")
  has(errors, "#ffb86 is not a colour")
  has(errors, "Line 6: a name and a colour")
  has(errors, "Line 7: a name and a colour, as name: #rrggbb")
  has(errors, "no theme is called nope")
  has(errors, "default takes no @host")
  has(errors, "nothing before the @")
  has(errors, "no host after the @")
  has(errors, "a folder on a host is absolute")
  has(errors, "x is already on line 9")
  has(errors, "No default")
end)

T.test("a second default, a missing title, a line above the titles", function()
  local _, errors = check({ "  stray: #000000", "Themes", "  a: #000000", "Assignments", "  default: a", "  default: a" })
  has(errors, "Line 1: not under a section title")
  has(errors, "default is already on line 5")
  _, errors = check({ "Themes", "  a: #000000" })
  has(errors, 'The "Assignments" title is missing')
end)

T.test("the same folder written two ways is a duplicate", function()
  T.mkdirs("code/a")
  local entries, errors = check({ "Themes", "  t: #000000", "Assignments", "  default: t", "  a/x/..: t", "  " .. T.dir .. "/code/a: t" })
  T.eq(entries.assignments[2].state, "folder")
  has(errors, "is already on line 5")
end)

T.test("the themes file: a missing one is nil, save and load round-trip", function()
  local path = T.dir .. "/t/themes.json"
  local data, missing = store.load_themes(path)
  T.eq({ data, missing }, { nil, true })
  data = {
    themes = { { name = "moon", color = "#00abab" } },
    assignments = { { match = "default", theme = "moon" } },
    extra = { theirs = 1 },
  }
  T.ok(store.save_themes(path, data))
  T.eq(store.load_themes(path), data)
  T.eq(T.read(path), table.concat({
    "{",
    '  "version": 1,',
    '  "themes": [',
    '    { "name": "moon", "color": "#00abab" }',
    "  ],",
    '  "assignments": [',
    '    { "match": "default", "theme": "moon" }',
    "  ],",
    '  "theirs": 1',
    "}",
    "",
  }, "\n"))
end)

T.test("the bundled defaults are valid", function()
  local data = T.ok(store.load_themes(T.root .. "/defaults/themes.json"))
  local entries, errors = check(parse.render(data))
  T.eq(errors, {})
  T.eq(#entries.themes, 11)
end)

T.test("each key says what it is, muted while it has no effect", function()
  T.mkdirs("code/acme")
  local entries = check({
    "Themes", "  t: #000000",
    "Assignments",
    "  default: t",
    "  ApolloEnv: t",
    "  Nobody: t",
    "  acme: t",
    "  ./later: t",
    "  /srv/app@me@prod: t",
    "  box@prod: t",
  })
  local function describe(index)
    return { parse.describe(entries.assignments[index]) }
  end
  -- check() validates without names: validate them again with some
  parse.validate(entries, T.dir .. "/code", { ApolloEnv = true, ["box@prod"] = true })
  T.eq(describe(1), { "fallback", false })
  T.eq(describe(2), { "named session", false })
  T.eq(describe(3), { "named session (no such name)", true })
  T.eq(describe(4), { "named session (no such name)", true }, "a bare word is a session name, not a folder")
  T.eq(describe(5), { "path-based session (missing)", true })
  T.eq(describe(6), { "path-based session on me@prod", false })
  T.eq(describe(7), { "named session on prod", false })
end)
