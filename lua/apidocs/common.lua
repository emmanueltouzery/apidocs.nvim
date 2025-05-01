local function data_folder()
  return vim.fn.stdpath("data") .. "/apidocs-data/"
end

-- https://stackoverflow.com/a/34953646/516188
local function escape_pattern(text)
    return text:gsub("([^%w])", "%%%1")
end

return {
  data_folder = data_folder,
  escape_pattern = escape_pattern,
}
