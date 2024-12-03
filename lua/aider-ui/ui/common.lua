local M = {}
local last_input_content = {}
local mapOpts = { noremap = true }
local utils = require("aider-ui.utils")

M.input = function(prompt, on_submit, opts)
  local Input = require("nui.input")
  local title = opts.title or (" Aider " .. prompt)
  local allow_empty = opts.allow_empty or false
  local default_value = opts.default_value or (last_input_content[prompt] or "")
  local popup = Input({
    position = "50%",
    relative = "editor",
    size = {
      width = 80,
      height = 2,
    },
    border = {
      style = "rounded",
      text = {
        top = title,
        top_align = "center",
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = "NormalFloat:Normal,Normal:Normal",
    },
  }, {
    prompt = prompt,
    default_value = default_value,
    on_submit = function(value)
      if value == "" and not allow_empty then
        utils.warn("submit content is empty, skip send")
        return
      end
      on_submit(value)
      last_input_content[prompt] = ""
    end,
    on_change = function(value)
      last_input_content[prompt] = value
    end,
  })
  popup:map("n", "q", function()
    popup:unmount()
  end, mapOpts)
  popup:map("n", "<Esc>", function()
    popup:unmount()
  end, mapOpts)
  popup:mount()
end

return M
