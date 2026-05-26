local common = require("apidocs.common")
local MiniPick = require("mini.pick")

local function parse_grep_item(item, cwd)
  if type(item) ~= "string" then return nil end

  local parts = vim.split(item, "\000")
  local rel_path = parts[1]

  if not rel_path then return nil end

  local abs_path = cwd .. "/" .. rel_path
  return vim.fs.normalize(abs_path)
end

local function format_entries(item, cwd)
  local raw_path = item
  local match_text = ""

  if type(item) == "string" and item:find("\000") then
    local parts = vim.split(item, "\000")
    raw_path = parts[1]
    match_text = parts[4] or ""
  end

  local parts = vim.split(raw_path, "/")
  local folder = parts[#parts - 1] or ""
  local filename = parts[#parts] or ""
  filename = filename:gsub("%.html%.md$", "")

  local display_name = common.filename_to_display(filename)

  if match_text ~= "" then
    return string.format(
      "%s │ %s ──> %s",
      folder,
      display_name,
      match_text
    )
  else
    return string.format("%s │ %s", folder, display_name)
  end
end

local function apidocs_open(opts)
  local cwd = common.get_data_dirs(opts)[1] or common.data_folder()

  MiniPick.builtin.files({
    globs = { "*.md", "*.markdown" },
  }, {
    source = {
      name = "API Docs (open)",
      cwd = cwd,
      format = format_entries,
      choose = function(item)
        local filepath = type(item) == "table" and item.path or item
        require("apidocs").open_doc_in_new_window(filepath)
      end,
    },
    options = {
      use_cache = true,
    },
  })
end

local function apidocs_search(opts)
  local cwd = common.get_data_dirs(opts)[1] or common.data_folder()

  MiniPick.builtin.grep_live({}, {
    source = {
      name = "API Docs (grep)",
      cwd = cwd,
      format = format_entries,
      choose = function(item)
        local filepath = parse_grep_item(item, cwd)
        if filepath then
          require("apidocs").open_doc_in_new_window(filepath)
        end
      end,
    },
  })
end

return {
  apidocs_open = apidocs_open,
  apidocs_search = apidocs_search,
}
