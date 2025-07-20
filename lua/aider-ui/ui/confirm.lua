local Layout = require("nui.layout")
local nui_popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local common = require("aider-ui.ui.common")
local events = require("aider-ui.events")
local utils = require("aider-ui.utils")

local M = {}
local MIN_WIDTH = 70

local sessions_manager = require("aider-ui.aider_sessions_manager")
local configs = require("aider-ui.config").options

-- Setup auto confirmation popup handler
function M.setup()
  if configs.auto_pop_confirm then
    events.AskConfirm:add_handler(function()
      vim.defer_fn(function()
        for _, session in ipairs(sessions_manager.sessions) do
          if session.need_confirm and session.confirm_info then
            M.show_confirm(session)
            break
          end
        end
      end, 200)
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

local function render_confirm(session, popup, result)
  local NuiLine = require("nui.line")
  local NuiText = require("nui.text")

  local lines = {}

  -- Add output history if available
  local last_idx = session.confirm_info.last_confirm_output_idx
  if last_idx then
    session:get_output_history({ start_index = last_idx }, function(output_history)
      if output_history and #output_history > 0 then
        for _, line in ipairs(output_history) do
          table.insert(lines, NuiLine({ NuiText(line, "AiderComment") }))
        end
        table.insert(lines, NuiLine({ NuiText("") }))
      end
      table.insert(
        lines,
        NuiLine({ NuiText(" ", "AiderWarning"), NuiText(session.confirm_info.question, "AiderWarning") })
      )
      -- Add options
      local option_line = NuiLine({ NuiText("> ", "AiderWarning") })
      for _, opt in ipairs(session.confirm_info.options or {}) do
        option_line:append(NuiText(" " .. opt.label .. " ", result == opt.value and "AiderH1" or ""))
        option_line:append(NuiText(" "))
      end
      table.insert(lines, option_line)
      -- Calculate max display width
      local popup_width = MIN_WIDTH
      local max_width = MIN_WIDTH + 60  -- 新增最大宽度限制
      for _, line in ipairs(lines) do
        local line_text = ""
        for _, text in ipairs(line._texts) do
          line_text = line_text .. text:content()
        end
        local line_width = vim.fn.strdisplaywidth(line_text)
        -- 应用宽度限制
        if line_width > max_width then
          line_width = max_width
        end
        if line_width > popup_width then
          popup_width = line_width
        end
      end

      for i, line in ipairs(lines) do
        line:render(popup.bufnr, -1, i)
      end
      popup:update_layout({
        size = {
          width = popup_width,
          height = #lines,
        },
      })
      if not popup.mounted then
        -- Mount popup directly
        popup:mount()
        common.dim(popup.bufnr)
        vim.api.nvim_set_current_win(popup.winid)
      end
    end)
  end
end

function M.show_confirm(session_with_confirm)
  if not session_with_confirm then
    utils.info("No session requires confirmation")
    return
  end
  local current_value = session_with_confirm.confirm_info.default
  local options = session_with_confirm.confirm_info.options or {}
  local original_winid = vim.api.nvim_get_current_win()

  -- Create standalone confirmation popup
  local popup = nui_popup({
    focusable = true,
    border = {
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {
        top = " Aider Confirm (" .. session_with_confirm.name .. ") ",
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
      width = MIN_WIDTH,
      height = 4,
    },
    position = { row = "20%", col = "50%" },
    relative = "editor",
    win_options = {
      winhighlight = "Normal:AiderInputFloatNormal,FloatBorder:AiderInputFloatBorder",
    },
  })

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
    popup:unmount()
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
    render_confirm(session_with_confirm, popup, current_value)
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
    render_confirm(session_with_confirm, popup, current_value)
  end)

  popup:map("n", "<CR>", function()
    on_confirm(current_value)
    popup:unmount()
  end)

  popup:on(event.BufLeave, unmount_all)
  render_confirm(session_with_confirm, popup, current_value)
end

return M
