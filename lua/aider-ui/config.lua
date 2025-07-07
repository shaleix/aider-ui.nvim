local M = {}

M.defaults = {
  icons = {
    folder = "",
    collapse_marks = { '', '' },
  },
  session_save_dir = ".aider_sessions",
  python_path = "/usr/bin/python3",
  aider_cmd_args = {
    "--no-check-update",
    "--no-auto-commits",
    "--dark-mode",
  },
  aider_cmd_args_watch_files = nil,
  auto_pop_confirm = true,  -- Automatically pop confirm dialog when AskConfirm event is triggered
  sider_width = 85,
  chat_size = {
    width = 85,
    height = 35,
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
