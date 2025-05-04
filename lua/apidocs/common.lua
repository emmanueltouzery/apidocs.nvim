local function data_folder()
  return vim.fn.stdpath("data") .. "/apidocs-data/"
end

-- https://stackoverflow.com/a/34953646/516188
local function escape_pattern(text)
    return text:gsub("([^%w])", "%%%1")
end

local function load_doc_in_buffer(buf, filepath)
  if vim.fn.filereadable(filepath) == 1 then
    local lines = {}
    for line in io.lines(filepath) do
      -- nbsp so that neovim doesn't highlight this as a quoted paragraph
      table.insert(lines, (line:gsub("^    ", "    ")))
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.bo[buf].filetype = "markdown"
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "File not readable: " .. filepath })
  end
end

local function buf_view_switch_to_new(new_buf)
  vim.wo.winfixbuf = false
  vim.api.nvim_win_set_buf(0, new_buf)
  vim.api.nvim_buf_set_option(0, 'modifiable', false)
  vim.wo.winfixbuf = true
  vim.wo.wrap = false
  vim.bo.modified = false

  vim.keymap.set("n", "<C-o>", function()
    vim.wo.winfixbuf = false
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-o>", true, false, true), "n", true)
    vim.defer_fn(function()
      vim.wo.winfixbuf = true
    end, 100)
  end, {buffer = true})
end

local function open_doc_in_cur_window(docs_path)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = "n"
  vim.wo.list = false
  load_doc_in_buffer(buf, docs_path)
  vim.api.nvim_buf_set_option(0, 'modifiable', false)
  vim.wo.wrap = false
  vim.bo.modified = false

  vim.keymap.set("n", "<C-]>", function()
    local line = vim.api.nvim_buf_get_lines(0, vim.fn.line(".")-1, vim.fn.line("."), false)[1]
    local m = string.match(line, "^%s+%d+%. local://")
    if m == nil and vim.startswith(line, "\tlocal://") then
      -- sometimes the format is not "number. link", but "number. desc\n\tlink". maybe when the link has
      -- a description? this happens with rust
      m = string.match(line, "^\tlocal://")
    end
    if m then
      -- when parsing the local:// url, drop "<tab>+" text at the end,
      -- we add this marker when we can't resolve the ID reference
      local target = line:sub(#m+1):gsub("\t%+.+$", "")
      local components = vim.split(target, "#")
      if #components == 2 then
        -- plain file name
        local new_buf = vim.api.nvim_create_buf(true, false)
        load_doc_in_buffer(new_buf, data_folder() .. target .. ".html.md")
        buf_view_switch_to_new(new_buf)

      elseif #components == 3 then
        -- file name+section ID
        local new_buf = vim.api.nvim_create_buf(true, false)
        load_doc_in_buffer(new_buf, data_folder() .. components[1] .. "#" .. components[2] .. ".html.md")
        buf_view_switch_to_new(new_buf)
        vim.cmd("/" .. components[3])
        -- put the match at the top of the screen, then scroll up one line <C-y>
        vim.cmd("norm! zt | ")

      elseif #components == 4 then
        -- file name with two hashes+section ID (happens for lua)
        local new_buf = vim.api.nvim_create_buf(true, false)
        load_doc_in_buffer(new_buf, data_folder() .. components[1] .. "#" .. components[2] .. "#" .. components[3] .. ".html.md")
        buf_view_switch_to_new(new_buf)
        vim.cmd("/" .. components[4])
        -- put the match at the top of the screen, then scroll up one line <C-y>
        vim.cmd("norm! zt | ")
      end
    end
  end)
end

local function open_doc_in_new_window(docs_path)
  -- create a new window and use winfixbuf on it, because i'll set
  -- conceallevel, and that's tied to the window (not the buffer),
  -- and is very invasive
  vim.cmd[[100vsplit]]
  open_doc_in_cur_window(docs_path)
  vim.wo.winfixbuf = true
end


return {
  data_folder = data_folder,
  escape_pattern = escape_pattern,
  load_doc_in_buffer = load_doc_in_buffer,
  open_doc_in_cur_window = open_doc_in_cur_window,
  open_doc_in_new_window = open_doc_in_new_window,
}
