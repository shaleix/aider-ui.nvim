local M = {}
local common = require("aider-ui.ui.common")
local files = require("aider-ui.ui.files")
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")
local config = require("aider-ui.config")

local last_input_content = {}
local mapOpts = { noremap = true }

local function popup_input(prompt, on_submit, opts, title)
  local Popup = require("nui.popup")
  local NuiText = require("nui.text")
  local Layout = require("nui.layout")
  local allow_empty = opts.allow_empty or false
  local default_value = opts.default_value or (last_input_content[title] or "")
  local top_popup = Popup({
    position = "50%",
    size = {
      width = 80,
      height = 1,
    },
    border = {
      padding = {
        left = 2,
        right = 2,
      },
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {
        top = NuiText(title or "", "AiderPromptTitle"),
        top_align = "center",
        bottom = NuiText("dd: drop file, c: switch add/read, <CR>: open file", "AiderComment"),
        bottom_align = "right",
      },
    },
    buf_options = {
      filetype = "aider-fixed-content",
    },
    win_options = {},
  })

  local cursor_path
  local support_get_path = true
  utils.get_current_path(function(path)
    cursor_path = path
  end, function()
    support_get_path = false
  end)

  local bottom_popup = Popup({
    position = "50%",
    size = {
      width = 80,
      height = 5,
    },
    enter = true,
    border = {
      padding = {
        left = 2,
        right = 2,
        top = 0,
        bottom = 1,
      },
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {
        top = NuiText(" " .. prompt, "AiderInfo"),
        top_align = "left",
        bottom = NuiText("Ctrl + Enter: submit | Ctrl + t: insert cursor path", "AiderComment"),
        bottom_align = "right",
      },
    },
    buf_options = {
      filetype = "aider-input",
    },
    win_options = {
      winhighlight = "Normal:AiderInputFloatNormal,FloatBorder:AiderInputFloatBorder",
    },
  })
  local split = Popup({
    focusable = false,
    win_options = {
      winhighlight = "Normal:AiderInputFloatNormal,FloatBorder:AiderInputFloatBorder",
    },
  })

  local layout = Layout(
    {
      position = "50%",
      relative = "editor",
      size = {
        width = config.options.chat_size.width,
        height = config.options.chat_size.height,
      },
    },
    Layout.Box({
      Layout.Box(top_popup, { grow = 1 }),
      Layout.Box(split, { size = { height = 1 } }),
      Layout.Box(bottom_popup, { size = { height = 7 } }),
    }, { dir = "col" })
  )

  local original_winid = vim.api.nvim_get_current_win()

  local on_input_submit = function()
    local bufnr = bottom_popup.bufnr
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local value = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")

    if value == "" and not allow_empty then
      utils.warn("Submit content is empty, skip")
      return
    end

    layout:unmount()
    on_submit(value)
    last_input_content[title] = ""

    if original_winid then
      pcall(vim.api.nvim_set_current_win, original_winid)
    end
  end
  local handle_quite = function()
    local bufnr = bottom_popup.bufnr
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    last_input_content[title] = lines
    layout:unmount()

    if original_winid then
      pcall(vim.api.nvim_set_current_win, original_winid)
    end
  end

  top_popup:map("n", "q", handle_quite, mapOpts)
  top_popup:map("n", "<Esc>", handle_quite, mapOpts)
  top_popup:map("i", "<C-q>", handle_quite, mapOpts)
  top_popup:map("n", "<C-q>", handle_quite, mapOpts)
  top_popup:map("n", "<C-s>", on_input_submit, mapOpts)
  top_popup:map("n", "<Tab>", function()
    vim.api.nvim_set_current_win(bottom_popup.winid)
  end, mapOpts)
  top_popup:map("i", "<C-s>", function()
    vim.api.nvim_input("<C-[>")
    on_input_submit()
  end, mapOpts)
  top_popup:map("n", "<C-j>", function()
    vim.api.nvim_set_current_win(bottom_popup.winid)
    vim.api.nvim_input("a")
  end, mapOpts)

  bottom_popup:map("n", "<Tab>", function()
    vim.api.nvim_set_current_win(top_popup.winid)
  end, mapOpts)
  bottom_popup:map("n", "q", handle_quite, mapOpts)
  bottom_popup:map("n", "<Esc>", handle_quite, mapOpts)
  bottom_popup:map("i", "<C-q>", handle_quite, mapOpts)
  bottom_popup:map("n", "<C-q>", handle_quite, mapOpts)
  bottom_popup:map("i", "<C-k>", function()
    vim.api.nvim_set_current_win(top_popup.winid)
    vim.api.nvim_input("<C-[>")
  end, mapOpts)
  bottom_popup:map("n", "<C-k>", function()
    vim.api.nvim_set_current_win(top_popup.winid)
  end, mapOpts)
  bottom_popup:map("n", "<C-Enter>", on_input_submit, mapOpts)
  bottom_popup:map("i", "<C-Enter>", function()
    vim.api.nvim_input("<C-[>")
    on_input_submit()
  end, mapOpts)
  bottom_popup:map("n", "<C-t>", function()
    if cursor_path then
      local line = "Target position: " .. cursor_path
      vim.api.nvim_buf_set_lines(bottom_popup.bufnr, 0, 0, false, { line })
    end
  end, mapOpts)
  bottom_popup:map("i", "<C-t>", function()
    if not support_get_path then
      utils.warn("Get path not supported")
    end
    if cursor_path then
      local line = "Target position: " .. cursor_path
      vim.api.nvim_buf_set_lines(bottom_popup.bufnr, 0, 0, false, { line })
    end
  end, mapOpts)

  layout:mount()
  common.dim(bottom_popup.bufnr, { "WinClosed" })

  local lines = {}
  if type(default_value) == "string" then
    for line in default_value:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
  else
    lines = default_value
  end
  vim.api.nvim_buf_set_lines(bottom_popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_input("GA")
  return top_popup, layout
end

function M.show_input(input_type, default_value)
  if sessions.is_empty() then
    sessions.sync_open_buffers()
  end
  local titles = {
    ask = " ? ask ",
    code = "  code ",
    architect = "  architect ",
  }
  local title = titles[input_type] or "Unknown Input"
  local session_name = sessions.get_current_session_name()
  local session_title = " Aider Session: " .. session_name .. " "
  local opts = { allow_empty = false }
  if default_value ~= nil then
    opts.default_value = default_value
  end
  local session = sessions.current_session()
  if session == nil then
    utils.err("No active session.")
    return
  end
  local handle_submit = function(value)
    if input_type == "ask" then
      session:ask(value)
    elseif input_type == "code" then
      session:code(value)
    elseif input_type == "architect" then
      session:architect(value)
    end
  end
  local content_popup, layout = popup_input(title, handle_submit, opts, session_title)
  local file_buf = files.new_file_buffer(content_popup.bufnr, session)
  file_buf:keybind(content_popup, layout)
  file_buf:update_file_content()
end

M.show_ask_input = function(default_value)
  M.show_input("ask", default_value)
end

M.show_code_input = function(default_value)
  M.show_input("code", default_value)
end

M.show_architect_input = function(default_value)
  M.show_input("architect", default_value)
end

M.lint_current_buffer = function()
  local current_session = sessions.current_session()
  if not current_session then
    utils.err("No active Aider session found.")
    return
  end

  local buftype = vim.bo.buftype
  if buftype == "nofile" or buftype == "terminal" then
    utils.warn("Current buffer is not a file.", "Aider Lint")
    return
  end
  local buffer_number = vim.api.nvim_get_current_buf()
  local buffer_name = vim.api.nvim_buf_get_name(buffer_number)
  if buffer_name == "" then
    utils.warn("Current buffer is not a file.")
    return
  end

  local buffer_path = vim.fn.expand("%:p")
  current_session:lint(buffer_path)
end

return M
