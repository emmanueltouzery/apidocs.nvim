# Apidocs.nvim

This is an integration of <https://devdocs.io/> in neovim.

This plugin will download devdocs documentations for offline usage and pre-format them for in-neovim display.
It will also extract the documentation for individual methods (`List.add()`...) for nicer browsing, and leverages neovim conceal features for a user-friendly display.

![basic screenshot](https://raw.githubusercontent.com/wiki/emmanueltouzery/apidocs.nvim/shot1.png)

## How to use

Call `require("apidocs").setup()` when installing the plugin to register the commands.

The plugin exports the following commands:

- `ApidocsInstall` - will fetch the list of supported documentation sources (lua, openjdk, rust...) from devdocs.io and ask you which one you wish to install. Note that downloading+installing can take over a minute and WILL TEMPORARILY FREEZE YOUR NEOVIM. This is because the plugin leverages neovim's tree-sitter to post-process the files. This happens only when installing a source, and never again after that.
- `ApidocsOpen` (requires telescope.nvim or snacks.nvim) - open a picker listing all apidocs. If you want to display only a subset of sources, call the lua function: `:lua require("apidocs").apidocs_open({restrict_sources={"rust"}})`
- `ApidocsSearch` (requires telescope.nvim or snacks.nvim) - open a picker to grep for text in all apidocs. If you want to display only a subset of sources, call the lua function: `:lua require("apidocs").apidocs_search({restrict_sources={"rust"}})`
- `ApidocsUninstall` - allows to uninstall sources. Press tab to get a completion on the available ones.

## Advanced usage

It is possible to follow links in docs. The links are numbered, `[1]`, `[2]` and so on. To follow links, you must open the document, viewing it in the picker is not enough. Once the doc is opened, position the cursor over the link, and press `*`. That will take you to the link text in the footer. If the link is a URL, open it as you would normally in neovim (probably `gx`). If it's another locally installed doc, the link will be `local://` and you can follow it using `<C-]>`.

When a link takes you to a specific part of a document, you may have to press `n` to get to the right spot, as we jump to the part based on text contents, doing a search in the file.

## Dependencies

This plugin requires:

- the [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) neovim plugin (optional, needed for preview and search)
- the [snacks.nvim](https://github.com/folke/snacks.nvim) neovim plugin (optional, needed for preview and search)
- the <https://github.com/rkd77/elinks> elinks TUI browser, to convert HTML
- ripgrep
- curl
- linux and probably OSX. Windows will not work, except maybe using WSL
- treesitter for html and markdown_inline, easiest way to get them is via [treesitter.nvim](https://github.com/nvim-treesitter/nvim-treesitter) plugin

## Lazy package manager setup

```lua
return {
  'emmanueltouzery/apidocs.nvim',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'nvim-telescope/telescope.nvim', -- or, 'folke/snacks.nvim'
  },
  cmd = { 'ApidocsSearch', 'ApidocsInstall', 'ApidocsOpen', 'ApidocsSelect', 'ApidocsUninstall' },
  config = function()
    require('apidocs').setup()
    -- Picker will be auto-detected. To select a picker of your choice explicitly you can set picker by the configuration option 'picker':
    -- require('apidocs').setup({picker = "snacks"})
    -- Possible options are 'ui_select', 'telescope', and 'snacks'
  end,
  keys = {
    { '<leader>sad', '<cmd>ApidocsOpen<cr>', desc = 'Search Api Doc' },
  },
}
```

## Extra screenshots

![basic screenshot](https://raw.githubusercontent.com/wiki/emmanueltouzery/apidocs.nvim/shot2.png)
![basic screenshot](https://raw.githubusercontent.com/wiki/emmanueltouzery/apidocs.nvim/shot3.png)

## Extension points

If you wish to integrate these docs with your own scripts or another picker, you can use the following functions exported by apidocs.nvim:

- `require("apidocs").data_folder()` -- the folder where the converted apidoc files can be found
- `require("apidocs").open_doc_in_new_window(docs_path)` -- open the documentation for a specific apidoc in a new window, where conceal and links navigation is properly set up
- `require("apidocs").open_doc_in_cur_window(docs_path)` -- open the documentation for a specific apidoc in the current window, with conceal and links navigation is properly set up. Compared to open_doc_in_new_window(), winfixbuf is not set.
- `require("apidocs").load_doc_in_buffer(buf, docs_path)` -- open the documentation for a specific apidoc in a buffer. You must set up conceal on the window yourself (conceallevel=2, concealcursor="n"). Link navigation is not set up, this is meant for a picker's preview not standalone display.
- `require("apidocs").ensure_install(langs)` -- install all languages in the provided array. E.g. if `langs` is `{ "lua~5.4", "rust" }` then the docs for Lua 5.4 and Rust will be installed. You can call this function after `setup()` in your configuration to ensure that your desired languages are available.

## Credits

Credits go to <https://github.com/luckasRanarison/nvim-devdocs> for the initial project which inspired this.
