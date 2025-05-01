local common = require("apidocs.common")

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

local function telescope_attach_mappings(prompt_bufnr, map)
  local actions = require('telescope.actions')
  map('i', '<cr>', function(nr)
    actions.close(prompt_bufnr)
    -- create a new window and use winfixbuf on it, because i'll set
    -- conceallevel, and that's tied to the window (not the buffer),
    -- and is very invasive
    vim.cmd[[100vsplit]]
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf)
    local entry = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
    local docs_path = entry.value
    if entry.filename then
      -- search
      docs_path = entry.cwd .. "/" .. entry.filename
    else
    end
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

        elseif #components == 4 then
          -- file name with two hashes+section ID (happens for lua)
          local new_buf = vim.api.nvim_create_buf(true, false)
          load_doc_in_buffer(new_buf, common.data_folder() .. components[1] .. "#" .. components[2] .. "#" .. components[3] .. ".html.md")
          buf_view_switch_to_new(new_buf)
          vim.cmd("/" .. components[4])
        end
      end
    end, {buffer = true})
  end)
  return true
end

local function apidocs_open(params, slugs_to_mtimes)
  local docs_path = common.data_folder()
  local fs = vim.uv.fs_scandir(docs_path)
  local candidates = {}
  local installed_docs = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(fs)
    if not name then break end
    if type == 'directory' then
      table.insert(installed_docs, name)
    end
  end

  if params and params.ensure_installed then
    for _, source in ipairs(params.ensure_installed) do
      if not vim.tbl_contains(installed_docs, source) then
        if slugs_to_mtimes == nil then
          fetch_slugs_and_mtimes_and_then(function (slugs_to_mtimes)
            apidoc_install(source, slugs_to_mtimes, function()
              apidocs_open(params, slugs_to_mtimes)
            end)
          end)
          return
        else
          apidoc_install(source, slugs_to_mtimes, function()
              apidocs_open(params, slugs_to_mtimes)
          end)
          return
        end
      end
    end
  end

  for _, name in ipairs(installed_docs) do
    local fs2 = vim.uv.fs_scandir(docs_path .. "/" .. name)
    while true do
      local name2, type2 = vim.uv.fs_scandir_next(fs2)
      if not name2 then break end
      if type2 == 'file' and vim.endswith(name2, ".html.md") then
        local name_no_txt = name2:gsub("#.*$", "")
        table.insert(candidates, {display = name .. "/" .. name_no_txt, path = name .. "/" .. name2})
      end
    end
  end

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
  local folder = common.data_folder()
  if opts and opts.source then
    folder = folder .. opts.source .. "/"
  end
  require('telescope.builtin').live_grep({
    cwd = folder,
    prompt_title = "API docs search",
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
        load_doc_in_buffer(self.state.bufnr, folder .. entry.filename)

        local ns = vim.api.nvim_create_namespace('my_highlights')
        vim.api.nvim_buf_set_extmark(self.state.bufnr, ns, entry.lnum-1, 0, {
          end_line = entry.lnum,
          hl_group = 'TelescopePreviewMatch',
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
