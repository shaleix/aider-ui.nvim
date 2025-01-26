local M = {
  layout = nil,
  is_visible = false,
  content_type = nil,
}
local FILE = 'file'

local common = require("aider-ui.ui.common")
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")
local files = require("aider-ui.ui.files")

local Popup = require("nui.popup")
local mapOpts = { noremap = true }

-- Display popup relative to editor
local function update_winbar(winid)
  local session_status = sessions.list_session_status()
  local session_names = {}
  local session_icon = "󰭻"
  local running_icon = ""

  for _, session in ipairs(session_status) do
    local icon = session.processing and running_icon or session_icon
    local hl_group = session.is_current and "AiderH1" or "AiderButtonActive"
    table.insert(session_names, ("%%#%s# %s %s %%*"):format(hl_group, icon, session.name))
  end

  local winbar_content = table.concat(session_names, " ")
  vim.api.nvim_set_option_value("winbar", winbar_content, { win = winid, scope="local" })
end

local function update_all(bufnr, winid)
  update_winbar(winid)
  local current_session = sessions.current_session()
  local file_buf = files.new_file_buffer(bufnr, current_session)
  -- file_buf:keybind(content_popup)
  file_buf:update_file_content()
end

function M.show_dashboard()
  local current_session = sessions.current_session()
  if not current_session then
    utils.warn("No active session")
    return
  end

  -- Create a single Popup
  local dashboard_popup = Popup({
    relative = "editor",
    position = {
      row = "50%",
      col = "50%",
    },
    size = { width = 80, height = 30 },
    border = {
      padding = {
        top = 1,
        left = 1,
        right = 1,
      },
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {
        top = " Files in Session ",
        top_align = "center",
      },
    },
    buf_options = {
      filetype = "aider-dashboard",
    },
  })

  -- Bind key mappings
  dashboard_popup:map("n", "q", M.close_dashboard, mapOpts)
  dashboard_popup:map("n", "<Esc>", M.close_dashboard, mapOpts)
  dashboard_popup:map("n", "H", function ()
    sessions.prev_session()
    update_all(dashboard_popup.bufnr, dashboard_popup.winid)
  end, mapOpts)
  dashboard_popup:map("n", "L", function ()
    sessions.next_session()
    update_all(dashboard_popup.bufnr, dashboard_popup.winid)
  end, mapOpts)

  M.layout = dashboard_popup
  dashboard_popup:mount()
  common.dim(dashboard_popup.bufnr)
  M.content_type = FILE
  update_all(dashboard_popup.bufnr, dashboard_popup.winid)

  M.is_visible = true
  vim.api.nvim_set_current_win(dashboard_popup.winid)
end

function M.close_dashboard()
  if M.layout then
    M.layout:unmount()
    M.layout = nil
    vim.cmd("checktime")
  end
  M.is_visible = false
end

function M.toggle_dashboard()
  if M.is_visible then
    M.close_dashboard()
  else
    M.show_dashboard()
  end
end

return M
