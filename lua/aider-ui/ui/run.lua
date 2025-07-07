local M = {}
local common = require("aider-ui.ui.common")
local sessions = require("aider-ui.aider_sessions_manager")

function M.run()
  local title = " Aider /run "
  common.input(" run: ", function(value)
    if sessions.is_empty() then
      sessions.create_session(nil, function()
        sessions.current_session():run(value)
      end)
    else
      sessions.current_session():run(value)
    end
  end, { title = title, allow_empty = true })
end

return M
