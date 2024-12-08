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
  aider_cmd_args_watch_files = nil,
}

M.options = {}

function M.setup(opts)
  -- watch files cmd args copy from aider_cmd_args if not set
  if opts.aider_cmd_args_watch_files == nil then
    opts.aider_cmd_args_watch_files = vim.deepcopy(opts.aider_cmd_args) or {}
    table.insert(opts.aider_cmd_args_watch_files, "--watch-files")
  end
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
