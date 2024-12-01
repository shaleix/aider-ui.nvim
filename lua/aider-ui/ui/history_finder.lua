local M = {}
local mapOpts = { noremap = true }
local aider_sessions_manager = require("aider-ui.aider_sessions_manager")

function M.input_history_view()
  local session = aider_sessions_manager.current_session()
  if not session then
    print("No active session found.")
    return
  end
  local Popup = require("nui.popup")
  local popup = Popup({
    relative = "editor",
    position = "50%",
    enter = true,
    size = { width = 0.8, height = 0.8 },
    border = {
      style = "rounded",
      text = { top = " Aider Input History " },
    },
    buf_options = {
      filetype = "conf",
      buftype = "nofile",
      swapfile = false,
      undofile = false,
      modifiable = false,
    },
  })
  popup:mount()
  local entry_map = {}

  session:get_input_history(function(history)
    local content = {}
    for i, entry in ipairs(history) do
      table.insert(content, "# " .. entry.cmd)
      local lines = vim.split(entry.content, "\n")
      for j, line in ipairs(lines) do
        table.insert(content, "> " .. line)
        entry_map[#content] = entry
      end
      table.insert(content, "")
    end
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, content)
  end)

  popup:map("n", "<Enter>", function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1] - 1
    local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    local current_line = lines[line_num + 1]

    if current_line:match("^> ") then
      local entry = entry_map[line_num + 1] -- 获取当前行对应的 entry

      if entry then
        local cmd_type = entry.cmd
        local default_content = entry.content

        -- local content = table.concat(default_content, "\n")
        if cmd_type == "/code" then
          require("aider-ui.ui.chat").show_code_input(default_content)
        elseif cmd_type == "/ask" then
          require("aider-ui.ui.chat").show_ask_input(default_content)
        elseif cmd_type == "/architect" then
          require("aider-ui.ui.chat").show_architect_input(default_content)
        end
        popup:unmount()
      end
    end
  end, mapOpts)

  popup:map("n", "q", function()
    popup:unmount()
  end, mapOpts)
end

return M
