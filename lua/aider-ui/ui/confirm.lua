local Layout = require("nui.layout")
local nui_popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local common = require("aider-ui.ui.common")
local events = require("aider-ui.events")
local utils = require("aider-ui.utils")

local M = {}

local sessions_manager = require("aider-ui.aider_sessions_manager")
local configs = require("aider-ui.config").options

-- Setup auto confirmation popup handler
function M.setup()
  if configs.auto_pop_confirm then
    events.AskConfirm:add_handler(function()
      for _, session in ipairs(sessions_manager.sessions) do
        if session.need_confirm and session.confirm_info then
          M.show_confirm(session)
          break
        end
      end
    end, "auto_confirm_pop")
  end
end

function M.toggle_aider_confirm()
  local sessions = sessions_manager.sessions
  for _, session in ipairs(sessions) do
    if session.need_confirm and session.confirm_info then
      M.show_confirm(session)
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
  if session.confirm_info.subject and #session.confirm_info.subject > 0 then
    for _, line in ipairs(session.confirm_info.subject) do
      table.insert(lines, NuiLine({ NuiText(line, "AiderWarning") }))
    end
    table.insert(lines, NuiLine({ NuiText("") }))
  end

  -- Add question line
  table.insert(
    lines,
    NuiLine({ NuiText(" ", "AiderWarning"), NuiText(session.confirm_info.question, "AiderWarning") })
  )
  table.insert(lines, NuiLine({ NuiText("") }))

  -- Add options
  local option_line = NuiLine({ NuiText("> ", "AiderWarning") })
  for _, opt in ipairs(session.confirm_info.options or {}) do
    option_line:append(NuiText(" " .. opt.label .. " ", result == opt.value and "AiderH1" or ""))
    option_line:append(NuiText(" "))
  end
  table.insert(lines, option_line)
  for i, line in ipairs(lines) do
    line:render(bufnr, -1, i)
  end
end

function M.show_confirm(session_with_confirm)
  local chat_history_popup, layout

  if not session_with_confirm then
    utils.info("No session requires confirmation")
    return
  end
  local current_value = session_with_confirm.confirm_info.default
  local options = session_with_confirm.confirm_info.options or {}
  local original_winid = vim.api.nvim_get_current_win()

  -- Calculate popup dimensions
  local subject_lines = 0
  local max_line_length = 0

  -- Calculate height and max line length
  if session_with_confirm.confirm_info.subject ~= nil and  #session_with_confirm.confirm_info.subject > 0 then
    subject_lines = #session_with_confirm.confirm_info.subject + 1
    max_line_length = math.max(max_line_length, #session_with_confirm.confirm_info.subject)
  end
  if session_with_confirm.confirm_info.question ~= nil then
    max_line_length = math.max(max_line_length, #session_with_confirm.confirm_info.question)
  end

  -- Add padding for options line
  max_line_length = max_line_length + 10

  -- Set width constraints
  local popup_width = math.min(math.max(max_line_length, 70), 120) -- min 50, max 90
  local popup_height = subject_lines + 4 -- 4 = question + empty line + options + padding

  -- Create confirmation popup as top part of layout
  local popup = nui_popup({
    focusable = true,
    border = {
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {
        top = " Aider: " .. session_with_confirm.name .. " ",
        top_align = "center",
      },
      padding = {
        top = 1,
        bottom = 0,
        left = 2,
        right = 2,
      },
    },
    size = {
      -- width = popup_width,
      height = popup_height,
    },
    win_options = {
      winhighlight = "Normal:AiderInputFloatNormal,FloatBorder:AiderInputFloatBorder",
    },
  })

  -- Initialize layout
  local boxes = {
    Layout.Box(popup, { size = "100%" }),
  }
  layout = Layout({
    position = { row = "20%", col = "50%" },
    relative = "editor",
    size = {
      width = popup_width,
      height = popup_height + 3, -- Adjust overall height
    },
  }, Layout.Box(boxes, { dir = "col" }))

  local function on_confirm(result)
    session_with_confirm:send_cmd(result)
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

  local function unmount_all()
    layout:unmount()
    if original_winid then
      pcall(vim.api.nvim_set_current_win, original_winid)
    end
  end

  popup:map("n", "<Esc>", unmount_all)
  popup:map("n", "q", unmount_all)

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

  popup:map("n", "<S-Tab>", function()
    local current_index = 1
    for i, opt in ipairs(options) do
      if opt.value == current_value then
        current_index = i
        break
      end
    end
    current_index = (current_index - 2) % #options + 1
    current_value = options[current_index].value
    render_confirm(session_with_confirm, popup.bufnr, current_value)
  end)

  popup:map("n", "<CR>", function()
    on_confirm(current_value)
    popup:unmount()
  end)

  popup:map("n", "t", function()
    if chat_history_popup then
      return
    end
    -- Create history popup (not mounted separately)
    chat_history_popup = nui_popup({
      border = {
        style = { " ", " ", " ", " ", " ", " ", " ", " " },
        text = {
          top = " Chat History ",
          top_align = "center",
        },
      },
      buf_options = {
        filetype = "markdown",
      },
    })

    layout:update(
      {
        size = {
          width = popup_width,
          height = 35,
        },
      },
      Layout.Box({
        Layout.Box(popup, {
          size = {
            height = popup_height + 3,
          },
        }),
        Layout.Box(chat_history_popup, {
          grow = 1,
        }),
      }, { dir = "col" })
    )

    -- Render history content
    common.display_session_chat_history(session_with_confirm, chat_history_popup.bufnr, chat_history_popup.winid)
  end)

  -- Mount layout first then the popup
  layout:mount()
  common.dim(popup.bufnr)
  vim.api.nvim_set_current_win(popup.winid)

  render_confirm(session_with_confirm, popup.bufnr, current_value)

  -- Set cursor position to the options line
  local option_line_number = subject_lines + 3 -- Options line is after subject and question
  vim.api.nvim_win_set_cursor(popup.winid, {option_line_number, 2}) -- Column 2 for "> "

  -- Auto close when leaving layout
  popup:on(event.BufLeave, unmount_all)
end

return M
