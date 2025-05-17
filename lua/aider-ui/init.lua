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

---@param cb fun(result: table)
function M.api.get_current_session_files(cb)
  local sessions = require("aider-ui.aider_sessions_manager")
  local current_session = sessions.current_session()
  if not current_session then
    return
  end
  current_session:list_files(function(response)
    cb(response.result)
  end)
end

---@param files string[]
---@param cb? fun(result: table)
function M.api.add_current_session_files(files, cb)
  local sessions = require("aider-ui.aider_sessions_manager")
  local current_session = sessions.current_session()
  if not current_session then
    return
  end
  current_session:add_files(files, function(response)
    if cb then
      cb(response.result)
    end
  end)
end

---@param files string[]
---@param cb? fun(result: table)
function M.api.drop_current_session_files(files, cb)
  local sessions = require("aider-ui.aider_sessions_manager")
  local current_session = sessions.current_session()
  if not current_session then
    return
  end
  current_session:drop_files(files, function(response)
    if cb then
      cb(response.result)
    end
  end)
end

return M
