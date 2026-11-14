# steward.nvim

The environment's settings, edited as text in Neovim, in the style of
[workhorse.nvim](https://github.com/thomazmoura/workhorse.nvim)'s screens. It is the
settings side of [dev-environment](https://github.com/thomazmoura/dev-environment): what its
tmux scripts read, steward edits.

There are two screens: the **project folders** the tmux session pickers offer, and the **tmux themes**, which set each session's colour.

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
├─ clients   12 folders  ~/code/clients
└─ ~/work   missing

Individual directories   listed themselves
└─ ~/notes   new
```

- **The header:** it is virtual text. The code folder shown there comes from `$CODE_FOLDER`. If that isn't set, the tmux server's `CODE_FOLDER` is used, then the first of `~/code`, `~/git` and `/Git`. You can't edit it here.
- **Editing:** you add, change and remove folders by editing the text, one path a line, under its section title. As on workhorse.nvim's screens, the lines are indented one level (3 spaces) under their section, and the `├─` / `└─` guides are virtual text drawn over the indentation, so they are never yanked. The indentation is kept for you: a new line under a section (`o` even on its title) starts one level in, and a line typed at the start goes under its section when you leave insert mode. This holds on the themes screen too.
- **Hints:** after each path. A parent shows how many folders it adds, and a relative path shows where it points. Other hints flag a path that is missing (allowed), not a folder, a duplicate, or new since the last load.
- **Errors:** a file, a duplicate, the code folder as a parent, a missing section title, or an edited header line all block saving.

| Key | |
|---|---|
| `<leader><leader>` (normal), `<C-CR>` (insert) | Save. `:w` does nothing, so an auto-save plugin never saves a half-typed path |
| `<leader>R`, `<CR>` on the title | Reload (asks first when there are edits) |
| `<CR>` on a path | A float listing the folders it adds |
| `gf` | Open the folder |
| `{` / `}`, `g1` / `g2` | Previous / next section, go to a section |
| Typing a path (insert) | Suggests folders as you type (relative to the code folder unless it starts with `/` or `~`); `<Tab>` / `<S-Tab>` move in the menu, `<CR>` takes the selected one, or the first |

In dev-environment you can open it three ways:
- Ctrl-E in `prefix,/` (the picker comes back with the saved list);
- the picker pane's *Steward*;
- `:Steward projects`.

## Tmux themes (`:Steward themes`)

dev-environment's tmux draws the status bar, borders and messages in one accent colour. `themes.json` names those colours and says which session draws in which:

- **Themes:** a name and its `#rrggbb` accent colour.
- **Assignments:** a key and the name of a theme. `default` is required; the other keys are optional.

| Key | Takes effect for |
|---|---|
| `default` | any session no other key matches |
| `default (ssh)`, `default (docker)` | an ssh session (`prefix,N`) or a Docker session (`prefix,D`) no `@Host` key matches |
| `Directory` | a local session in that folder, or in a folder under it (the longest match wins) |
| `SessionName` | a local session of that name, or the session with that `prefix,$` name (label): `ApolloEnv` for `dev-environment` named ApolloEnv |
| `Directory@Host` | an ssh/Docker session (`prefix,N`, `prefix,D`) in that folder on that host, or under it |
| `SessionName@Host` | an ssh/Docker session of that name on that host |

- **Telling them apart:** a key is a Directory when it is path-like: it starts with `/` or `~`, or contains a `/`. Anything else is a SessionName, so write `~/code/x` or `./x` for a top-level folder.
- **Directories:** a local Directory is relative to the code folder, `~/…`, or absolute, as in `projects.json`. A Directory@Host is absolute.
- **Hosts:** the key is split at its first `@`. The host is the session's ssh target, whole (`user@host`, `docker:name`) or just its host part.
- **Which key wins:** the most specific one that matches. A local session takes SessionName, then Directory, then `default`. An ssh/Docker session takes SessionName@Host, then Directory@Host, then `default (ssh)` or `default (docker)`, then `default`.
- **ssh and Docker sessions:** they never take a local SessionName or Directory key. A Docker session is one whose target is `docker:name`. Without a `default (ssh)` or `default (docker)`, they take `default`. Without a file, they keep the ssh violet or Docker blue.
- **Linked machines:** a session on a linked machine is drawn by that machine's tmux, from that machine's file.

The file is `$XDG_CONFIG_HOME/dev-environment/themes.json`:

```json
{
  "version": 1,
  "themes": [
    { "name": "moon", "color": "#00abab" },
    { "name": "coral", "color": "#ff7f50" }
  ],
  "assignments": [
    { "match": "default", "theme": "moon" },
    { "match": "ApolloEnv@prod", "theme": "coral" }
  ]
}
```

- **Defaults:** while there is no file, the screen shows steward's [`defaults/themes.json`](defaults/themes.json): the old tmux-power themes plus `azure` and `lavender`, with `default` set to `moon`, `default (ssh)` to `violet` and `default (docker)` to `azure` (the colours ssh and Docker sessions had before). Saving writes them. Without a file, tmux behaves as before (`@theme`).
- **When it applies:** at once. Saving runs dev-environment's `Set-SessionTheme.sh -g -a`, which draws the global bar and every open session in their new colours (set `themes.apply` to another script, or `false`). `prefix,u` does the same, and a session switch, attach, new session or new `prefix,$` name re-themes that session (`Set-SessionTheme.sh` and `themes.py`).

The screen:

```
Tmux themes                                                     Reload
Saved in     ~/.config/dev-environment/themes.json
─────────────────────────── ◇ ───────────────────────────
Themes   a name and its #rrggbb accent colour
├─ moon: #00abab   ██  used by 1
└─ coral: #ff7f50   ██  unused

Assignments   default, default (ssh|docker), Directory, SessionName, Directory@Host, SessionName@Host
├─ default: moon   ██  fallback
├─ default (ssh): coral   ██  fallback for ssh sessions
├─ ApolloEnv: coral   ██  named session
├─ acme: coral   ██  path-based session  ~/code/acme
├─ ~/later: coral   ██  path-based session (missing)
└─ ApolloEnv@prod: coral   ██  named session on prod  new
```

- **Editing:** a line is `key: value` (`name: #rrggbb` under Themes, `key: theme` under Assignments), indented under its section with tree guides drawn over the indentation, as on the projects screen. The key is coloured. It ends at the last `:` followed by a blank, so a key may contain spaces and colons (`Proj@docker:apollo: coral`).
- **Hints:** each colour gets a swatch, and each theme says how many assignments use it. Each key says what kind it is, and a relative folder shows where it points:
  - `fallback`: `default`;
  - `fallback for ssh sessions`, `fallback for Docker sessions`: `default (ssh)`, `default (docker)`;
  - `named session`: a name a session has, or a `prefix,$` name (`~/.cache/tmux/session-names`, open or not); muted as `(no such name)` while nothing has that name;
  - `path-based session`: a folder; muted as `(missing)` while it doesn't exist. It can still be saved, and takes effect once the folder is there;
  - `named session on <host>`, `path-based session on <host>`: the same for ssh/Docker sessions.
- **Errors:** these block saving:
  - a bad name or colour, or a duplicate;
  - an unknown theme;
  - no `default`, or `default@host`;
  - a `default (…)` for anything but `ssh` or `docker`;
  - a relative Directory@Host;
  - a duplicate key;
  - an edited header line.
- **Keys:** the same save, reload and `{` / `}`, `g1` / `g2` keys as the projects screen. Typing on an Assignments line suggests, as you type, a key or (after `key: `) a theme's name, with the theme's colour beside it; `<Tab>` / `<S-Tab>` move in the menu and `<CR>` takes the selected one, or the first. Keys come from:
  - `default`, `default (ssh)` and `default (docker)`;
  - the `prefix,$` names, local ones as they are and the others as `name@target`;
  - the tmux server's sessions: local ones by name, ssh/Docker ones as `name@target` and `folder@target`;
  - the folders `prefix,/` offers (the code folder's, plus what `projects.json` adds).

  Folders are written as the projects screen shows them, with `./` before a top-level one. A key starting with `/` or `~` also completes any folder. Keys already assigned are left out, and suggestions starting with what you typed come first.

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
    themes = {
      file = nil,        -- default: $XDG_CONFIG_HOME/dev-environment/themes.json
      apply = nil,       -- run (with -g -a) after saving; default: dev-environment's
                         -- ~/.modules/tmux/scripts/Set-SessionTheme.sh, false for none
    },
  },
}
```

`setup()` is optional.

**Completion** works as on workhorse.nvim's and paperboy.nvim's screens. With
[blink.cmp](https://github.com/Saghen/blink.cmp) installed, the suggestions come from a `steward`
source. Only it runs on the lines it completes, so buffer words and snippets stay out, while the
usual sources apply elsewhere. blink.cmp's own look, keymaps and selection settings apply.
Without it, Neovim's completion menu opens as you type. `<C-x><C-o>` also works.

## Tests

```sh
nvim --headless -l tests/run.lua [filter]
```
