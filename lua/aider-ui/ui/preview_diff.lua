-- delete later
local M = {}

local Job = require("plenary.job")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local pickers = require("telescope.pickers")
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")

function M.get_diff(before_path, after_path, opts)
  local diff = {}
  local args = {}

  table.insert(args, before_path)
  table.insert(args, after_path)

  Job:new({
    command = "delta",
    args = args,
    on_exit = function(j)
      diff = j:result()
    end,
  }):sync()

  return diff
end

local function preview_file_changes(items)
  local entries = {}
  local devicons = require("nvim-web-devicons")

  for _, item in ipairs(items) do
    local path = item.path
    local filename = vim.fn.fnamemodify(path, ":t")
    local icon, _ = devicons.get_icon(filename, nil, { default = true })
    icon = icon or ""
    local display_path = vim.fn.fnamemodify(path, ":.")

    table.insert(entries, {
      value = item,
      ordinal = item.path,
      display = " " .. icon .. " " .. display_path,
    })
  end

  pickers
    .new({}, {
      prompt_title = "File Changes",
      layout_strategy = "vertical",
      layout_config = {
        width = 0.8,
        height = 0.9,
        preview_cutoff = 1,
        preview_height = function(_, _, max_lines)
          local h = math.floor(max_lines * 0.7)
          return math.max(h, 10)
        end,
      },
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry.value,
            ordinal = entry.ordinal,
            display = entry.display,
          }
        end,
      }),
      sorter = sorters.get_fzy_sorter(),
      previewer = previewers.new_termopen_previewer({
        get_command = function(entry)
          return {
            "delta",
            "--side-by-side",
            "--file-style",
            "omit",
            entry.value.before_path,
            entry.value.after_path,
          }
        end,
      }),
    })
    :find()
end

M.preview_current_last_change = function()
  local session = sessions.current_session()
  if session == nil then
    utils.err("No active session.")
    return
  end
  local last_change = session:get_last_change()
  if last_change == nil then
    utils.info("No changes to preview.")
    return
  end
  preview_file_changes(last_change)
end

return M
