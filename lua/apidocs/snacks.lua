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

-- The layout comes from the call's opts, then from setup(), then the default.
-- A string is a snacks layout preset name ("ivy_split", "vertical"...), a table
-- is a full snacks layout config.
local function get_layout(opts)
  local layout = (opts and opts.layout) or (Config and Config.layout)
  if type(layout) == "string" then
    return { preset = layout }
  end
  return layout or common_layout_options
end

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
  new_item[#new_item + 1] = {
    common.filename_to_display(filename),
    "SnacksPickerFile",
    field = "file",
  }
  return new_item
end

-- A grep match inside a page's "Visible links" footer is a link to the thing
-- searched for, not a mention of it: every page linking to RidgeCV would list
-- one (147 of 258 scikit_learn hits). At this point item.text is
-- "file:line:col:text".
local function drop_link_footer_matches(item)
  local text = item.text:sub(#item.file + 2):match("^%d+:%d+:(.*)$")
  if text and common.link_footer_prefix(text) then
    return false
  end
end

local function apidocs_open(opts)
  Snacks.picker.files({
    layout = get_layout(opts),
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
    layout = get_layout(opts),
    win = common_win_options,
    dirs = get_data_dirs(opts),
    ft = { "markdown", "md" },
    transform = drop_link_footer_matches,
    confirm = function(picker, item)
      require("apidocs").open_doc_in_new_window(item.file)
    end,
    format = format_entries,
  })
end

return {
  apidocs_open = apidocs_open,
  apidocs_search = apidocs_search,
  drop_link_footer_matches = drop_link_footer_matches,
}
