local parse = require("steward.projects.parse")

local CODE = { "Code folder", "   /srv/code", "" }

--- `lines` after the code folder section (written /srv/code), so only what follows is tested
local function with_code(lines)
  return vim.list_extend(vim.deepcopy(CODE), lines)
end

T.test("render and parse round-trip", function()
  local data = { code_folder = "/srv/code", parents = { "clients", "~/work" }, folders = { "/etc" } }
  local lines = parse.render(data)
  T.eq(lines, with_code({ "Parent directories", "   clients", "   ~/work", "", "Individual directories", "   /etc" }))
  local entries, errors = parse.parse(lines)
  T.eq(errors, {})
  T.eq(parse.values(entries), data)
  T.eq(entries.parents[2].lnum, 6)
  T.eq(entries.code_folder[1].lnum, 2)
end)

T.test("render: no code folder is an empty section", function()
  T.eq(parse.render({ parents = {}, folders = {} }), { "Code folder", "", "Parent directories", "", "Individual directories" })
end)

T.test("trailing slashes go, titles match ignoring case", function()
  local entries, errors = parse.parse({ "code FOLDER", "/srv/", "parent DIRECTORIES", "a/", "", "individual directories", " / " }, 5)
  T.eq(errors, {})
  T.eq(parse.values(entries), { code_folder = "/srv", parents = { "a" }, folders = { "/" } })
  T.eq(entries.parents[1].lnum, 8)
end)

T.test("lines before a title and missing titles block saving", function()
  local _, errors = parse.parse({ "stray", "Parent directories", "a" })
  T.eq(#errors, 3, vim.inspect(errors))
  T.ok(errors[1]:find("Line 1", 1, true))
  T.ok(errors[2]:find("Code folder", 1, true))
  T.ok(errors[3]:find("Individual directories", 1, true))
end)

T.test("validate: files, duplicates and the code folder block saving; missing does not", function()
  T.mkdirs("code/a")
  T.write(T.dir .. "/code/f", "")
  local root = T.dir .. "/code"
  local entries = parse.parse({
    "Code folder", root,
    "Parent directories", "a", root .. "/a", "missing", root,
    "Individual directories", "a", "f",
  })
  local errors, used = parse.validate(entries, "/elsewhere")
  T.eq(#errors, 3, vim.inspect(errors))
  T.eq(used, root, "the code folder as edited")
  T.eq(entries.code_folder[1].state, "folder")
  T.eq(entries.parents[1].state, "folder")
  T.ok(entries.parents[2].duplicate)
  T.eq(entries.parents[3].state, "missing")
  T.ok(entries.parents[4].duplicate)
  T.eq(entries.folders[1].duplicate, nil, "a parent may also be listed itself")
  T.eq(entries.folders[2].state, "file")
end)

T.test("validate: the code folder must be one existing folder, ~/... or absolute", function()
  T.mkdirs("code/a", "other/b")
  T.write(T.dir .. "/file", "")
  local function check(code_lines)
    local lines = { "Code folder" }
    vim.list_extend(lines, code_lines)
    vim.list_extend(lines, { "Parent directories", "Individual directories", "b" })
    local entries = parse.parse(lines)
    local errors, used = parse.validate(entries, T.dir .. "/code")
    return errors, used, entries
  end
  -- Each of these blocks saving, and the others keep resolving against the loaded one
  for _, case in ipairs({
    { {}, "empty" },
    { { T.dir .. "/nowhere" }, "does not exist" },
    { { T.dir .. "/file" }, "is a file" },
    { { "other" }, "~/... or absolute" },
    { { "~nobody/x" }, "~/... or absolute" },
    { { T.dir .. "/code", T.dir .. "/other" }, "one code folder" },
  }) do
    local errors, used = check(case[1])
    T.eq(#errors, 1, vim.inspect(case) .. vim.inspect(errors))
    T.ok(errors[1]:find(case[2], 1, true), errors[1])
    T.eq(used, T.dir .. "/code", case[2])
  end
  -- A valid one: the other paths are relative to it, as a link it is its real path
  vim.uv.fs_symlink(T.dir .. "/other", T.dir .. "/link")
  local errors, used, entries = check({ T.dir .. "/link/" })
  T.eq(errors, {})
  T.eq(used, T.dir .. "/other")
  T.eq(entries.folders[1].path, T.dir .. "/other/b")
  T.eq(entries.folders[1].state, "folder")
  T.eq(parse.values(entries).code_folder, T.dir .. "/link")
end)
