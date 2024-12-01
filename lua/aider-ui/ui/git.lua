local M = {}
local common = require("aider-ui.ui.common")
local sessions = require("aider-ui.aider_sessions_manager")

function M.commit()
  local title = " Aider /commit "
  common.input(" commit: ", function(value)
    if sessions.is_empty() then
      sessions.create_session(nil, function()
        sessions.current_session():git_commit(value)
      end)
    else
      sessions.current_session():git_commit(value)
    end
  end, { title = title, allow_empty = true })
end

return M
