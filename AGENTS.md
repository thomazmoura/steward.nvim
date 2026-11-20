# AGENTS.md

steward.nvim: the environment's settings edited as text in Neovim, in the style of workhorse.nvim's screens. It edits the files that dev-environment's tmux scripts read: `projects.json`, the project folders listed by `prefix,/`, and `themes.json`, the tmux theme colour of each session.

## Layout

- `plugin/steward.lua`: the `:Steward <sub>` command, dispatched through a `subcommands` table, and the `Steward*` highlight links.
- `lua/steward/config.lua`: the options. All of them are optional.
- `lua/steward/paths.lua`: the code folder (the setup() option, then the `code-folder` file, then `$CODE_FOLDER`, the tmux server's, and the guesses; the same order as dev-environment's `code-folder.sh`), plus how entries are resolved, shown and expanded. **It must keep the same rules as dev-environment's `modules/tmux/scripts/project_folders.py`**, which is what the pickers use to read the file.
- `lua/steward/store.lua`: reads and writes the settings files: plain JSON (`projects.json`, `themes.json`), and `code-folder`, one line of plain text that every shell reads on every ssh command. Writes are atomic, and unknown keys are kept.
- `lua/steward/ui/`: `header.lua` (the virtual header), `send.lua` (the save keys; `:w` is a no-op) and `guides.lua` (the tree guides drawn over the indentation, 3 spaces a level), trimmed from workhorse.nvim's. `choices.lua` (completion as you type, attached by both screens) and `blink.lua` (its blink.cmp source, with the native menu as the fallback), ported from paperboy.nvim's; keep them in step with it.
- `lua/steward/projects/`: `parse.lua` (render, parse and validate, all pure functions) and `init.lua` (the screen).
- `lua/steward/themes/`: the same split for the themes screen. **Its key rules (`key_kind`, which key wins) must match dev-environment's `modules/tmux/scripts/themes.py`**, which is what `Set-SessionTheme.sh` uses to read the file.
- `defaults/themes.json`: the themes the screen shows while there is no saved file.

## Rules

- A new setting gets its own screen, as `lua/steward/<name>/`, plus a subcommand. If a script reads its file, the format must stay plain JSON. The exception is a single value that shells read at startup, like `code-folder`, which is one line of text.
- Run the tests: `nvim --headless -l tests/run.lua`. Add a spec when you change behaviour.
- Commit messages carry no AI attribution.
