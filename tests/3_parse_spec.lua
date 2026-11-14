local parse = require("steward.projects.parse")

T.test("render and parse round-trip", function()
  local data = { parents = { "clients", "~/work" }, folders = { "/etc" } }
  local lines = parse.render(data)
  T.eq(lines, { "Parent directories", "   clients", "   ~/work", "", "Individual directories", "   /etc" })
  local entries, errors = parse.parse(lines)
  T.eq(errors, {})
  T.eq(parse.values(entries), data)
  T.eq(entries.parents[2].lnum, 3)
end)

T.test("trailing slashes go, titles match ignoring case", function()
  local entries, errors = parse.parse({ "parent DIRECTORIES", "a/", "", "individual directories", " / " }, 5)
  T.eq(errors, {})
  T.eq(parse.values(entries), { parents = { "a" }, folders = { "/" } })
  T.eq(entries.parents[1].lnum, 6)
end)

T.test("lines before a title and missing titles block saving", function()
  local _, errors = parse.parse({ "stray", "Parent directories", "a" })
  T.eq(#errors, 2)
  T.ok(errors[1]:find("Line 1", 1, true))
  T.ok(errors[2]:find("Individual directories", 1, true))
end)

T.test("validate: files, duplicates and the code folder block saving; missing does not", function()
  T.mkdirs("code/a")
  T.write(T.dir .. "/code/f", "")
  local root = T.dir .. "/code"
  local entries = parse.parse({
    "Parent directories", "a", root .. "/a", "missing", root,
    "Individual directories", "a", "f",
  })
  local errors = parse.validate(entries, root)
  T.eq(#errors, 3, vim.inspect(errors))
  T.eq(entries.parents[1].state, "folder")
  T.ok(entries.parents[2].duplicate)
  T.eq(entries.parents[3].state, "missing")
  T.ok(entries.parents[4].duplicate)
  T.eq(entries.folders[1].duplicate, nil, "a parent may also be listed itself")
  T.eq(entries.folders[2].state, "file")
end)
