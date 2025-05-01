local common = require("apidocs.common")
local install = require("apidocs.install")
local telescope = require("apidocs.telescope")

local function setup()
  vim.api.nvim_create_user_command("ApidocsInstall", install.apidocs_install, {})
  vim.api.nvim_create_user_command("ApidocsOpen", telescope.apidocs_open, {})
  vim.api.nvim_create_user_command("ApidocsSearch", telescope.apidocs_search, {})
  vim.api.nvim_create_user_command("ApidocsUninstall", function(args)
    vim.system({"rm", "-Rf", common.data_folder() .. args.fargs[1]}, {text = true}, function()
      vim.notify("Apidocs: removed source " .. args.fargs[1])
    end)
  end, {
    complete = function()
      local docs_path = common.data_folder()
      local fs = vim.uv.fs_scandir(docs_path)
      local installed_docs = {}
      while true do
        local name, type = vim.uv.fs_scandir_next(fs)
        if not name then break end
        if type == 'directory' then
          table.insert(installed_docs, name)
        end
      end
      return installed_docs
    end,
    nargs = 1,
  })
end

return {
  setup = setup,
  apidocs_install = install.apidocs_install,
  apidocs_open = telescope.apidocs_open,
  apidocs_search = telescope.apidocs_search,
}
