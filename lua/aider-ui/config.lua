local M = {}

M.defaults = {
  icons = {
    folder = "",
  },
  session_save_dir = ".aider_sessions",
  python_path = "/usr/bin/python3",
  aider_cmd_args = {
    "--no-check-update",
    "--no-auto-commits",
    "--dark-mode",
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
