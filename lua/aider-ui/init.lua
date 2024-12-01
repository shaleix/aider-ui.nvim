local M = {}
local config = require("aider-ui.config")
local command = require("aider-ui.command")

M.setup = function (opts)
    config.setup(opts)
    command.setup()
end

return M
