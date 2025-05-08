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
  local install_dirs = vim.fn.readdir(data_dir)
  for _, source in ipairs(opts.restrict_sources) do
    for _, entry in ipairs(install_dirs) do
      if vim.fn.isdirectory(data_dir .. entry) == 1 then
        if entry == source then
          table.insert(dirs, data_dir .. entry .. "/")
        elseif entry:match("^" .. source) then
          -- no exact match found, check for a partial match
          table.insert(dirs, data_dir .. entry .. "/")
        end
      end
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

return {
  apidocs_open = apidocs_open,
  apidocs_search = apidocs_search,
}
