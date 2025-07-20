local M = {}

M.setup = function()
  local chat_history = require("aider-ui.ui.chat_history")
  local sessions_ui = require("aider-ui.ui.sessions_ui")
  local model = require("aider-ui.ui.model")
  local sessions_manager = require("aider-ui.aider_sessions_manager")
  local git = require("aider-ui.ui.git")
  local side_split = require("aider-ui.ui.side_split")
  local chat = require("aider-ui.ui.chat")
  local cmd_input = require("aider-ui.ui.cmd_input")
  local utils = require("aider-ui.utils")

  vim.api.nvim_create_user_command("AiderHistory", function()
    chat_history.input_history_view()
  end, { desc = "Show Aider Chat History" })

  vim.api.nvim_create_user_command("AiderNewSession", function()
    sessions_ui.create_session_in_working_dir()
  end, { desc = "Create Aider Session" })

  vim.api.nvim_create_user_command("AiderNewWatchFilesSession", function()
    sessions_ui.create_session_in_working_dir(nil, "watch-files", true)
  end, { desc = "Create Aider Session with watched files" })

  vim.api.nvim_create_user_command("AiderSwitchModel", function()
    model.switch_model()
  end, { desc = "Switch Aider Model" })

  vim.api.nvim_create_user_command("AiderInterruptCurrentSession", function()
    local current_session = sessions_manager.current_session()
    if current_session then
      current_session:interrupt()
    else
      utils.err("No active Aider session found.")
    end
  end, { desc = "Interrupt the current Aider session" })

  vim.api.nvim_create_user_command("AiderGitCommit", function()
    git.commit()
  end, { desc = "Commit changes using Aider" })

  vim.api.nvim_create_user_command("AiderShowSessionInfo", function()
    require("aider-ui.ui.sessions_ui").show_session_info()
  end, { desc = "Show Aider session info" })

  vim.api.nvim_create_user_command("AiderToggleSplit", function()
    side_split.toggle_aider_split()
  end, { desc = "Toggle Aider split" })

  vim.api.nvim_create_user_command("AiderAddCurrentBuffer", function()
    local buffer_type = vim.bo.buftype
    if buffer_type == "" then
      local buffer_path = vim.fn.expand("%:p")
      sessions_manager.add_files({ buffer_path })
    end
  end, { desc = "Add current buffer to Aider" })

  vim.api.nvim_create_user_command("AiderCode", function()
    chat.show_code_input()
  end, { desc = "Show Aider /code input" })

  vim.api.nvim_create_user_command("AiderArchitect", function()
    chat.show_architect_input()
  end, { desc = "Show Aider /architect input" })

  vim.api.nvim_create_user_command("AiderAsk", function()
    chat.show_ask_input()
  end, { desc = "Show Aider /ask input" })

  vim.api.nvim_create_user_command("AiderReadCurrentBuffer", function()
    local buffer_type = vim.bo.buftype
    if buffer_type == "" then
      local buffer_path = vim.fn.expand("%:p")
      sessions_manager.read_files({ buffer_path })
    end
  end, { desc = "Read current buffer into Aider" })

  vim.api.nvim_create_user_command("AiderSyncOpenBuffers", function()
    sessions_manager.sync_open_buffers()
  end, { desc = "Sync open buffers with Aider" })

  vim.api.nvim_create_user_command("AiderAddFile", function(args)
    local file_paths = vim.split(args.args, " ")
    sessions_manager.add_files(file_paths)
  end, { nargs = "*", desc = "Add files to current Aider session" })

  vim.api.nvim_create_user_command("AiderReadFile", function(args)
    local file_paths = vim.split(args.args, " ")
    sessions_manager.read_files(file_paths)
  end, { nargs = "*", desc = "Read files into current Aider session" })

  vim.api.nvim_create_user_command("AiderSessionFinder", function()
    sessions_ui.session_finder()
  end, { desc = "Use Telescope to select Aider session" })

  vim.api.nvim_create_user_command("AiderSwitchNextSession", function()
    sessions_manager.next_session()
  end, { desc = "Switch next aider session" })

  vim.api.nvim_create_user_command("AiderViewLastChange", function()
    require("aider-ui.ui.diff_view").view_current_session_last_change()
  end, { desc = "View the last change in Aider" })

  vim.api.nvim_create_user_command("AiderLintCurrentBuffer", function()
    chat.lint_current_buffer()
  end, { desc = "Lint the current buffer using Aider" })

  vim.api.nvim_create_user_command("AiderReset", function()
    local current_session = sessions_manager.current_session()
    if current_session then
      current_session:reset()
    else
      utils.err("No active Aider session found.")
    end
  end, { desc = "Reset and drop files in the current Aider session" })

  vim.api.nvim_create_user_command("AiderClearContext", function()
    local current_session = sessions_manager.current_session()
    if current_session then
      current_session:clear()
    else
      utils.err("No active Aider session found.")
    end
  end, { desc = "Clear the context of the current Aider session" })

  vim.api.nvim_create_user_command("AiderCmd", function()
    cmd_input.cmd_popup()
  end, { desc = "Show Aider command input" })

  vim.api.nvim_create_user_command("AiderShowCmd", function()
    local configs = require("aider-ui.config").options
    local cmd_args = { "aider" }
    for _, arg in ipairs(configs.aider_cmd_args) do
      table.insert(cmd_args, arg)
    end
    local cmd = table.concat(cmd_args, " ")
    print(cmd)
  end, { desc = "Show Aider command" })

  vim.api.nvim_create_user_command("AiderDiagnosticLine", function()
    local diagnostic = require("aider-ui.ui.diagnostic")
    diagnostic.diagnostic({scope = 'line'})
  end, { desc = "send line diagnostic to aider" })

  vim.api.nvim_create_user_command("AiderDiagnosticBuffer", function()
    local diagnostic = require("aider-ui.ui.diagnostic")
    diagnostic.diagnostic({scope = 'buffer'})
  end, { desc = "send buffer diagnostic to aider" })

  vim.api.nvim_create_user_command("AiderSaveCurrentSession", function()
    sessions_ui.save_session()
  end, { desc = "Save the current Aider session" })

  vim.api.nvim_create_user_command("AiderCloseCurrentSession", function()
    sessions_manager.close_session()
  end, { desc = "Close the current Aider session" })

  vim.api.nvim_create_user_command("AiderLoadSession", function()
    sessions_ui.session_loader()
  end, { desc = "Load a saved Aider session" })

  vim.api.nvim_create_user_command("AiderToggleDashBoard", function()
    require("aider-ui.ui.dashboard").toggle_dashboard()
  end, { desc = "Toggle Aider dashboard" })

  vim.api.nvim_create_user_command("AiderCommentEndWithAI", function()
    local line = vim.fn.getline(".")
    local updated_line = line .. " . AI!"
    vim.fn.setline(".", updated_line)
  end, { desc = "Append ' . AI!' to the end of the current line" })

  vim.api.nvim_create_user_command("AiderNewWatchSessionInCurrentDir", function()
    local buffer_path = vim.fn.expand("%:p")
    if buffer_path == "" then
      utils.err("Current buffer has no file path")
      return
    end
    local dir_path = vim.fn.fnamemodify(buffer_path, ":h")
    local dir_name = vim.fn.fnamemodify(dir_path, ":t")
    local session_name = "w:" .. dir_name
    sessions_ui.create_session_in_working_dir(dir_path, session_name, true)
  end, { desc = "Create new watch files session in current file's directory" })

  vim.api.nvim_create_user_command("AiderConfirmToggle", function()
    local current_session = sessions_manager.current_session()
    if not current_session then
      utils.err("No active Aider session found.")
      return
    end
    local confirm = require("aider-ui.ui.confirm")
    confirm.toggle_aider_confirm()
  end, { desc = "Toggle Aider confirm popup" })

  vim.api.nvim_create_user_command("AiderRun", function()
    require("aider-ui.ui.run").run()
  end, { desc = "Run commands using Aider" })

  vim.api.nvim_create_user_command("AiderDevTest", function(opts)
    local args = opts.fargs
    if #args > 0 and args[1] == "diffview" then
      local diff_files = {
        {
          path="/home/shalei/workspace/aider-ui.nvim/lua/aider-ui/command.lua",
          before_path="/tmp/command.lua",
          after_path="/home/shalei/workspace/aider-ui.nvim/lua/aider-ui/command.lua",
          diff_summary= {added = 1, removed = 2}
        }
      }
      require("aider-ui.ui.diff_view").diff(diff_files)
    elseif #args > 0 and args[1] == "get_output_history" then
      local current_session = sessions_manager.current_session()
      if not current_session then
        utils.err("No active Aider session found.")
        return
      end
      current_session:get_output_history({start_index=1}, function(output_history)
        print(vim.inspect(output_history))
      end)
    end
  end, { nargs = "*", desc = "for aider-ui dev" })
end

return M
