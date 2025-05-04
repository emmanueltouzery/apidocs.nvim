local common = require("apidocs.common")
local install = require("apidocs.install")

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

local function open_doc_in_new_window(docs_path)
  -- create a new window and use winfixbuf on it, because i'll set
  -- conceallevel, and that's tied to the window (not the buffer),
  -- and is very invasive
  vim.cmd[[100vsplit]]
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = "n"
  vim.wo.winfixbuf = true
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
        load_doc_in_buffer(new_buf, common.data_folder() .. target .. ".html.md")
        buf_view_switch_to_new(new_buf)

      elseif #components == 3 then
        -- file name+section ID
        local new_buf = vim.api.nvim_create_buf(true, false)
        load_doc_in_buffer(new_buf, common.data_folder() .. components[1] .. "#" .. components[2] .. ".html.md")
        buf_view_switch_to_new(new_buf)
        vim.cmd("/" .. components[3])
        -- put the match at the top of the screen, then scroll up one line <C-y>
        vim.cmd("norm! zt | ")

      elseif #components == 4 then
        -- file name with two hashes+section ID (happens for lua)
        local new_buf = vim.api.nvim_create_buf(true, false)
        load_doc_in_buffer(new_buf, common.data_folder() .. components[1] .. "#" .. components[2] .. "#" .. components[3] .. ".html.md")
        buf_view_switch_to_new(new_buf)
        vim.cmd("/" .. components[4])
        -- put the match at the top of the screen, then scroll up one line <C-y>
        vim.cmd("norm! zt | ")
      end
    end
  end)
end

local function telescope_attach_mappings(prompt_bufnr, map)
  local actions = require('telescope.actions')
  map('i', '<cr>', function(nr)
    actions.close(prompt_bufnr)
    local entry = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
    open_doc_in_new_window(entry.filename or entry.value)
  end, {buffer = true})
  return true
end

local function apidocs_open(params, slugs_to_mtimes, candidates)
  local docs_path = common.data_folder()
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local previewers = require("telescope.previewers")
  local conf = require("telescope.config").values

  local function entry_maker(entry)
    return {
      value = docs_path .. entry.path,
      ordinal = entry.display,
      display = entry.display,
      contents = entry.display,
    }
  end

  pickers.new({}, {
    prompt_title = "API docs",
    finder = finders.new_table {
      results = candidates,
      entry_maker = entry_maker
    },
    previewer = previewers.new_buffer_previewer({
      -- messy because of the conceal
      setup = function(self)
        vim.schedule(function()
          local winid = self.state.winid
          vim.wo[winid].conceallevel = 2
          vim.wo[winid].concealcursor = "n"
          local augroup = vim.api.nvim_create_augroup('TelescopeApiDocsResumeConceal', { clear = true })
          vim.api.nvim_create_autocmd({"User"}, {
            group = augroup,
            pattern = "TelescopeResumePost",
            callback = function()
              local action_state = require("telescope.actions.state")
              local current_picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
              if current_picker.prompt_title == "API docs" or current_picker.prompt_title == "API docs search" then
                local winid = current_picker.all_previewers[1].state.winid
                vim.wo[winid].conceallevel = 2
                vim.wo[winid].concealcursor = "n"
              end
            end
          })
        end)
        return {}
      end,
      define_preview = function(self, entry)
        load_doc_in_buffer(self.state.bufnr, entry.value)
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = telescope_attach_mappings,
  }):find()
end

local function apidocs_search(opts)
  local previewers = require("telescope.previewers")
  local make_entry = require "telescope.make_entry"
  local folder = common.data_folder()
  if opts and opts.source then
    folder = folder .. opts.source .. "/"
  end
  local search_dirs = {folder}
  if opts and opts.restrict_sources then
    search_dirs = vim.tbl_map(function(d) return folder .. d end, opts.restrict_sources)
  end


  local default_entry_maker = make_entry.gen_from_vimgrep()
  local function entry_maker(entry)
    local r = default_entry_maker(entry)
      r.display = function(entry)
        local entry_components = vim.split(entry.filename:sub(#folder+1), "#")
        local source_length = entry_components[1]:find("/")
        local hl_group = {
          { {0, source_length}, "TelescopeResultsTitle"},
          { {source_length, #entry_components[1]}, "TelescopeResultsMethod" },
          { {#entry_components[1], #entry_components[1] + #(tostring(entry.lnum))+2}, "TelescopeResultsLineNr" },
        }
        return string.format("%s:%d: %s", entry_components[1], entry.lnum, entry.text), hl_group
      end
    return r
  end

  require('telescope.builtin').live_grep({
    cwd = folder,
    search_dirs = search_dirs,
    prompt_title = "API docs search",
    entry_maker = entry_maker,
    previewer = previewers.new_buffer_previewer({
      -- messy because of the conceal
      setup = function(self)
        vim.schedule(function()
          local winid = self.state.winid
          vim.wo[winid].conceallevel = 2
          vim.wo[winid].concealcursor = "n"
          local augroup = vim.api.nvim_create_augroup('TelescopeApiDocsResumeConceal', { clear = true })
          vim.api.nvim_create_autocmd({"User"}, {
            group = augroup,
            pattern = "TelescopeResumePost",
            callback = function()
              local action_state = require("telescope.actions.state")
              local current_picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
              if current_picker.prompt_title == "API docs" or current_picker.prompt_title == "API docs search" then
                local winid = current_picker.all_previewers[1].state.winid
                vim.wo[winid].conceallevel = 2
                vim.wo[winid].concealcursor = "n"
              end
            end
          })
        end)
        return {}
      end,
      define_preview = function(self, entry)
        load_doc_in_buffer(self.state.bufnr, entry.filename)

        local ns = vim.api.nvim_create_namespace('my_highlights')
        vim.api.nvim_buf_set_extmark(self.state.bufnr, ns, entry.lnum-1, 0, {
          end_line = entry.lnum,
          hl_group = 'TelescopePreviewMatch',
          strict = false,
        })
        vim.schedule(function()
          vim.api.nvim_buf_call(self.state.bufnr, function()
            vim.cmd(":" .. entry.lnum)
            vim.cmd("norm! zz")
          end)
        end)
      end,
    }),
    attach_mappings = telescope_attach_mappings,
  })
end

return {
  apidocs_open = apidocs_open,
  apidocs_search = apidocs_search,
  open_doc_in_new_window = open_doc_in_new_window,
}
