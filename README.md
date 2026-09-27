# tatr.nvim

Minimal Neovim frontend for [Tsoding's TATR](https://github.com/tsoding/tatr).

Requires Neovim 0.10+ and `tatr` installed on PATH.

## Local development with lazy.nvim

```lua
{
  dir = vim.fn.expand('~/Programming/tatr.nvim'),
  config = function()
    require('tatr').setup({ keymap = '<leader>tt' })
  end,
}
```

Commands:
- `:Tatr` lists tasks from the closest ancestor `tasks/` folder, including closed tasks. Choose one to edit `TASK.md`.
- `:TatrNew` opens `tatr new` in a terminal split. Use `:Tatr` after it exits.
- `:TatrInit` runs `tatr init` in the current working directory if no ancestor project exists.

This first version reads `TASK.md` directly for display and delegates creation/initialization to the TATR executable. It does not modify task metadata itself.
