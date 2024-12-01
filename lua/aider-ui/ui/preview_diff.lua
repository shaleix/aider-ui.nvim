local M = {}

local Job = require("plenary.job")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local pickers = require("telescope.pickers")
local sessions = require("aider-ui.aider_sessions_manager")
local notify = require("notify")

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

function preview_file_changes(items)
  local entries = {}
  for _, item in ipairs(items) do
    table.insert(entries, {
      value = item,
      ordinal = item.path,
      display = item.path,
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
    notify("No active session.", "error", { title = "No active session (Aider)" })
    return
  end
  local last_change = session:get_last_change()
  if last_change == nil then
    notify("No changes to preview.", vim.log.levels.INFO)
    return
  end
  preview_file_changes(last_change)
end

function M.test_preview()
  M.preview_file_changes({
    { path = "/tmp/a.py", before_path = "/tmp/a.py", after_path = "/tmp/b.py" },
  })
end

return M
