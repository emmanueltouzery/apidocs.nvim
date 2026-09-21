-- Tests for what keeps repeated text out of search results.
-- Run from the repository root: nvim --headless -l tests/search_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local common = require("apidocs.common")
local sections = require("apidocs.sections")

local failures = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. "\n     " .. tostring(err))
  end
end

local function eq(actual, expected)
  if not vim.deep_equal(actual, expected) then
    error("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual), 2)
  end
end

-- link footer lines ----------------------------------------------------------

test("a numbered local link is a footer line", function()
  eq(
    common.link_footer_prefix("   1. local://scikit_learn/1.1. Linear Models##modules_linear_model\t+logistic"),
    "   1. local://"
  )
end)

test("a tab-indented local link is a footer line", function()
  eq(
    common.link_footer_prefix("\tlocal://scikit_learn/linear_model.RidgeCV()#x\t+sklearn.linear_model.RidgeCV"),
    "\tlocal://"
  )
end)

test("prose mentioning local:// is not a footer line", function()
  eq(common.link_footer_prefix(" >>> from sklearn.linear_model import RidgeCV  # local://"), nil)
end)

test("a numbered external link is not a local footer line", function()
  eq(common.link_footer_prefix("   2. https://example.com/RidgeCV"), nil)
end)

-- section ignore file --------------------------------------------------------

test("each section file becomes an anchored pattern, sorted", function()
  eq(
    sections.ignore_file({ "b#p#id.html", "a#p#id.html" }),
    "# section files repeat text from their page; keep them out of ripgrep\n/a#p#id.html.md\n/b#p#id.html.md\n"
  )
end)

test("glob metacharacters are escaped", function()
  eq(
    sections.ignore_file({ "x[1]*?{a,b}\\#p#id.html" }),
    sections.header .. "/x\\[1\\]\\*\\?\\{a,b\\}\\\\#p#id.html.md\n"
  )
end)

test("leading # and ! cannot be read as comment or negation", function()
  -- the leading slash already protects them
  eq(
    sections.ignore_file({ "#op#p#id.html", "!not#p#id.html" }),
    sections.header .. "/!not#p#id.html.md\n/#op#p#id.html.md\n"
  )
end)

test("no sections gives no patterns", function()
  eq(sections.ignore_file({}), sections.header)
end)

-- the ignore file really filters ripgrep, and fd still lists everything ------

test("rg skips listed sections while fd keeps them", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local names = { "page#p.html.md", "page#p#id [1].html.md" }
  for _, name in ipairs(names) do
    local f = assert(io.open(dir .. "/" .. name, "w"))
    f:write("needle\n")
    f:close()
  end
  sections.write(dir, { "page#p#id [1].html" })
  local rg = vim.system({ "rg", "-l", "needle", "." }, { cwd = dir, stdin = false }):wait()
  eq(vim.split(vim.trim(rg.stdout), "\n"), { "./page#p.html.md" })
  local fd_bin = vim.fn.executable("fd") == 1 and "fd" or "fdfind"
  local fd = vim.system({ fd_bin, "-t", "f", "." }, { cwd = dir }):wait()
  local listed = vim.split(vim.trim(fd.stdout), "\n")
  table.sort(listed)
  eq(listed, { "page#p#id [1].html.md", "page#p.html.md" })
  vim.fn.delete(dir, "rf")
end)

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
