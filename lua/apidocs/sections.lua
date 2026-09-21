-- Keep section files out of ripgrep searches.
--
-- The installer writes every devdocs page whole, then writes each index entry
-- that points inside a page ("page#id") again, as a slice of that page. Those
-- section files are what the open picker lists, but for a text search they are
-- copies: every line in a section also sits in its page, so one match showed up
-- two or three times (measured on scikit_learn: 784 hits for "fit_transform",
-- 490 once sections are skipped; rust "HashMap": 1182 -> 706).
--
-- The installer therefore lists its section files in <source>/.rgignore.
-- ripgrep reads that file and skips them; fd (the open picker's lister) does
-- not read .rgignore, so opening a section by name keeps working. A search hit
-- lands in the page, with the whole page around it.

local M = {}

M.name = ".rgignore"
M.header = "# section files repeat text from their page; keep them out of ripgrep\n"

-- gitignore glob syntax: escape everything a file name could make special.
local function escape_glob(name)
  return (name:gsub("([\\%[%]%*%?{}])", "\\%1"))
end

--- The .rgignore contents for the given section files, named as the installer
--- writes them (`….html`); elinks later turns each into `….html.md`.
---@param html_names string[]
---@return string
function M.ignore_file(html_names)
  local names = vim.deepcopy(html_names)
  table.sort(names)
  local lines = { M.header }
  for _, name in ipairs(names) do
    -- The leading slash anchors the pattern to this folder and also stops a
    -- name starting with "#" or "!" being read as a comment or a negation.
    table.insert(lines, "/" .. escape_glob(name) .. ".md\n")
  end
  return table.concat(lines)
end

---@param dir string the source folder
---@param html_names string[]
function M.write(dir, html_names)
  local file = assert(io.open(dir .. "/" .. M.name, "w"))
  file:write(M.ignore_file(html_names))
  file:close()
end

return M
