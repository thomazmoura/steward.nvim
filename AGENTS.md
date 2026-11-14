# AGENTS.md

steward.nvim: the environment's settings edited as text in Neovim, in the style of workhorse.nvim's screens. It edits the files that dev-environment's tmux scripts read. Today that is one file, `projects.json`, the project folders listed by `prefix,/`.

## Layout

- `plugin/steward.lua`: the `:Steward <sub>` command, dispatched through a `subcommands` table, and the `Steward*` highlight links.
- `lua/steward/config.lua`: the options. All of them are optional.
- `lua/steward/paths.lua`: the code folder, plus how entries are resolved, shown and expanded. **It must keep the same rules as dev-environment's `modules/tmux/scripts/project_folders.py`**, which is what the pickers use to read the file.
- `lua/steward/store.lua`: reads and writes plain JSON. Writes are atomic, and unknown keys are kept.
- `lua/steward/ui/`: `header.lua` (the virtual header) and `send.lua` (the save keys; `:w` is a no-op), trimmed from workhorse.nvim's.
- `lua/steward/projects/`: `parse.lua` (render, parse and validate, all pure functions) and `init.lua` (the screen).

## Rules

- A new setting gets its own screen, as `lua/steward/<name>/`, plus a subcommand. If a script reads its file, the format must stay plain JSON.
- Run the tests: `nvim --headless -l tests/run.lua`. Add a spec when you change behaviour.
- Commit messages carry no AI attribution.
