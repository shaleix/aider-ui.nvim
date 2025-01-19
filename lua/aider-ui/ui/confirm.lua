local nui_popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local utils = require("aider-ui.utils")
local events = require("aider-ui.events")

local M = {}

local sessions_manager = require("aider-ui.aider_sessions_manager")
local configs = require("aider-ui.config").options

-- Setup auto confirm pop handler
function M.setup()
  if configs.auto_pop_confirm then
    events.AskConfirm:add_handler(function(session)
      M.show_confirm()
    end, "auto_confirm_pop")
  end
end

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
    for _, line in ipairs(session.confirm_info.subject) do
      table.insert(lines, NuiLine({ NuiText(line, "AiderWarning") }))
    end
    table.insert(lines, NuiLine({ NuiText("") }))
  end

  -- Add question line
  table.insert(
    lines,
    NuiLine({ NuiText("  ", "AiderWarning"), NuiText(session.confirm_info.question, "AiderWarning") })
  )
  table.insert(lines, NuiLine({ NuiText("") }))

  -- Add options
  local option_line = NuiLine({NuiText(" ")})
  for _, opt in ipairs(session.confirm_info.options or {}) do
    option_line:append(NuiText(" " .. opt.label .. " ", result == opt.value and "AiderH1" or ""))
    option_line:append(NuiText(" "))
  end
  table.insert(lines, option_line)
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
  local options = session_with_confirm.confirm_info.options or {}

  -- Calculate popup dimensions
  local subject_lines = 0
  local max_line_length = 0

  -- Calculate height and max line length
  if session_with_confirm.confirm_info.subject ~= nil then
    subject_lines = #session_with_confirm.confirm_info.subject
    max_line_length = math.max(max_line_length, #session_with_confirm.confirm_info.subject)
  end
  if session_with_confirm.confirm_info.question ~= nil then
    max_line_length = math.max(max_line_length, #session_with_confirm.confirm_info.question)
  end

  -- Add padding for options line
  max_line_length = max_line_length + 10

  -- Set width constraints
  local popup_width = math.min(math.max(max_line_length, 50), 90) -- min 50, max 90
  local popup_height = subject_lines + 4 -- 4 = question + empty line + options + padding

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
      width = popup_width,
      height = popup_height,
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
  -- Add keymaps for each option
  for _, opt in ipairs(options) do
    local key = opt.value:upper()
    popup:map("n", key, function()
      on_confirm(opt.value)
      popup:unmount()
    end)
  end

  popup:map("n", "<Esc>", function()
    popup:unmount()
  end)

  popup:map("n", "q", function()
    popup:unmount()
  end)

  popup:map("n", "<Tab>", function()
    -- Find current index using for loop
    local current_index = 1
    for i, opt in ipairs(options) do
      if opt.value == current_value then
        current_index = i
        break
      end
    end
    current_value = options[(current_index % #options) + 1].value
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
