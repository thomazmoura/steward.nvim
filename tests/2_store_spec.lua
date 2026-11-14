local store = require("steward.store")

T.test("a missing file is an empty one", function()
  T.eq(store.load(T.dir .. "/none.json"), { parents = {}, folders = {}, extra = {} })
end)

T.test("save then load round-trips, keeping unknown keys", function()
  local path = T.dir .. "/deep/er/projects.json"
  local data = { parents = { "clients", "~/work" }, folders = { "/etc/nginx" }, extra = { theirs = { a = 1 } } }
  T.ok(store.save(path, data))
  T.eq(store.load(path), data)
  T.eq(vim.json.decode(T.read(path)).version, 1)
  T.eq(vim.fn.glob(T.dir .. "/deep/er/*.tmp*", false, true), {}, "no temporary file left")
end)

T.test("one entry a line", function()
  local text = store.encode({ parents = { "a", "b" }, folders = {} })
  T.eq(text, '{\n  "version": 1,\n  "parents": [\n    "a",\n    "b"\n  ],\n  "folders": []\n}\n')
end)

T.test("broken JSON is an error, not an empty list", function()
  T.write(T.dir .. "/p.json", "{bad")
  local data, err = store.load(T.dir .. "/p.json")
  T.eq(data, nil)
  T.ok(err:find("not valid JSON", 1, true), err)
  T.write(T.dir .. "/p.json", "[1]")
  data, err = store.load(T.dir .. "/p.json")
  T.ok(err:find("not a JSON object", 1, true), err)
end)

T.test("entries that are not strings are dropped", function()
  T.write(T.dir .. "/p.json", '{"parents": ["a", 3, "", null], "folders": "x"}')
  T.eq(store.load(T.dir .. "/p.json"), { parents = { "a" }, folders = {}, extra = {} })
end)
