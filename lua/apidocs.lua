local function apidocs_install()
  local data_folder = vim.fn.stdpath("data") .. "/apidocs-data/"

  vim.system({"curl", "-L", "https://devdocs.io/docs.json"}, {text=true}, vim.schedule_wrap(function(res)
    local data = vim.fn.json_decode(res.stdout)
    local slugs_to_mtimes = {}
    for _, doc in ipairs(data) do
      slugs_to_mtimes[doc['slug']] = doc['mtime']
    end
    local keys = vim.tbl_keys(slugs_to_mtimes)
    table.sort(keys)
    vim.ui.select(keys, {prompt="Pick a documentation to install"}, function(choice)
      vim.notify("Fetching documentation for " .. choice)
      if choice == nil then
        return
      end
      vim.fn.mkdir(data_folder, "p")
      local elinks_conf_path = data_folder .. "elinks.conf"
      if vim.fn.filereadable(elinks_conf_path) ~= 1 then
        local file = io.open(elinks_conf_path, "w")
        -- nice table borders
        file:write("set terminal._template_.type = 2\n")
        file:close()
      end
      local start_install = vim.loop.hrtime()
      local mtime = slugs_to_mtimes[choice]
      vim.system({"curl", "-L", "https://documents.devdocs.io/" .. choice .. "/index.json?" .. mtime}, {text=true}, vim.schedule_wrap(function(res)
        local data = vim.fn.json_decode(res.stdout)
        local name_to_path = {}
        local path_to_name = {}
        local known_keys_per_path = {}
        for _, entry in ipairs(data["entries"]) do
          name_to_path[entry.name] = entry.path
          path_to_name[entry.path] = entry.name

          local file_id = vim.split(entry.path, "#")
          if #file_id == 2 then
            path_to_name[entry.path] = entry.name
            local sanitized_fname = file_id[1]:gsub("/", "_")
            if known_keys_per_path[file_id[1]] == nil then
              known_keys_per_path[file_id[1]] = {[file_id[2]] = true}
            else
              known_keys_per_path[file_id[1]][file_id[2]] = true
            end
          end
        end

        vim.system({"curl", "-L", "https://documents.devdocs.io/" .. choice .. "/db.json?" .. mtime}, {text=true}, vim.schedule_wrap(function(res)
          local data = vim.fn.json_decode(res.stdout)
          local target_path = data_folder .. choice
          vim.system({"sh", "-c", "rm -Rf " .. target_path}):wait()
          vim.fn.mkdir(target_path, "p")
          local name_and_id_to_pos = {}
          local name_known_byte_offsets = {}
          local name_to_contents = {}

          local query = vim.treesitter.query.parse('html', [[
          (attribute
            (attribute_name) @_name
            (#eq? @_name "id")
          )
          ]])
          all_parsing = 0
          all_reading_ids = 0

          -- save all the files
          for _, key in ipairs(vim.tbl_keys(data)) do
            local sanitized_key = ((path_to_name[key] or key) .. "#" .. key):gsub("/", "_")
            local file = io.open(target_path .. "/" .. sanitized_key  .. ".html", "w")
            contents = data[key]:gsub("<pre [^<>]*data%-language=\"(%w+)\">", "<pre>\n```%1\n")
            contents = contents:gsub("</pre>", "\n```\n</pre>")
            contents = contents:gsub("<td class=.font%-monospace.>([^<]+)</td>", "<td>`%1`</td>")
            contents = contents:gsub("<code>([^<]+)</code>", "<code>`%1`</code>")
            contents = contents:gsub("<table", "<table border=\"1\"")
            file:write(contents)
            file:close()

            local start_parse = vim.loop.hrtime()
            local parser = vim.treesitter.get_string_parser(contents, "html")
            local tree = parser:parse()[1]
            local elapsed = (vim.loop.hrtime() - start_parse) / 1e9
            all_parsing = all_parsing + elapsed

            name_to_contents[sanitized_key] = contents
            name_and_id_to_pos[sanitized_key] = {}
            name_known_byte_offsets[sanitized_key] = {#contents}

            local start_ids = vim.loop.hrtime()
            if known_keys_per_path[key] ~= nil then
              for id, node, metadata in query:iter_captures(tree:root(), contents) do
                id_val = vim.treesitter.get_node_text(node:next_named_sibling():named_child(), contents)
                if known_keys_per_path[key][id_val] then
                  _, _, byte_pos = node:parent():parent():start()
                  name_and_id_to_pos[sanitized_key][id_val] = byte_pos
                  table.insert(name_known_byte_offsets[sanitized_key], byte_pos)
                end
              end
            end
            all_reading_ids = all_reading_ids + elapsed

            -- need to sort offsets, later i search for the byte offset after my current one
            -- to know where to stop when extracting docs from a larger file
            table.sort(name_known_byte_offsets[sanitized_key])
          end

          -- now extract all the entries to non-html files
          local start_writing = vim.loop.hrtime()
          for name, path in pairs(name_to_path) do
            local file_id = vim.split(path, "#")
            local sanitized_containing_file_name = ((path_to_name[file_id[1]] or file_id[1]) .. "#" .. file_id[1]):gsub("/", "_")
            local sanitized_fname = name:gsub("/", "_")
            if #file_id == 2 then
              local byte = name_and_id_to_pos[sanitized_containing_file_name][file_id[2]]
              local to_write_contents = nil
              if byte == nil then
                -- bad id. this happens with openjdk~8, Vector.add() for instance. Behave the same
                -- as the devdocs UI, point to the whole file since we can't delimitate the correct subpart.
                to_write_contents = name_to_contents[sanitized_containing_file_name]
              else
                local next_byte = nil
                for i,val in ipairs(name_known_byte_offsets[sanitized_containing_file_name]) do
                  if val == byte then
                    next_byte = name_known_byte_offsets[sanitized_containing_file_name][i+1]
                  end
                end
                to_write_contents = string.sub(name_to_contents[sanitized_containing_file_name], byte, next_byte)
              end
              local sanitized_name = name:gsub("/", "_")
              local file = io.open(target_path .. "/" .. sanitized_name .. "#" .. file_id[1]:gsub("/", "_") .. ".html", "w")
              file:write(to_write_contents)
              file:close()
            end
          end
          local elapsed_writing = (vim.loop.hrtime() - start_writing) / 1e9

          local start_elinks = vim.loop.hrtime()
          -- convert the html to text, on 8 processes concurrently (-P8)
          vim.system({
            "sh", "-c",
            [[find . -maxdepth 1 -name '*.html' -print0 | xargs -0 -P 8 -I param sh -c "elinks -config-dir ]] .. data_folder .. [[ -dump 'param' > 'param'.md"]]
          }, {cwd=target_path}):wait()
          local elapsed_elinks = (vim.loop.hrtime() - start_elinks) / 1e9
          local elapsed = (vim.loop.hrtime() - start_install) / 1e9
          vim.notify("Finished fetching documentation for " .. choice .. " in " .. elapsed .. "s. All parsing: " .. all_parsing .. "s. All reading IDs: " .. all_reading_ids .. "s. All writing: " .. elapsed_writing .. "s. All elinks: " .. elapsed_elinks .. "s.")
        end))
      end))
    end)
  end))
end

local function apidocs_open()
  local docs_path = vim.fn.stdpath("data") .. "/apidocs-data/"
  local fs = vim.uv.fs_scandir(docs_path)
  local candidates = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(fs)
    if not name then break end
    if type == 'directory' then
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
          vim.wo[winid].conceallevel = 1 -- if we set to 3, table borders don't line up anymore
          vim.wo[winid].concealcursor = "n"
        end)
        return {}
      end,
      define_preview = function(self, entry)
        local filepath = entry.value
        if vim.fn.filereadable(filepath) == 1 then
          local lines = {}
          for line in io.lines(filepath) do
            table.insert(lines, line)
          end
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

          vim.bo[self.state.bufnr].filetype = "markdown"
        else
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "File not readable: " .. filepath })
        end

      end,
    }),
    sorter = conf.generic_sorter({}),
  }):find()
end

return {
  apidocs_install = apidocs_install,
  apidocs_open = apidocs_open,
}
