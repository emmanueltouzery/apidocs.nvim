local common = require("apidocs.common")
local install = require("apidocs.install")

Config = {}

local function set_picker(opts)
  if opts and (opts.picker == "snacks" or opts.picker == "telescope" or opts.picker == "ui_select") then
    return opts
  end
  if not opts then
    opts = {}
  end
  if package.loaded["snacks"] then
    opts.picker = "snacks"
    return opts
  end
  if package.loaded["telescope"] then
    opts.picker = "telescope"
    return opts
  end
  opts.picker = "ui_select"
  return opts
end

local function get_installed_docs(opts)
  local docs_path = common.data_folder()
  local fs = vim.uv.fs_scandir(docs_path)
  local installed_docs = {}
  if fs == nil then
    return installed_docs
  end
  while true do
    local name, type = vim.uv.fs_scandir_next(fs)
    if not name then
      break
    end
    if type == "directory" then
      if opts and opts.restrict_sources then
        if vim.tbl_contains(opts.restrict_sources, name) then
          table.insert(installed_docs, name)
        end
      else
        table.insert(installed_docs, name)
      end
    end
  end
  return installed_docs
end

local apidocs_open -- forward declaration

local function ensure_install_and_then(languages, cont)
  local installed_docs = get_installed_docs()
  local pending_installation = 0
  -- count items to install
  for _, source in ipairs(languages) do
    if not vim.tbl_contains(installed_docs, source) then
      pending_installation = pending_installation + 1
    end
  end

  local function after_install()
    pending_installation = pending_installation - 1
    if pending_installation == 0 then
      cont(slugs_to_mtimes)
    end
  end

  for _, source in ipairs(languages) do
    if not vim.tbl_contains(installed_docs, source) then
      if slugs_to_mtimes == nil then
        install.fetch_slugs_and_mtimes_and_then(function(slugs_to_mtimes)
          install.apidoc_install(source, slugs_to_mtimes, after_install)
        end)
      else
        install.apidoc_install(source, slugs_to_mtimes, after_install)
      end
    end
  end
end

local function ensure_install(languages)
  ensure_install_and_then(languages, function()
    vim.notify("Apidocs ensure_install complete!")
  end)
end

function apidocs_open(opts)
  local picker = Config.picker
  if opts and opts.picker then
    picker = opts.picker
  end

  local docs_path = common.data_folder()
  local candidates = {}
  local installed_docs = get_installed_docs(opts)

  if opts and opts.ensure_installed then
    return ensure_install_and_then(opts.ensure_installed, function()
      -- call apidocs_open() again, but remove ensure_installed from opts
      -- otherwise this would loop infinitely
      local new_opts = { picker = opts.picker }
      apidocs_open(new_opts)
    end)
  end

  if picker == "snacks" then
    require("apidocs.snacks").apidocs_open(opts)
    return
  end

  for _, name in ipairs(installed_docs) do
    local fs2 = vim.uv.fs_scandir(docs_path .. "/" .. name)
    while true do
      local name2, type2 = vim.uv.fs_scandir_next(fs2)
      if not name2 then
        break
      end
      if type2 == "file" and vim.endswith(name2, ".html.md") then
        local name_no_txt = name2:gsub("#.*$", "")
        table.insert(candidates, { display = name .. "/" .. name_no_txt, path = name .. "/" .. name2 })
      end
    end
  end

  if picker == "ui_select" then
    local display_list = vim.tbl_map(function(c)
      return c.display
    end, candidates)
    local path_list = vim.tbl_map(function(c)
      return c.path
    end, candidates)
    vim.ui.select(display_list, { prompt = "Pick a documentation to view" }, function(item, idx)
      if item ~= nil then
        common.open_doc_in_new_window(docs_path .. path_list[idx])
      end
    end)
  else
    require("apidocs.telescope").apidocs_open(opts, slugs_to_mtimes, candidates)
  end
end

local function apidocs_search(opts)
  local picker = Config.picker
  if opts and opts.picker then
    picker = opts.picker
  end
  if picker == "ui_select" then
    vim.notify("Apidocs: ui_select picker does not support search", vim.log.levels.ERROR)
    return
  end
  if picker == "snacks" then
    require("apidocs.snacks").apidocs_search(opts)
    return
  end
  if picker == "telescope" then
    require("apidocs.telescope").apidocs_search(opts)
    return
  end
end

local function set_config(opts)
  Config = set_picker(opts)
end

local function setup(conf)
  set_config(conf)
  vim.api.nvim_create_user_command("ApidocsInstall", install.apidocs_install, {})
  vim.api.nvim_create_user_command("ApidocsOpen", apidocs_open, {})
  vim.api.nvim_create_user_command("ApidocsSearch", apidocs_search, {})
  vim.api.nvim_create_user_command("ApidocsUninstall", function(args)
    vim.system(
      { "rm", "-Rf", common.data_folder() .. args.fargs[1] },
      { text = true },
      vim.schedule_wrap(function()
        vim.notify("Apidocs: removed source " .. args.fargs[1])
      end)
    )
  end, {
    complete = function()
      local docs_path = common.data_folder()
      local fs = vim.uv.fs_scandir(docs_path)
      local installed_docs = {}
      while true do
        local name, type = vim.uv.fs_scandir_next(fs)
        if not name then
          break
        end
        if type == "directory" then
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
  config = Config,
  apidocs_install = install.apidocs_install,
  apidocs_open = apidocs_open,
  apidocs_search = apidocs_search,
  ensure_install = ensure_install,
  data_folder = common.data_folder,
  open_doc_in_new_window = common.open_doc_in_new_window,
  open_doc_in_cur_window = common.open_doc_in_cur_window,
  load_doc_in_buffer = common.load_doc_in_buffer,
}
