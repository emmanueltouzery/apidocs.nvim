local function data_folder()
  return vim.fn.stdpath("data") .. "/apidocs-data/"
end

-- https://stackoverflow.com/a/34953646/516188
local function escape_pattern(text)
    return text:gsub("([^%w])", "%%%1")
end

local function sanitize_fname(fname)
  return fname:gsub("/", "_"):gsub("'", "_")
end

-- if the line contains table cells it's sensitive to alignment...
-- in that case compensate the neovim conceal that hides the ` and other characters
-- by adding extra spaces not to break the table borders alignment.
local function add_spaces_to_compensate_conceals_cols(lines)
  local lines_str = vim.fn.join(lines, "\n")

  local query = vim.treesitter.query.parse('markdown_inline', [[[
    (code_span_delimiter) (emphasis_delimiter)
    (full_reference_link
      [
        "["
      ])
     (shortcut_link
       [
         "["
       ])
     (collapsed_reference_link
       [
         "["
       ])
     (inline_link
       [
         "["
         "("
         (link_destination)
       ])
      (image
        [
          "!"
          "["
          "("
          (link_destination)
        ])
    ] @concealed]])

  local parser = vim.treesitter.get_string_parser(lines_str, "markdown")
  parser:parse(true)

  parser:for_each_tree(function(tree)
    local pos_to_insert = {}
    for id, node, metadata in query:iter_captures(tree:root(), lines) do
      local row, col, bytes = node:start()
      if lines[row+1]:match("│") then
        table.insert(pos_to_insert, {row, col, bytes})
      end
    end
    -- go from the end because inserting is going to move offsets
    for i = #pos_to_insert, 1, -1 do
      local row, col, bytes = unpack(pos_to_insert[i])
      lines[row+1] = lines[row+1]:sub(1, col) .. " " .. lines[row+1]:sub(col+1)
    end
  end)

  local lines_str = vim.fn.join(lines, "\n")

  local query = vim.treesitter.query.parse('markdown_inline', [[[
    (full_reference_link
      [
        "]"
      ])
     (shortcut_link
       [
         "]"
       ])
     (collapsed_reference_link
       [
         "]"
       ])
     (inline_link
       [
         "]"
         ")"
       ])
      (image
        [
          "]"
          ")"
        ])
    ] @concealed]])

  local parser = vim.treesitter.get_string_parser(lines_str, "markdown")
  parser:parse(true)
  parser:for_each_tree(function(tree)

    local pos_to_insert = {}
    for id, node, metadata in query:iter_captures(tree:root(), lines) do
      local row, col, bytes = node:end_()
      if lines[row+1]:match("│") then
        table.insert(pos_to_insert, {row, col, bytes})
      end
    end
    -- go from the end because inserting is going to move offsets
    for i = #pos_to_insert, 1, -1 do
      local row, col, bytes = unpack(pos_to_insert[i])
      lines[row+1] = lines[row+1]:sub(1, col) .. " " .. lines[row+1]:sub(col+1)
    end
  end)

  return lines
end

local function urldecode(url)
  return url:gsub("%%20", " "):gsub("%%3c", "<"):gsub("%%3e", ">"):gsub("%%23", "#")
end

local function fix_file_links(fname, lines, target_path, choice, path_to_name,
    name_and_id_to_string_nearby, orig_path)
  local changes = false
  for i = #lines, 1, -1 do
    local l, m = lines[i]:match("^( +%d+%. )(.*)$")
    -- remove the path prefix, which could be the folder in which we store the files, or
    -- any parent of it, in case it's a link to '../../filename'
    if m ~= nil and m:match("^file://") then
      local file_guessed_subpath_str = orig_path:gsub("/[^/]+$", "") -- take the parent the first time, it's the filename
      if not orig_path:match("/") then
        -- completing the gsub before.. no child folder. remove the filename
        file_guessed_subpath_str = ""
      end
      if m:match("getattribute") then
        print("m " .. m)
        print("orig_path " .. orig_path)
      end
      local prefix = "file://" .. target_path
      -- if the link points to target_path/orig_subfolder/../../ then i must use orig_path/../../
      while #prefix > 0 do
        if m:match("getattribute") then
          print("prefix " .. prefix)
          print("file_guessed_subpath_str " .. file_guessed_subpath_str)
        end
        -- take the parent folder of the prefix until it is a prefix of m.
        if m:match("^" .. escape_pattern(prefix)) then
          break
        end
        -- everytime i take the parent of prefix, take the parent of orig_path too
        prefix = prefix:gsub("/[^/]+$", "")
        if file_guessed_subpath_str:match("/") then
          file_guessed_subpath_str = file_guessed_subpath_str:gsub("/[^/]+$", "")
        else
          file_guessed_subpath_str = ""
        end
      end
      if m:match("getattribute") then
        print("final file_guessed_subpath_str " .. file_guessed_subpath_str)
      end

      local link_target = urldecode(m):gsub("^" .. escape_pattern(prefix), "")
      if m:match("getattribute") then
        print("link_target " .. link_target)
      end
      local file_id = vim.split(link_target, "#")
      if #file_id == 4 then
        -- for lua, the path sometimes contains a #...
        -- it's a link to the same file, which was already properly named... "name#pa#th#id"
        local path = sanitize_fname(file_id[1]:gsub("^/", "") .. "#" .. file_id[2] .. "#" .. file_id[3]:gsub("%.html$", ""))
        if path ~= nil then
          if name_and_id_to_string_nearby[path] ~= nil then
            local text_section = name_and_id_to_string_nearby[path][file_id[4]]
            if text_section ~= nil then
              lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(path) .. "#" .. text_section
              changes = true
            end
          -- elseif #vim.tbl_keys(name_and_id_to_string_nearby) == 1 then
          --   local text_section = name_and_id_to_string_nearby[vim.tbl_keys(name_and_id_to_string_nearby)[1]][file_id[4]]
          --   if text_section ~= nil then
          --     lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(path) .. "#" .. text_section
          --     changes = true
          --   end
          end
        end
      elseif #file_id == 3 then
        -- it's a link to the same file, which was already properly named... "name#path#id"
        local path = sanitize_fname(file_id[1]:gsub("^/", "") .. "#" .. file_id[2]:gsub("%.html$", ""))
        if path ~= nil and name_and_id_to_string_nearby[path] ~= nil then
          local text_section = name_and_id_to_string_nearby[path][file_id[3]]
          if text_section ~= nil then
            lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(path) .. "#" .. text_section
            changes = true
          end
        end
      elseif #file_id == 2 then
        -- link to another file, ID lookup
        local name = path_to_name[file_id[1]:gsub("^/", "")]
        if name ~= nil then
          local text_section = name_and_id_to_string_nearby[sanitize_fname(name .. "#" .. file_id[1]:gsub("^/", ""))][file_id[2]]
          if text_section ~= nil then
            lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(sanitize_fname(name .. "#" .. file_id[1]:gsub("^/", "")) .. "#" .. text_section)
            changes = true
          end
        end
      else
        -- link to a pain file, no ID lookup
        -- print("will search for: '" .. file_guessed_subpath_str .. link_target .. "'")
        -- print(vim.inspect(path_to_name))
        -- print(vim.inspect(path_to_name))
        -- print(file_guessed_subpath_str)
        link_target = link_target:gsub("^/", "")
        local name = path_to_name[file_guessed_subpath_str .. "/" .. link_target] or path_to_name[link_target]

        -- if m:match("getattribute") then
        --   print("name " .. name)
        --   print("file_guessed_subpath_str " .. file_guessed_subpath_str)
        --   print("link_target " .. link_target)
        -- end
        if name ~= nil then
          if #file_guessed_subpath_str > 0 then
            lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(name .. "#" .. file_guessed_subpath_str .. "/" .. link_target)
          else
            lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(name .. "#" .. link_target)
          end
          if m:match("getattribute") then
            print(lines[i])
          end
          changes = true
        -- else
        --   print(m)
        --   print(vim.inspect(path_to_name))
        --   print("NOT FOUND")
        --   print("prefix => " .. prefix)
        --   print("m => " .. m)
        --   print("file_guessed_subpath_str: " .. file_guessed_subpath_str)
        --   print("link_target: " .. link_target)
        --   print("orig_path: " .. orig_path)
        end
      end
    end
  end
  return lines, changes
end

local function html_extra_css(source)
  if source:match("openjdk") then
    return [[
<html>
  <head>
    <style>
      ul.inheritance {
        list-style:none
      }
      ul.inheritance ul.inheritance {
        margin:0
      }
    </style>
  </head>
  <body>
    ]]
  else
    return ""
  end
end

local function apidoc_install(choice, slugs_to_mtimes, cont)
  vim.notify("Fetching documentation for " .. choice)
  local data_folder = data_folder()
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
    local path_to_name = {}
    local path_to_type = {}
    local known_keys_per_path = {}
    for _, entry in ipairs(data["entries"]) do
      path_to_name[entry.path] = entry.name
      path_to_type[entry.path] = entry.type

      local file_id = vim.split(entry.path, "#")
      if #file_id == 2 then
        path_to_name[entry.path] = entry.name
        local sanitized_fname = sanitize_fname(file_id[1])
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
      -- used to split files in sections based on ids referenced from the toplevel
      local name_and_id_to_pos = {}
      -- used to gather all section "titles" so that we can prepare links to this
      -- part of the files later on. So we gather this for ALL ids, whether we know
      -- about them or not.
      local name_and_id_to_string_nearby = {}
      local name_known_byte_offsets = {}
      local name_to_contents = {}
      local out_path_to_orig_path = {}

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
      local sanitized_key = sanitize_fname((path_to_name[key] or key) .. "#" .. key)
      out_path_to_orig_path[sanitized_key .. ".html"] = key
      local file = io.open(target_path .. "/" .. sanitized_key  .. ".html", "w")
      contents = data[key]
      :gsub("<pre([^>]*)>(.-)</pre>", function(pre_attrs, children)
        local match = pre_attrs:match("[^<>]*data%-language=\"(%w+)\"")
        -- don't put ``` unless it's multiline
        if match and children:match("\n") then
          return "<pre>\n```" .. match .. "\n" .. children:gsub("</?code>", "") .. "\n```</pre>"
        elseif not children:match("<code") and children:match("\n") then
          return "<pre" ..pre_attrs .. ">\n```\n" .. children .. "\n```</pre>"
        elseif not children:match("<code") and not children:match("\n") then
          return "<pre" ..pre_attrs .. ">\n`" .. children .. "`</pre>"
        else
          -- sometimes there is <pre><code></code></pre>. don't add double ```, let <code> handle it
          return "<pre" .. pre_attrs .. ">" .. children .. "</pre>"
        end
      end)
      :gsub("<td class=.font%-monospace.>([^<]+)</td>", "<td>`%1`</td>")
      :gsub("<code([^>]*)>(.-)</code>", function(code_attrs, children)
        local match = code_attrs:match("class=\"javascript\"")
        if match and children:match("\n") then
          return "<code" .. code_attrs .. ">\n```javascript\n" .. children .. "\n```</code>"
        elseif not children:match("<a") then
          -- don't wrap a tags in `` or we lose the links
          if children:match("\n") then
            return "<code" .. code_attrs .. ">\n```\n" .. children .. "\n```\n</code>"
          else
            return "<code" .. code_attrs .. ">`" .. children .. "`</code>"
          end
        else
          return "<code" .. code_attrs .. ">" .. children .. "</code>"
        end
      end)
      :gsub("<table", "<table border=\"1\"")
      file:write(html_extra_css(choice))
      if path_to_type[key] ~= nil then
        file:write("> " .. path_to_type[key] .. "\n")
      end
      file:write(contents)
      file:close()

      local start_parse = vim.loop.hrtime()
      local parser = vim.treesitter.get_string_parser(contents, "html")
      local tree = parser:parse()[1]
      local elapsed = (vim.loop.hrtime() - start_parse) / 1e9
      all_parsing = all_parsing + elapsed

      name_to_contents[sanitized_key] = contents
      name_and_id_to_pos[sanitized_key] = {}
      name_and_id_to_string_nearby[sanitized_key] = {}
      name_known_byte_offsets[sanitized_key] = {#contents}

      local start_ids = vim.loop.hrtime()
      for id, node, metadata in query:iter_captures(tree:root(), contents) do
        if node:next_named_sibling():named_child_count() > 0 then
          local id_val = vim.treesitter.get_node_text(node:next_named_sibling():named_child(), contents)
          if known_keys_per_path[key] ~= nil and known_keys_per_path[key][id_val] then
            _, _, byte_pos = node:parent():parent():start()
            name_and_id_to_pos[sanitized_key][id_val] = byte_pos
            table.insert(name_known_byte_offsets[sanitized_key], byte_pos)
          end
          if node:parent() ~= nil and node:parent():parent() ~= nil
            and node:parent():parent():next_named_sibling() ~= nil
            and node:parent():parent():next_named_sibling():type() == "text" then
            name_and_id_to_string_nearby[sanitized_key][id_val] =
            vim.treesitter.get_node_text(node:parent():parent():next_named_sibling(), contents)
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
    for path, name in pairs(path_to_name) do
      local file_id = vim.split(path, "#")
      local sanitized_fname = sanitize_fname(name)
      if #file_id == 2 then
        local sanitized_containing_file_name = sanitize_fname((path_to_name[file_id[1]] or file_id[1]) .. "#" .. file_id[1])
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
        local sanitized_name = sanitize_fname(name)
        local out_path = sanitize_fname(sanitized_name .. "#" .. path):sub(1, 250) .. ".html"
        out_path_to_orig_path[out_path] = path
        local file = io.open(target_path .. "/" .. out_path, "w")
        file:write(html_extra_css(choice))
        if path_to_type[file_id[1]] ~= nil then
          file:write("> " .. path_to_type[file_id[1]] .. "/" .. path_to_name[file_id[1]] .. "\n")
        end
        file:write(to_write_contents)
        file:close()
      end
    end
    local elapsed_writing = (vim.loop.hrtime() - start_writing) / 1e9

    local start_elinks = vim.loop.hrtime()
    -- convert the html to text, on 8 processes concurrently (-P8)
    vim.system({
      "sh", "-c",
      -- [[find . -maxdepth 1 -name '*.html' -print0 | xargs -0 -P 8 -I param sh -c "elinks -config-dir ]] .. data_folder .. [[ -dump 'param' > 'param'.md && rm 'param'"]]
      [[find . -maxdepth 1 -name '*.html' -print0 | xargs -0 -P 8 -I param sh -c "elinks -config-dir ]] .. data_folder .. [[ -dump 'param' > 'param'.md"]]
    }, {cwd=target_path}):wait()
    local elapsed_elinks = (vim.loop.hrtime() - start_elinks) / 1e9

    local start_pp = vim.loop.hrtime()

    -- unfortunately i must post-process the markdown to fix conceal table alignment and fix links..
    vim.system({"rg", "-l", "│"}, {cwd=target_path}, vim.schedule_wrap(function(res)
      for _, fname in ipairs(vim.fn.split(res.stdout, "\n")) do
        local filepath = target_path .. "/" .. fname
        local lines = {}
        for line in io.lines(filepath) do
          table.insert(lines, line)
        end
        local file = io.open(filepath, "w")
        local after_conceal = add_spaces_to_compensate_conceals_cols(lines)
        file:write(vim.fn.join(after_conceal, "\n"))
        file:close()
      end

      local fs = vim.uv.fs_scandir(target_path)
      while true do
        local name, type = vim.uv.fs_scandir_next(fs)
        if not name then break end
        if type ~= 'directory' then
          local filepath = target_path .. "/" .. name
          local lines = {}
          for line in io.lines(filepath) do
            table.insert(lines, line)
          end
          local after_links, changes = fix_file_links(
            filepath, lines, target_path, choice, path_to_name, name_and_id_to_string_nearby, out_path_to_orig_path[name:gsub(".md$", "")])
          if changes then
            local file = io.open(filepath, "w")
            file:write(vim.fn.join(after_links, "\n"))
            file:close()
          end
        end
      end

      local elapsed_pp = (vim.loop.hrtime() - start_pp) / 1e9

      local elapsed = (vim.loop.hrtime() - start_install) / 1e9

      vim.notify("Finished fetching documentation for " .. choice .. " in " .. elapsed .. "s. All parsing: " .. all_parsing
      .. "s. All reading IDs: " .. all_reading_ids .. "s. All writing: " .. elapsed_writing .. "s. All elinks: " .. elapsed_elinks .. "s. All post-process: " .. elapsed_pp .. "s.")

      if cont ~= nil then
        cont()
      end
    end)):wait()
  end))
end))
end

local function fetch_slugs_and_mtimes_and_then(cont)
  vim.system({"curl", "-L", "https://devdocs.io/docs.json"}, {text=true}, vim.schedule_wrap(function(res)
    local data = vim.fn.json_decode(res.stdout)
    local slugs_to_mtimes = {}
    for _, doc in ipairs(data) do
      slugs_to_mtimes[doc['slug']] = doc['mtime']
    end
    cont(slugs_to_mtimes)
  end))
end

local function apidocs_install()
  fetch_slugs_and_mtimes_and_then(function (slugs_to_mtimes)
    local keys = vim.tbl_keys(slugs_to_mtimes)
    table.sort(keys)
    vim.ui.select(keys, {prompt="Pick a documentation to install"}, function(choice)
      if choice == nil then
        return
      end
      apidoc_install(choice, slugs_to_mtimes)
    end)
  end)
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

local function apidocs_open(params, slugs_to_mtimes)
  local docs_path = data_folder()
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
    attach_mappings = function(prompt_bufnr, map)
      local actions = require('telescope.actions')
      map('i', '<cr>', function(nr)
        actions.close(prompt_bufnr)
        -- create a new window and use winfixbuf on it, because i'll set
        -- conceallevel, and that's tied to the window (not the buffer),
        -- and is very invasive
        vim.cmd[[100vsplit]]
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, buf)
        local docs_path = require("telescope.actions.state").get_selected_entry(prompt_bufnr).value
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
          -- print(line)
          local m = string.match(line, "^%s+%d+%. local://")
          if m then
            local target = line:sub(#m+1)
            local components = vim.split(target, "#")
            print(vim.inspect(components))
            -- TODO allow C-o navigation, ie open a new buffer instead of replacing the contents of this one
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

            elseif #components == 4 then
              -- file name with two hashes+section ID (happens for lua)
              local new_buf = vim.api.nvim_create_buf(true, false)
              print(data_folder() .. components[1] .. "#" .. components[2] .. "#" .. components[3] .. ".html.md")
              load_doc_in_buffer(new_buf, data_folder() .. components[1] .. "#" .. components[2] .. "#" .. components[3] .. ".html.md")
              buf_view_switch_to_new(new_buf)
              vim.cmd("/" .. components[4])
            end
          end
        end, {buffer = true})
      end)
      return true
    end,
  }):find()
end

local function apidocs_search(opts)
  local previewers = require("telescope.previewers")
  local folder = data_folder()
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
    })
  })
end

return {
  apidocs_install = apidocs_install,
  apidocs_open = apidocs_open,
  apidocs_search = apidocs_search,
}
