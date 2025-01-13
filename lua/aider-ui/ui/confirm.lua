local nui_popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local utils = require("aider-ui.utils")

local M = {}

local sessions_manager = require("aider-ui.aider_sessions_manager")

function M.toggle_aider_confirm()
  local sessions = sessions_manager.sessions
  for _, session in ipairs(sessions) do
    if session.need_confirm and session.confirm_info then
      M.show_confirm()
      return
    end
  end
  utils.info("No session requires confirmation")
end

local function render_confirm(session, bufnr, result)
  local NuiLine = require("nui.line")
  local NuiText = require("nui.text")

  local lines = {}

  -- Add subject line if present
  if session.confirm_info.subject then
    table.insert(
      lines,
      NuiLine({ NuiText(session.confirm_info.subject, "AiderWarning") })
    )
    table.insert(lines, NuiLine({ NuiText("") }))
  end

  -- Add question line
  table.insert(
    lines,
    NuiLine({ NuiText("  ", "AiderWarning"), NuiText(session.confirm_info.question, "AiderWarning") })
  )
  table.insert(lines, NuiLine({ NuiText("") }))

  -- Add yes/no options
  table.insert(
    lines,
    NuiLine({
      NuiText(" "),
      NuiText(" Yes ", result == "y" and "AiderH1" or ""),
      NuiText(" "),
      NuiText(" No ", result == "n" and "AiderH1" or ""),
    })
  )
  for i, line in ipairs(lines) do
    line:render(bufnr, -1, i)
  end
end

function M.show_confirm()
  local sessions = sessions_manager.sessions
  local session_with_confirm = nil

  for _, session in ipairs(sessions) do
    if session.need_confirm and session.confirm_info then
      session_with_confirm = session
      break
    end
  end

  if not session_with_confirm then
    utils.info("No session requires confirmation")
    return
  end
  local current_value = session_with_confirm.confirm_info.default

  local popup = nui_popup({
    enter = true,
    position = "50%",
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Aider: " .. session_with_confirm.name .. " ",
        top_align = "center",
      },
      padding = {
        top = 1,
        bottom = 1,
        left = 2,
        right = 2,
      },
    },
    size = {
      width = "50%",
      height = 6,
    },
    -- win_options = {
    --   winhighlight = "Normal:Normal,FloatBorder:Normal",
    -- },
  })

  local function on_confirm(result)
    if session_with_confirm then
      session_with_confirm:send_cmd(result)
    end
  end

  -- Keymaps
  popup:map("n", "Y", function()
    on_confirm(true)
    popup:unmount()
  end)

  popup:map("n", "N", function()
    on_confirm(false)
    popup:unmount()
  end)

  popup:map("n", "<Esc>", function()
    popup:unmount()
  end)

  popup:map("n", "q", function()
    popup:unmount()
  end)

  popup:map("n", "<Tab>", function()
    current_value = current_value == "y" and "y" or "y"
    render_confirm(session_with_confirm, popup.bufnr, current_value)
  end)

  popup:map("n", "<CR>", function()
    on_confirm(current_value)
    popup:unmount()
  end)

  -- Show popup
  popup:mount()

  render_confirm(session_with_confirm, popup.bufnr, current_value)

  -- Auto close when leaving
  popup:on(event.BufLeave, function()
    popup:unmount()
  end)
end

return M
