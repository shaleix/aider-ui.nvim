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
    win_options = {},
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

  local on_input_submit = function()
    session:send_cmd(current_value)
    vim.api.nvim_input("<Esc>^lld$a")
  end
  local normal_submit = function()
    session:send_cmd(current_value)
    vim.api.nvim_input("^lld$a")
  end

  bottom_input:map("n", "q", handle_quite, mapOpts)
  bottom_input:map("i", "<C-y>", handle_quite, mapOpts)
  bottom_input:map("n", "<C-y>", handle_quite, mapOpts)
  bottom_input:map("n", "<Esc>", handle_quite, mapOpts)
  bottom_input:map("i", "<C-q>", handle_quite, mapOpts)
  bottom_input:map("n", "<C-q>", handle_quite, mapOpts)
  bottom_input:map("i", "<Enter>", on_input_submit, mapOpts)
  bottom_input:map("n", "<Enter>", normal_submit, mapOpts)

  original_winid = vim.api.nvim_get_current_win()

  layout:mount()
  vim.api.nvim_win_set_buf(top_popup.winid, session.bufnr)
  vim.api.nvim_set_current_win(top_popup.winid)
  vim.api.nvim_input("<C-\\><C-n>G")

  vim.defer_fn(function()
    vim.api.nvim_set_current_win(bottom_input.winid)
  end, 100)
end

return M
