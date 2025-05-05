local common = require("apidocs.common")
local Snacks = require("snacks")

local common_layout_options = {
	preview = true,
	preset = "telescope",
}
local common_win_options = {
	preview = {
		wo = {
			number = true,
			relativenumber = false,
			signcolumn = "no",
			conceallevel = 2,
			concealcursor = "n",
			winfixbuf = true,
			list = false,
			wrap = false,
		},
	},
}

local function get_data_dir(opts)
	local data_dir = common.data_folder()
	if opts and opts.source then
		data_dir = data_dir .. opts.source .. "/"
	end
end

local function format_entries(item, picker)
	vim.notify(vim.inspect(item), vim.log.levels.DEBUG, { title = "Snacks" })
	local parts = vim.split(item.file, "/")
	-- take the last part and set it as the text
	local folder = parts[#parts - 1]
	local filename = parts[#parts]
	local filetype = vim.split(folder, "~")[1]
	local icon, hl = Snacks.util.icon(filetype, "filetype", {
		fallback = picker.opts.icons.files,
	})
	icon = Snacks.picker.util.align(icon, picker.opts.formatters.file.icon_width or 2)
	filename = filename:gsub("%.html%.md$", "")
	local new_item = {
		{
			icon,
			hl,
			virtual = true,
		},
		{
			folder .. " | ",
			"SnacksPickerSpecial",
			field = "file",
		},
	}
	local fileNameParts = vim.split(filename, "#")
	-- loop through the parts and add them to the new_item
	for i = 1, #fileNameParts do
		local part = fileNameParts[i]
		new_item[#new_item + 1] = {
			part,
			"SnacksPickerFile",
			field = "file",
		}
		if i < #fileNameParts then
			new_item[#new_item + 1] = {
				" > ",
				"SnacksPickerDelim",
				field = "file",
			}
		end
	end
	return new_item
end

local function apidocs_open(opts)
	Snacks.picker.files({
		layout = common_layout_options,
		win = common_win_options,
		dirs = { get_data_dir(opts) },
		ft = { "markdown", "md" },
		confirm = function(picker, item)
			require("apidocs").open_doc_in_new_window(item.file)
		end,
		format = format_entries,
	})
end

local function apidocs_search(opts)
	Snacks.picker.grep({
		layout = common_layout_options,
		win = common_win_options,
		dirs = { get_data_dir(opts) },
		ft = { "markdown", "md" },
		confirm = function(picker, item)
			require("apidocs").open_doc_in_new_window(item.file)
		end,
		format = format_entries,
	})
end

return {
	apidocs_open = apidocs_open,
	apidocs_search = apidocs_search,
}
