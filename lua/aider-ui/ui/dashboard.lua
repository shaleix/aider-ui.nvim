local M = {
  layout = nil,
  is_visible = false,
  content_type = nil,
  original_winid = nil,  -- 新增：存储原始窗口ID
}
local FILE = "Files"
local DIFF_VIEW = "DiffView"

local common = require("aider-ui.ui.common")
local diff_view = require("aider-ui.ui.diff_view")
local files = require("aider-ui.ui.files")
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")

local Layout = require("nui.layout")
local Line = require("nui.line")
local Popup = require("nui.popup")
local Text = require("nui.text")
local mapOpts = { noremap = true }

-- 更新顶部会话栏
local function update_top_bar(top_popup)
  if not top_popup or not top_popup.winid or not vim.api.nvim_win_is_valid(top_popup.winid) then
    return
  end

  local bufnr = top_popup.bufnr
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- 第一行：会话列表
  local session_status = sessions.list_session_status()
  local session_icon = "󰭻"
  local running_icon = ""

  -- 计算会话文本总宽度
  local session_texts = {}
  local total_width = 0
  for _, session in ipairs(session_status) do
    local icon = session.processing and running_icon or session_icon
    local text = (" %s %s "):format(icon, session.name)
    table.insert(session_texts, text)
    total_width = total_width + vim.api.nvim_strwidth(text)
  end

  -- 添加会话间的空格宽度
  if #session_status > 1 then
    total_width = total_width + (#session_status - 1)
  end

  -- 计算左侧填充
  local win_width = vim.api.nvim_win_get_width(top_popup.winid)
  local left_padding = math.floor((win_width - total_width) / 2)

  local session_line = Line()
  -- 添加左侧填充
  if left_padding > 0 then
    session_line:append(string.rep(" ", left_padding))
  end

  -- 添加会话项
  for i, text in ipairs(session_texts) do
    local session = session_status[i]
    if session.is_current then
      session_line:append(Text(text, "AiderH1"))
    else
      session_line:append(Text(text, "AiderButtonActive"))
    end

    -- 添加会话间的空格（最后一个除外）
    if i < #session_texts then
      session_line:append(" ")
    end
  end
  session_line:render(bufnr, -1, 1)

  -- 第二行：空行
  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "" })

  -- 第三行：标签栏
  local tabs = {
    { text = " Files (F) ", value = FILE },
    { text = " DiffView (D) ", value = DIFF_VIEW },
  }
  local tab_line = Line()
  tab_line:append(" ")
  if M.content_type == nil then
    M.content_type = FILE
  end

  for i, tab in ipairs(tabs) do
    if tab.value == M.content_type then
      tab_line:append(Text(tab.text, "AiderH2"))
    else
      tab_line:append(Text(tab.text, "AiderButtonActive"))
    end

    if i < #tabs then
      tab_line:append(" ")
    end
  end

  tab_line:render(bufnr, -1, 3)
end

-- 更新底部内容区
local function update_bottom(bottom_popup)
  if not bottom_popup or not bottom_popup.winid or not vim.api.nvim_win_is_valid(bottom_popup.winid) then
    return
  end

  local bufnr = bottom_popup.bufnr

  -- Clear buffer before rendering new content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  if M.content_type == FILE then
    files.show_current_session(bottom_popup)
  elseif M.content_type == DIFF_VIEW then
    -- Show last change diff in the dashboard
    diff_view.show_current_session(bottom_popup)
  end
end

function M.show_dashboard()
  local current_session = sessions.current_session()
  if not current_session then
    utils.warn("No active session")
    return
  end

  -- 创建顶部弹出窗口 (高度3)
  local top_popup = Popup({
    relative = "editor",
    size = { width = 80, height = 3 },
    -- border = {
    --   style = { " ", " ", " ", " ", " ", " ", " ", " " },
    -- },
    buf_options = {
      filetype = "aider-dashboard-top",
    },
  })

  -- 创建底部弹出窗口
  local bottom_popup = Popup({
    relative = "editor",
    size = { width = 80, height = 27 },
    border = {
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {},
    },
    buf_options = {
      filetype = "aider-dashboard-bottom",
    },
  })

  -- 创建布局 (上下结构)
  local layout = Layout(
    {
      position = "50%",
      relative = "editor",
      size = { width = 0.8, height = 0.85 },
    },
    Layout.Box({
      Layout.Box(top_popup, { size = 3 }),
      Layout.Box(bottom_popup, { grow = 1 }),
    }, { dir = "col" })
  )

  -- 在挂载布局前记录当前窗口
  M.original_winid = vim.api.nvim_get_current_win()

  -- 挂载布局
  layout:mount()

  -- 保存布局组件
  M.layout = layout
  M.top_popup = top_popup
  M.bottom_popup = bottom_popup

  -- 绑定按键
  bottom_popup:map("n", "q", M.close_dashboard, mapOpts)
  bottom_popup:map("n", "<Esc>", M.close_dashboard, mapOpts)

  bottom_popup:map("n", "H", function()
    sessions.prev_session()
    update_top_bar(top_popup)
    update_bottom(bottom_popup)
  end, mapOpts)

  bottom_popup:map("n", "L", function()
    sessions.next_session()
    update_top_bar(top_popup)
    update_bottom(bottom_popup)
  end, mapOpts)

  bottom_popup:map("n", "m", function()
    require("aider-ui.ui.model").switch_model()
    M.close_dashboard()
  end)

  bottom_popup:map("n", "F", function()
    M.content_type = FILE
    update_top_bar(top_popup)
    update_bottom(bottom_popup)
  end, mapOpts)

  bottom_popup:map("n", "D", function()
    M.content_type = DIFF_VIEW
    update_top_bar(top_popup)
    update_bottom(bottom_popup)
  end, mapOpts)

  bottom_popup:map("n", "d", function()
    M.toggle_diff_view()
  end, mapOpts)

  -- 初始化内容
  update_top_bar(top_popup)
  update_bottom(bottom_popup)

  common.dim(bottom_popup.bufnr)
  M.is_visible = true
  vim.api.nvim_set_current_win(bottom_popup.winid)

  -- Add autocmd for diff view keybinds
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "aider-diff-view",
    callback = function()
      vim.api.nvim_buf_set_keymap(0, "n", "q", "<cmd>lua require('aider-ui.ui.dashboard').close_dashboard()<CR>", {})
    end,
  })
end

function M.close_dashboard()
  if M.layout then
    M.layout:unmount()
    M.layout = nil
    vim.cmd("checktime")
  end
  M.is_visible = false

  -- 返回到原始窗口（如果仍然有效）
  if M.original_winid and vim.api.nvim_win_is_valid(M.original_winid) then
    vim.api.nvim_set_current_win(M.original_winid)
    M.original_winid = nil  -- 重置避免内存泄漏
  end
end

function M.toggle_dashboard()
  if M.is_visible then
    M.close_dashboard()
  else
    M.show_dashboard()
  end
end

function M.toggle_diff_view()
  M.content_type = DIFF_VIEW
  M.toggle_dashboard()
end

return M
