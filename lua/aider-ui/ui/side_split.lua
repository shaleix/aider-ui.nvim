local common = require("aider-ui.ui.common")
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")

local mapOpts = { noremap = true }

local M = {
  split = nil,
}

local function set_split_winbar(winid)
  local session_status = sessions.list_session_status()
  local session_names = {}
  for _, session in ipairs(session_status) do
    if session.is_current then
      table.insert(session_names, "%#DiagnosticError#" .. session.name .. "%*")
    else
      table.insert(session_names, session.name)
    end
  end
  local content = table.concat(session_names, "%#Comment# | %#Normal#")
  local winbar_content = string.format("Aider Session: %s", content)
  vim.api.nvim_set_option_value("winbar", winbar_content, { win = winid })
end

M.show_aider_split = function(new_session_name)
  local Split = require("nui.split")
  local current_session = sessions.current_session()
  if current_session == nil then
    current_session = sessions.create_session(new_session_name)
  end
  if not M.is_split_visible() then
    M.split = Split({
      win_options = {
        number = false,
      },
      size = {
        width = 85,
      },
      buf_options = {
        filetype = "aiderpanel",
      },
      relative = "editor",
      enter = false,
      position = "right",
    })
  end
  M.split:mount()

  -- vim.api.nvim_set_current_win(current_split.winid)
  vim.api.nvim_win_call(M.split.winid, function()
    vim.wo.winfixbuf = false
  end)

  vim.api.nvim_win_set_buf(M.split.winid, current_session.bufnr)
  M.split.bufnr = current_session.bufnr
  vim.api.nvim_buf_call(M.split.bufnr, function()
    vim.opt_local.signcolumn = "no"
    vim.opt_local.number = false
  end)
  vim.api.nvim_win_call(M.split.winid, function()
    vim.wo.winfixbuf = true
  end)

  M.split:map("n", "<C-y>", M.aider_hide, mapOpts)
  M.split:map("t", "<C-y>", M.aider_hide, mapOpts)
  M.split:map("n", "<C-q>", M.aider_hide, mapOpts)
  M.split:map("t", "<C-q>", M.aider_hide, mapOpts)
  M.split:map("n", "q", M.aider_hide, mapOpts)
  M.split:map("t", "<C-o>", function()
    vim.api.nvim_input("<C-\\><C-n>")
  end, mapOpts)
  M.split:map("n", "L", function()
    sessions.next_session()
  end, mapOpts)
  M.split:map("n", "E", function()
    sessions.close_session()
  end, mapOpts)
  set_split_winbar(M.split.winid)
  return current_session
end

function M.is_split_visible()
  if M.split == nil or M.split.winid == nil then
    return false
  end
  local wininfo = vim.fn.getwininfo(M.split.winid)
  if #wininfo == 0 then
    return false
  end
  return true
end

function M.aider_hide()
  if M.is_split_visible() then
    M.split:hide()
  end
end

function M.create_session()
  local title = " Aider New Session "
  common.input("Name: ", function(session_name)
    if session_name == "" then
      utils.warn("Seession name required", "Aider Warning")
      return
    end

    local is_valid = sessions.validate_new_session_name(session_name)
    if not is_valid then
      utils.warn("Session name already exist", "Aider Warning")
      return
    end
    sessions.create_session(session_name)
    M.show_aider_split()
  end, { title = title })
end

function M.toggle_aider_split()
  if M.is_split_visible() then
    M.aider_hide()
  else
    M.show_aider_split()
  end
end

return M
