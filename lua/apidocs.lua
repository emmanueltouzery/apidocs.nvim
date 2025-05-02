local common = require("apidocs.common")
local install = require("apidocs.install")
local telescope = require("apidocs.telescope")

local function apidocs_open(opts)
  local docs_path = common.data_folder()
  local fs = vim.uv.fs_scandir(docs_path)
  local candidates = {}
  local installed_docs = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(fs)
    if not name then break end
    if type == 'directory' then
      if params and params.restrict_sources then
        if vim.tbl_contains(params.restrict_sources, name) then
          table.insert(installed_docs, name)
        end
      else
        table.insert(installed_docs, name)
      end
    end
  end

  if params and params.ensure_installed then
    for _, source in ipairs(params.ensure_installed) do
      if not vim.tbl_contains(installed_docs, source) then
        if slugs_to_mtimes == nil then
          install.fetch_slugs_and_mtimes_and_then(function (slugs_to_mtimes)
            install.apidoc_install(source, slugs_to_mtimes, function()
              apidocs_open(params, slugs_to_mtimes)
            end)
          end)
          return
        else
          install.apidoc_install(source, slugs_to_mtimes, function()
              apidocs_open(params, slugs_to_mtimes)
          end)
          return
        end
      end
    end
  end

  for _, name in ipairs(installed_docs) do
    local fs2 = vim.uv.fs_scandir(docs_path .. "/" .. name)
    while true do
      local name2, type2 = vim.uv.fs_scandir_next(fs2)
      if not name2 then break end
      if type2 == 'file' and vim.endswith(name2, ".html.md") then
        local name_no_txt = name2:gsub("#.*$", "")
        table.insert(candidates, {display = name .. "/" .. name_no_txt, path = name .. "/" .. name2})
      end
    end
  end

  if opts and opts.use_ui_select then
    local display_list = vim.tbl_map(function(c) return c.display end, candidates)
    local path_list = vim.tbl_map(function(c) return c.path end, candidates)
    vim.ui.select(display_list, {prompt="Pick a documentation to view"}, function(item, idx)
      if item ~= nil then
        telescope.open_doc_in_new_window(docs_path .. path_list[idx])
      end
    end)
  else
    telescope.apidocs_open(params, slugs_to_mtimes, candidates)
  end
end

local function setup()
  vim.api.nvim_create_user_command("ApidocsInstall", install.apidocs_install, {})
  vim.api.nvim_create_user_command("ApidocsOpen", apidocs_open, {})
  vim.api.nvim_create_user_command("ApidocsSelect", function()
    apidocs_open({use_ui_select = true})
  end, {})
  vim.api.nvim_create_user_command("ApidocsSearch", telescope.apidocs_search, {})
  vim.api.nvim_create_user_command("ApidocsUninstall", function(args)
    vim.system({"rm", "-Rf", common.data_folder() .. args.fargs[1]}, {text = true}, vim.schedule_wrap(function()
      vim.notify("Apidocs: removed source " .. args.fargs[1])
    end))
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
  apidocs_open = apidocs_open,
  apidocs_search = telescope.apidocs_search,
}
