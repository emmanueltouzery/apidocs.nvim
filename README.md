# Apidocs.nvim

This is an integration of <https://devdocs.io/> in neovim.

This plugin will download devdocs documentations for offline usage and pre-format them for in-neovim display.
It will also extract the documentation for individual methods (`List.add()`...) for nicer browsing, and leverages neovim conceal features for a user-friendly display.

![basic screenshot](https://raw.githubusercontent.com/wiki/emmanueltouzery/apidocs.nvim/shot1.png)

## How to use

Call `require("apidocs").setup()` when installing the plugin to register the commands.

The plugin exports the following commands:

- `ApidocsInstall` - will fetch the list of supported documentation sources (lua, openjdk, rust...) from devdocs.io and ask you which one you wish to install. Note that downloading+installing can take over a minute and WILL TEMPORARILY FREEZE YOUR NEOVIM. This is because the plugin leverages neovim's tree-sitter to post-process the files. This happens only when installing a source, and never again after that.
- `ApidocsOpen` - open a picker listing all apidocs. If you want to display only a subset of sources, call the lua function: `:lua require("apidocs").apidocs_open({restrict_sources={"rust"}})`. You can also use the option `ensure_installed` to list sources that should be automatically installed. They'll be fetched next time you open the picker.
- `ApidocsSearch` - open a picker to grep for text in all apidocs. If you want to display only a subset of sources, call the lua function: `:lua require("apidocs").apidocs_search({restrict_sources={"rust"}})`
- `ApidocsUninstall` - allows to uninstall sources. Press tab to get a completion on the available ones.

## Advanced usage

It is possible to follow links in docs. The links are numbered, `[1]`, `[2]` and so on. To follow links, you must open the document, viewing it in the picker is not enough. Once the doc is opened, position the cursor over the link, and press `*`. That will take you to the link text in the footer. If the link is a URL, open it as you would normally in neovim (probably `gx`). If it's another locally installed doc, the link will be `local://` and you can follow it using `<C-]>`.

When a link takes you to a specific part of a document, you may have to press `n` to get to the right spot, as we jump to the part based on text contents, doing a search in the file.

## Dependencies

This plugin requires:

- the telescope.nvim neovim plugin
- the <https://github.com/rkd77/elinks> elinks TUI browser, to convert HTML
- ripgrep
- curl
- linux and probably OSX. Windows will not work, except maybe using WSL

## Extra screenshots

![basic screenshot](https://raw.githubusercontent.com/wiki/emmanueltouzery/apidocs.nvim/shot2.png)
![basic screenshot](https://raw.githubusercontent.com/wiki/emmanueltouzery/apidocs.nvim/shot3.png)

## Credits

Credits go to <https://github.com/luckasRanarison/nvim-devdocs> for the initial project which inspired this.
