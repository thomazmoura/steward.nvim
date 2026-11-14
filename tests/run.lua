-- Tests of steward: nvim --headless -l tests/run.lua [filter]
-- Runs every tests/*_spec.lua (only those whose name contains `filter` when given), in the style
-- of locksmith.nvim's harness: no plenary, a fresh temporary folder per test (T.dir).
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.rtp:prepend(root)
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;"):format(root, root) .. package.path

local T = { root = root, passed = 0, failed = {} }
_G.T = T

local function show(value)
  return type(value) == "string" and ("%q"):format(value) or vim.inspect(value)
end

function T.eq(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(("%sexpected %s, got %s"):format(message and (message .. ": ") or "", show(expected), show(actual)), 2)
  end
end

function T.ok(value, message)
  if not value then
    error(message or "expected a true value", 2)
  end
  return value
end

function T.read(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

function T.write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local handle = assert(io.open(path, "wb"))
  handle:write(content)
  handle:close()
end

--- Make folders under T.dir: T.mkdirs("code/a", "code/.hidden")
function T.mkdirs(...)
  for _, path in ipairs({ ... }) do
    vim.fn.mkdir(T.dir .. "/" .. path, "p")
  end
end

function T.test(name, fn)
  T.dir = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(T.dir, "p")
  vim.env.XDG_CONFIG_HOME = T.dir .. "/config"
  vim.env.CODE_FOLDER = T.dir .. "/code"
  -- The session labels from this folder, and no tmux server: tmux looks for one in an empty
  -- folder, so a test never reads or re-themes the sessions of the tmux it runs under
  vim.env.XDG_CACHE_HOME = T.dir .. "/cache"
  vim.env.TMUX = nil
  vim.env.TMUX_TMPDIR = T.dir
  -- Messages are not printed (a test that checks them replaces this)
  vim.notify = function() end
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    T.passed = T.passed + 1
    io.stdout:write("  ok   " .. name .. "\n")
  else
    table.insert(T.failed, name)
    io.stdout:write("  FAIL " .. name .. "\n" .. tostring(err):gsub("\n", "\n       ") .. "\n")
  end
  vim.fn.delete(T.dir, "rf")
end

local filter = arg[1]
local files = vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
table.sort(files)
for _, file in ipairs(files) do
  if not filter or file:find(filter, 1, true) then
    io.stdout:write(vim.fn.fnamemodify(file, ":t") .. "\n")
    local ok, err = xpcall(dofile, debug.traceback, file)
    if not ok then
      table.insert(T.failed, file)
      io.stdout:write("  FAIL loading: " .. tostring(err) .. "\n")
    end
  end
end

io.stdout:write(("\n%d passed, %d failed\n"):format(T.passed, #T.failed))
io.stdout:flush()
os.exit(#T.failed == 0 and 0 or 1)
