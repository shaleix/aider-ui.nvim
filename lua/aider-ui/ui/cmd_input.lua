local M = {}
local mapOpts = { noremap = true }
local sessions_manager = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")

M.cmd_popup = function()
  local session = sessions_manager.current_session()
  if session == nil then
    utils.err("No active session.")
    return
  end

  local history_bufnr = vim.api.nvim_create_buf(false, true)
  local Popup = require("nui.popup")
  local NuiText = require("nui.text")
  local Input = require("nui.input")
  local Layout = require("nui.layout")
  local title = "Aider Session: " .. session.name
  local current_value = ""

  local top_popup = Popup({
    position = "50%",
    size = {
      width = 80,
      height = 10,
    },
    border = {
      padding = {
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = NuiText(title or "", "AiderPromptTitle"),
        top_align = "center",
      },
    },
    buf = history_bufnr,
    win_options = {
      wrap = true,
      linebreak = true,
    },
    buf_options = {
      filetype = "markdown",
    },
  })

  local bottom_input = Input({
    position = "50%",
    relative = "editor",
    size = {
      width = 80,
      height = 1,
    },
    border = {
      style = "rounded",
      text = {
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = "NormalFloat:Normal",
    },
  }, {
    prompt = "  ",
    default_value = "",
    on_change = function(value)
      current_value = value
    end,
  })
  local layout = Layout(
    {
      position = "50%",
      relative = "editor",
      size = {
        width = 80,
        height = 30,
      },
    },
    Layout.Box({
      Layout.Box(top_popup, { grow = 1 }),
      Layout.Box(bottom_input, { size = { height = 3 } }),
    }, { dir = "col" })
  )

  local original_winid = nil

  local handle_quite = function()
    layout:unmount()
    if original_winid then
      pcall(vim.api.nvim_set_current_win, original_winid)
    end
  end

  local normal_submit = function()
    session:send_cmd(current_value)
    handle_quite()
  end

  bottom_input:map("n", "q", handle_quite, mapOpts)
  bottom_input:map("i", "<C-y>", handle_quite, mapOpts)
  bottom_input:map("n", "<C-y>", handle_quite, mapOpts)
  bottom_input:map("n", "<Esc>", handle_quite, mapOpts)
  bottom_input:map("i", "<C-q>", handle_quite, mapOpts)
  bottom_input:map("n", "<C-q>", handle_quite, mapOpts)
  bottom_input:map("i", "<Enter>", normal_submit, mapOpts)
  bottom_input:map("n", "<Enter>", normal_submit, mapOpts)

  original_winid = vim.api.nvim_get_current_win()

  layout:mount()
  session:chat_history(function(history)
    if not history then
      return
    end
    vim.api.nvim_buf_set_lines(top_popup.bufnr, 0, -1, false, history)
  end)

  vim.defer_fn(function()
    local lnum = vim.api.nvim_buf_line_count(top_popup.bufnr)
    vim.api.nvim_win_set_cursor(top_popup.winid, { lnum, 0 })
    vim.api.nvim_set_option_value("conceallevel", 2, { win = top_popup.winid})
  end, 100)
end

return M
