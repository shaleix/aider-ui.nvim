local M = {}

M.setup = function()
  local history_finder = require("aider-ui.ui.history_finder")
  local sessions_ui = require("aider-ui.ui.sessions_ui")
  local model = require("aider-ui.ui.model")
  local sessions_manager = require("aider-ui.aider_sessions_manager")
  local git = require("aider-ui.ui.git")
  local side_split = require("aider-ui.ui.side_split")
  local chat = require("aider-ui.ui.chat")
  local cmd_input = require("aider-ui.ui.cmd_input")

  vim.api.nvim_create_user_command("AiderHistory", function()
    history_finder.input_history_view()
  end, { desc = "Show Aider Chat History" })

  vim.api.nvim_create_user_command("AiderNewSession", function()
    sessions_ui.create_session_in_working_dir()
  end, { desc = "Create Aider Session" })

  vim.api.nvim_create_user_command("AiderSwitchModel", function()
    model.switch_model()
  end, { desc = "Switch Aider Model" })

  vim.api.nvim_create_user_command("AiderInterruptCurrentSession", function()
    local current_session = sessions_manager.current_session()
    if current_session then
      current_session:interrupt()
    else
      vim.notify("No active Aider session found.", vim.log.levels.ERROR, { title = "Aider Interrupt" })
    end
  end, { desc = "Interrupt the current Aider session" })

  vim.api.nvim_create_user_command("AiderGitCommit", function()
    git.commit()
  end, { desc = "Commit changes using Aider" })

  vim.api.nvim_create_user_command("AiderShowSessionInfo", function()
    require("aider-ui.ui.sessions_ui").show_session_info()
  end, { desc = "Show Aider session info" })

  vim.api.nvim_create_user_command("AiderShowFiles", function()
    require("aider-ui.ui.files_finder").show_files()
  end, { desc = "Show Aider files" })

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
    require("aider-ui.ui.preview_diff").preview_current_last_change()
  end, { desc = "View the last change in Aider" })

  vim.api.nvim_create_user_command("AiderLintCurrentBuffer", function()
    chat.lint_current_buffer()
  end, { desc = "Lint the current buffer using Aider" })

  vim.api.nvim_create_user_command("AiderCmd", function()
    cmd_input.cmd_popup()
  end, { desc = "Show Aider command input" })
end

return M
