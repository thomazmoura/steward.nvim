# steward.nvim

The environment's settings, edited as text in Neovim, in the style of
[workhorse.nvim](https://github.com/thomazmoura/workhorse.nvim)'s screens. It is the
settings side of [dev-environment](https://github.com/thomazmoura/dev-environment): what its
tmux scripts read, steward edits.

For now there is one screen: the **project folders** the tmux session pickers offer.

## Project folders (`:Steward projects`)

dev-environment's `prefix,/` lists the first level of folders in the code folder
(`$CODE_FOLDER`). `projects.json` adds more:

- **Parent directories:** their first level of folders is listed (hidden ones left out).
- **Individual directories:** these folders are listed themselves.

The file is `$XDG_CONFIG_HOME/dev-environment/projects.json`, by default `~/.config/dev-environment/projects.json`:

```json
{
  "version": 1,
  "parents": [
    "clients",
    "~/work"
  ],
  "folders": [
    "~/notes",
    "/etc/nginx"
  ]
}
```

A path is relative to the code folder, `~/…`, or absolute. Relative paths let one file fit machines whose code folders differ.

- **Code folder:** it is always a parent, and it is not written to the file.
- **Saving:** when steward saves, keys it doesn't know are kept.
- **Per machine:** each machine reads its own file. A linked machine's folders in `prefix,/`, and `prefix,N` to a host with dev-environment, come from that machine's file.

The screen:

```
Project folders                                                 Reload
Code folder  ~/code  read-only · 24 folders
Saved in     ~/.config/dev-environment/projects.json
─────────────────────────── ◇ ───────────────────────────
Parent directories   their folders are listed
  clients   12 folders  ~/code/clients
  ~/work   missing

Individual directories   listed themselves
  ~/notes   new
```

- **The header:** it is virtual text. The code folder shown there comes from `$CODE_FOLDER`. If that isn't set, the tmux server's `CODE_FOLDER` is used, then the first of `~/code`, `~/git` and `/Git`. You can't edit it here.
- **Editing:** you add, change and remove folders by editing the text, one path a line, under its section title.
- **Hints:** after each path. A parent shows how many folders it adds, and a relative path shows where it points. Other hints flag a path that is missing (allowed), not a folder, a duplicate, or new since the last load.
- **Errors:** a file, a duplicate, the code folder as a parent, a missing section title, or an edited header line all block saving.

| Key | |
|---|---|
| `<leader><leader>` (normal), `<C-CR>` (insert) | Save. `:w` does nothing, so an auto-save plugin never saves a half-typed path |
| `<leader>R`, `<CR>` on the title | Reload (asks first when there are edits) |
| `<CR>` on a path | A float listing the folders it adds |
| `gf` | Open the folder |
| `{` / `}`, `g1` / `g2` | Previous / next section, go to a section |
| `<C-x><C-o>` (insert) | Complete a folder (relative to the code folder unless it starts with `/` or `~`) |

In dev-environment you can open it three ways:
- Ctrl-E in `prefix,/` (the picker comes back with the saved list);
- the picker pane's *Steward*;
- `:Steward projects`.

## Setup

With lazy.nvim:

```lua
{
  'thomazmoura/steward.nvim',
  cmd = 'Steward',
  opts = {
    projects = {
      file = nil,        -- default: $XDG_CONFIG_HOME/dev-environment/projects.json
      code_folder = nil, -- a path or a function; default: as described above
    },
  },
}
```

`setup()` is optional.

## Tests

```sh
nvim --headless -l tests/run.lua [filter]
```
