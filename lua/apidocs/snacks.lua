local common = require("apidocs.common")
local Snacks = require("snacks")

local common_layout_options = {
  preview = true,
  preset = "telescope",
}
local common_win_options = {
  preview = {
    wo = {
      number = true,
      relativenumber = false,
      signcolumn = "no",
      conceallevel = 2,
      concealcursor = "n",
      winfixbuf = true,
      list = false,
      wrap = false,
    },
  },
}

local function get_data_dirs(opts)
  local data_dir = common.data_folder()
  if not (opts and opts.restrict_sources) then
    return { data_dir }
  end
  local dirs = {}
  for _, source in ipairs(opts.restrict_sources) do
    local dir = data_dir .. source .. "/"
    if vim.fn.isdirectory(dir) == 1 then
      table.insert(dirs, dir)
    end
  end
  return dirs
end

local function format_entries(item, picker)
  local parts = vim.split(item.file, "/")
  -- take the last part and set it as the text
  local folder = parts[#parts - 1]
  local filename = parts[#parts]
  local filetype = vim.split(folder, "~")[1]
  local icon, hl = Snacks.util.icon(filetype, "filetype", {
    fallback = picker.opts.icons.files,
  })
  icon = Snacks.picker.util.align(icon, picker.opts.formatters.file.icon_width or 2)
  filename = filename:gsub("%.html%.md$", "")
  local new_item = {
    {
      icon,
      hl,
      virtual = true,
    },
    {
      folder .. " | ",
      "SnacksPickerSpecial",
      field = "file",
    },
  }
  local fileNameParts = vim.split(filename, "#")
  new_item[#new_item + 1] = {
    fileNameParts[1],
    "SnacksPickerFile",
    field = "file",
  }
  return new_item
end

local function apidocs_open(opts)
  Snacks.picker.files({
    layout = common_layout_options,
    win = common_win_options,
    dirs = get_data_dirs(opts),
    ft = { "markdown", "md" },
    confirm = function(picker, item)
      require("apidocs").open_doc_in_new_window(item.file)
    end,
    format = format_entries,
  })
end

local function apidocs_search(opts)
  Snacks.picker.grep({
    layout = common_layout_options,
    win = common_win_options,
    dirs = get_data_dirs(opts),
    ft = { "markdown", "md" },
    confirm = function(picker, item)
      require("apidocs").open_doc_in_new_window(item.file)
    end,
    format = format_entries,
  })
end

local function apidocs_install()
  -- might not work, have no way of testing it
  local install = require("apidocs.install")

  if vim.fn.executable("elinks") ~= 1 or vim.fn.executable("rg") ~= 1 or vim.fn.executable("find") ~= 1 then
    print("The 'elinks', 'rg' and 'find' programs must be installed to proceed, refusing to run.")
  else
    install.fetch_slugs_and_mtimes_and_then(function (slugs_to_mtimes)
      local keys = vim.tbl_keys(slugs_to_mtimes)
      table.sort(keys)
      Snacks.picker({
        title = "API docs install",
        layout = common_layout_options,
        win = common_win_options,
        items = keys,
        on_select = function(choice)
          if choice == nil then
            return
          end
          install.apidoc_install(choice[1], slugs_to_mtimes)
        end,
        format = format_entries,
      })

    end)
  end
end

return {
  apidocs_open = apidocs_open,
  apidocs_search = apidocs_search,
  apidocs_install = apidocs_install,
}
