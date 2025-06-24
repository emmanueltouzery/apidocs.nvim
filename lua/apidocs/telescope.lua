local common = require("apidocs.common")
local install = require("apidocs.install")

local function telescope_attach_mappings(prompt_bufnr, map)
  local actions = require('telescope.actions')
  map('i', '<cr>', function(nr)
    actions.close(prompt_bufnr)
    local entry = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
    common.open_doc_in_new_window(entry.filename or entry.value)
    if entry.lnum then
      vim.cmd(":" .. entry.lnum)
      vim.cmd("norm! zz")
    end
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
        common.load_doc_in_buffer(self.state.bufnr, entry.value)
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
      local display = common.filename_to_display(entry.filename:sub(#folder+1))
      local source_length = display:find("/")
      local hl_group = {
        { {0, source_length}, "TelescopeResultsTitle"},
        { {source_length, #display}, "TelescopeResultsMethod" },
        { {#display, #display + #(tostring(entry.lnum))+2}, "TelescopeResultsLineNr" },
      }
      return string.format("%s:%d: %s", display, entry.lnum, entry.text), hl_group
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
        common.load_doc_in_buffer(self.state.bufnr, entry.filename)

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
}