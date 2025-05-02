local common = require("apidocs.common")

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

local function fix_file_links_resolve_fname(choice, path_to_name, file_guessed_subpath_str, link_target)
  local name = path_to_name[file_guessed_subpath_str .. "/" .. link_target] or path_to_name[link_target]
  if name ~= nil then
    if #file_guessed_subpath_str > 0 then
      return "local://" .. choice .. "/", sanitize_fname(name .. "#" .. file_guessed_subpath_str .. "/" .. link_target)
    else
      return "local://" .. choice .. "/", sanitize_fname(name .. "#" .. link_target)
    end
  end
  return nil, nil
end

local function fix_file_links(fname, lines, target_path, choice, path_to_name,
    name_and_id_to_string_nearby, orig_path, orig_containing_path)
  local changes = false
  for i = #lines, 1, -1 do
    local l, m = lines[i]:match("^( +%d+%. )(.*)$")
    if m == nil and i > 1 and lines[i-1]:match("^ +%d+%. .*$") and vim.startswith(lines[i], "\t") then
      -- sometimes the format is not "number. link", but "number. desc\n\tlink". maybe when the link has
      -- a description? this happens with rust
      l, m = lines[i]:match("^(\t)(.*)$")
    end
    -- remove the path prefix, which could be the folder in which we store the files, or
    -- any parent of it, in case it's a link to '../../filename'
    if m ~= nil and m:match("^file://") then
      local file_guessed_subpath_str = orig_path:gsub("/[^/]+$", "") -- take the parent the first time, it's the filename
      if not orig_path:match("/") then
        -- completing the gsub before.. no child folder. remove the filename
        file_guessed_subpath_str = ""
      end
      local prefix = "file://" .. target_path
      -- if the link points to target_path/orig_subfolder/../../ then i must use orig_path/../../
      while #prefix > 0 do
        -- take the parent folder of the prefix until it is a prefix of m.
        if m:match("^" .. common.escape_pattern(prefix)) then
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

      local link_target = urldecode(m):gsub("^" .. common.escape_pattern(prefix), "")
      local file_id = vim.split(link_target, "#")
      if #file_id == 4 then
        -- it's a link to the same file, which was already properly named... "name#pa#th#id"
        -- the trick is that if we're a file split from a larger file and we're pointing back
        -- to ourself, we likely want to point back to the original large file, not to us,
        -- which are the smaller split file.
        local link_file = file_id[2] .. "#" .. file_id[3]:gsub("%.html$", "")
        local path = sanitize_fname(file_id[1]:gsub("^/", "") .. "#" .. link_file) -- TODO is that ever used?
        if link_file == orig_path and orig_containing_path ~= nil then
          path = orig_containing_path
        end
        if path ~= nil then
          if name_and_id_to_string_nearby[path] ~= nil then
            local text_section = name_and_id_to_string_nearby[path][file_id[4]]
            if text_section ~= nil then
              lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(path) .. "#" .. text_section
              changes = true
            else
              -- can't find a header by that name in the source file. sometimes the files
              -- are just broken. for instance date_fns/I18n Contribution Guide.
              -- in that case do the same as upstream devdocs/the browser: show the file at the top, ignoring the ID.
              lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(path) .. "\t+" .. file_id[4]
              changes = true
            end
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
          else
            -- can't find a header by that name in the source file. sometimes the files
            -- are just broken. for instance date_fns/I18n Contribution Guide.
            -- in that case do the same as upstream devdocs/the browser: show the file at the top, ignoring the ID.
            lines[i] = l .. "local://" .. choice .. "/" .. sanitize_fname(path) .. "\t+" .. file_id[3]
            changes = true
          end
        end
      elseif #file_id == 2 then
        -- link to another file, ID lookup
        local local_path, local_fname = fix_file_links_resolve_fname(choice, path_to_name, file_guessed_subpath_str, file_id[1]:gsub("^/", ""))
        if local_path ~= nil and name_and_id_to_string_nearby[local_fname] then
          local text_section = name_and_id_to_string_nearby[local_fname][file_id[2]]
          if text_section ~= nil then
            lines[i] = l .. local_path .. local_fname .. "#" .. text_section
            changes = true
          else
            -- can't find a header by that name in the source file. sometimes the files
            -- are just broken. for instance date_fns/I18n Contribution Guide.
            -- in that case do the same as upstream devdocs/the browser: show the file at the top, ignoring the ID.
            lines[i] = l .. local_path .. local_fname .. "\t+" .. file_id[2]
            changes = true
          end
        end
      else
        local local_path, local_fname = fix_file_links_resolve_fname(choice, path_to_name, file_guessed_subpath_str, link_target:gsub("^/", ""))
        if local_path ~= nil then
          lines[i] = l .. local_path .. local_fname
          changes = true
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
  local data_folder = common.data_folder()
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
      local out_path_to_orig_containing_path = {}

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
      local fname = target_path .. "/" .. sanitized_key  .. ".html"
      local file = io.open(fname, "w")
      if file == nil then
        print("Error opening file " .. fname)
      end
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
        file:write("<p>&gt; " .. choice .. "/" .. path_to_type[key] .. "\n</p>\n")
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
            name_and_id_to_pos[sanitized_key][id_val] = byte_pos+1
            table.insert(name_known_byte_offsets[sanitized_key], byte_pos+1)
          end
          if node:parent() ~= nil and node:parent():parent() ~= nil
            and node:parent():parent():next_named_sibling() ~= nil
            and node:parent():parent():next_named_sibling():type() == "text" then
            name_and_id_to_string_nearby[sanitized_key][id_val] =
              vim.treesitter.get_node_text(node:parent():parent():next_named_sibling(), contents)
          elseif node:parent() ~= nil and node:parent():parent() ~= nil
            and node:parent():parent():next_named_sibling() ~= nil
            and node:parent():parent():next_named_sibling():type() == "element"
            and node:parent():parent():next_named_sibling():named_child_count() > 1
            and node:parent():parent():next_named_sibling():named_children()[2]:type() == "text" then
            -- happens with lua, but seems generic enough not to gate it
            name_and_id_to_string_nearby[sanitized_key][id_val] =
              vim.treesitter.get_node_text(node:parent():parent():next_named_sibling():named_children()[2], contents)
          elseif choice == "rust" and node:parent() ~= nil and node:parent():parent() ~= nil and node:parent():parent():parent() ~= nil then
            -- for rust, the node text is a little harder to find
            local elt = node:parent():parent():parent()
            if elt:type() == "element" and elt:named_child_count() >= 3 then
              local next_elt = elt:named_children()[3]
              if next_elt:type() == "element" and next_elt:named_child_count() >= 2 then
                local text = next_elt:named_children()[2]
                if text:type() == "text" then
                  local text_contents = vim.treesitter.get_node_text(text, contents)
                  local lines = vim.split(text_contents, "\n")
                  if #lines > 1 then
                    text_contents = lines[1]
                    for i = 2, #lines do
                      if #lines[i] > #text_contents then
                        text_contents = lines[i]
                      end
                    end
                  end
                  name_and_id_to_string_nearby[sanitized_key][id_val] = text_contents
                end
              end
            end
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
          to_write_contents = string.sub(name_to_contents[sanitized_containing_file_name], byte, next_byte-1)
        end
        local sanitized_name = sanitize_fname(name)
        local out_path = sanitize_fname(sanitized_name .. "#" .. path):sub(1, 250) .. ".html"
        out_path_to_orig_path[out_path] = path
        out_path_to_orig_containing_path[out_path] = sanitized_containing_file_name
        local file = io.open(target_path .. "/" .. out_path, "w")
        file:write(html_extra_css(choice))
        if path_to_type[file_id[1]] ~= nil then
          file:write("<p>&gt; " .. choice .. "/" .. path_to_type[file_id[1]] .. "/" .. path_to_name[file_id[1]] .. "\n</p>\n")
        else
          file:write("<p>&gt; " .. choice .. "\n</p>\n")
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
      [[find . -maxdepth 1 -name '*.html' -print0 | xargs -0 -P 8 -I param sh -c "elinks -config-dir ]] .. data_folder .. [[ -dump 'param' > 'param'.md && rm 'param'"]]
      -- [[find . -maxdepth 1 -name '*.html' -print0 | xargs -0 -P 8 -I param sh -c "elinks -config-dir ]] .. data_folder .. [[ -dump 'param' > 'param'.md"]]
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
            filepath, lines, target_path, choice, path_to_name, name_and_id_to_string_nearby,
            out_path_to_orig_path[name:gsub(".md$", "")], out_path_to_orig_containing_path[name:gsub(".md$", "")])
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

local function apidocs_install()
  if vim.fn.executable("elinks") ~= 1 or vim.fn.executable("rg") ~= 1 or vim.fn.executable("find") ~= 1 then
    print("The 'elinks', 'rg' and 'find' programs must be installed to proceed, refusing to run.")
  else
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
end


return {
  fetch_slugs_and_mtimes_and_then = fetch_slugs_and_mtimes_and_then,
  apidoc_install = apidoc_install,
  apidocs_install = apidocs_install,
}
