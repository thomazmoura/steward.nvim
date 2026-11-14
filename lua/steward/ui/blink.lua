-- blink.cmp source for the screens (see ui/choices.lua): the choices of a line (a key, a theme,
-- a folder). The screen asks for them on every keystroke, matched against the whole value typed
-- so far (blink.cmp alone would match only its last word, e.g. "app" of "/srv/app"), and only
-- this source runs on those lines, so buffer words and snippets stay out.
-- Ported from paperboy.nvim's form/blink.lua (itself from workhorse.nvim's builds/blink_source.lua).
local M = {}

local ID = "steward"
-- Filetypes of the screens completed by ui/choices.lua
local FILETYPES = { "steward-projects", "steward-themes" }

local Source = {}
Source.__index = Source

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return require("steward.ui.choices").choice_completion() ~= nil
end

function Source:get_completions(context, callback)
  local choices = require("steward.ui.choices")
  local completion = choices.choice_completion()
  local items = {}
  if completion then
    local line, col = context.cursor[1] - 1, context.cursor[2]
    for i, match in ipairs(completion.matches) do
      local word = choices.word(match)
      local menu = type(match) == "table" and match.menu or nil
      table.insert(items, {
        label = word,
        labelDetails = menu and { description = menu } or nil,
        filterText = word,
        -- Keep the screen's order (starting with the text, containing it, then fuzzy):
        -- blink.cmp sorts by its own score first, which these offsets outweigh
        sortText = ("%04d"):format(i),
        score_offset = (#completion.matches - i + 1) * 1000,
        kind = require("blink.cmp.types").CompletionItemKind.EnumMember,
        textEdit = {
          newText = word,
          range = { start = { line = line, character = completion.start }, ["end"] = { line = line, character = col } },
        },
      })
    end
  end
  callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
end

local registered = false

--- Register the source with blink.cmp (once); returns true when done
function M.register()
  if registered then
    return true
  end
  local blink = require("blink.cmp")
  local ok = pcall(blink.add_source_provider, ID, { name = "Steward", module = "steward.ui.blink" })
  if not ok then
    return false
  end
  local per_filetype = require("blink.cmp.config").sources.per_filetype
  for _, filetype in ipairs(FILETYPES) do
    if per_filetype[filetype] == nil then
      -- Only the choices on lines that have them, the usual sources elsewhere
      per_filetype[filetype] = function()
        if require("steward.ui.choices").choice_completion() then
          return { ID }
        end
        return { inherit_defaults = true }
      end
    else
      -- The user configured the filetype: add to it
      blink.add_filetype_source(filetype, ID)
    end
  end
  registered = true
  return true
end

return M
