local M = {}

local _setup = false

M.setup = function(opts)
  local config = require("aider-ui.config")
  config.setup(opts)
  require("aider-ui.command").setup()
  require("aider-ui.ui.hl").setup()
  require("aider-ui.ui.confirm").setup()
  _setup = true
end

-- list of session info: { name: str, processing: bool, is_current: bool, need_confirm: bool}
M.session_status = function()
  if not _setup then
    return {}
  end
  local aider_sessions = require("aider-ui.aider_sessions_manager")
  return aider_sessions.list_session_status()
end

return M
