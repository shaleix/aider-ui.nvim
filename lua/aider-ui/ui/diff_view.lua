local M = {}

local Job = require("plenary.job")
local Line = require("nui.line")
local Popup = require("nui.popup")
local Text = require("nui.text")
local common = require("aider-ui.ui.common")
local configs = require("aider-ui.config")
local devicons = require("nvim-web-devicons")
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")

---@param diff_files {path: string, before_path: string, after_path: string, opened: boolean}[]
function M.diff(diff_files)
  local lines = {}

  for _, item in ipairs(diff_files) do
    if not item.opened or item.cached_diff_lines == nil then
      item.opened = false
    end
  end
  for _, item in ipairs(diff_files) do
    local icon, _ = devicons.get_icon(item.path, nil, { default = true })
    icon = icon or ""
    local icon_text = Text(icon .. " ")
    local path_text = Text(item.path)
    local file_line = Line({ icon_text, path_text })
    table.insert(lines, file_line)
  end

  local popup = Popup({
    enter = true,
    focusable = true,
    position = "50%",
    relative = "editor",
    border = {
      padding = {
        left = 1,
        right = 1,
        top = 1,
        bottom = 1,
      },
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {
        top = Text(" Aider Diff View ", "AiderPromptTitle"),
        top_align = "center",
      },
    },
    on_close = function()
      if M.current_job then
        M.current_job:kill()
      end
    end,
    size = { width = 0.8, height = 0.8 },
    zindex = 50,
  })

  local function get_file_by_cursor(current_line)
    local start_line = 1
    for _, item in ipairs(diff_files) do
      local file_lines = 1
      if item.opened then
        file_lines = file_lines + (#item.cached_diff_lines or 0)
      end
      local end_line = start_line + file_lines - 1
      if current_line >= start_line and current_line <= end_line then
        return item, start_line
      end
      start_line = end_line + 1
    end
    return nil
  end

  popup:map("n", { "o", "<Tab>" }, function()
    local current_line = vim.api.nvim_win_get_cursor(popup.winid)[1]
    local target_item, line_index = get_file_by_cursor(current_line)

    if target_item then
      local content_length = target_item.opened and #target_item.cached_diff_lines or 0
      target_item.opened = not target_item.opened
      local end_lnum = line_index + content_length

      M.render_file(popup.bufnr, target_item, line_index, end_lnum, popup.winid)

      if current_line > line_index then
        vim.api.nvim_win_set_cursor(popup.winid, { line_index, 1 })
      end
    end
  end, { noremap = true })

  popup:map("n", "<CR>", function()
    local current_line = vim.api.nvim_win_get_cursor(popup.winid)[1]
    local target_item = get_file_by_cursor(current_line)

    if target_item then
      local line_content = vim.api.nvim_get_current_line()
      local lineNumberStr = line_content:match("│.*│.*│%s*(%d+).*")
      local lineNumber = tonumber(lineNumberStr)

      popup:unmount()

      if lineNumber then
        vim.cmd("edit +" .. lineNumber .. " " .. target_item.path)
      else
        vim.cmd("edit " .. target_item.path)
      end
    end
  end, { noremap = true })

  popup:map("n", "q", function()
    popup:unmount()
  end, { noremap = true })

  popup:mount()
  vim.api.nvim_set_option_value("undolevels", -1, { buf = popup.bufnr })
  M.init_render_diff(popup, diff_files)
  common.dim(popup.bufnr)
end

function M.init_render_diff(popup, diff_files)
  local bufnr = popup.bufnr
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  local current_lnum = 1
  for _, item in ipairs(diff_files) do
    local end_lnum = nil
    if item.opened and item.cached_diff_lines then
      end_lnum = current_lnum + #item.cached_diff_lines
    end
    current_lnum = M.render_file(bufnr, item, current_lnum, end_lnum, popup.winid)
  end
end

function M.render_file(bufnr, file, start_lnum, end_lnum, winid)
  if file.opened then
    if not file.cached_diff_lines then
      file.cached_diff_lines = {}

      local width = vim.api.nvim_win_get_width(winid or 0)

      local job = Job:new({
        command = "delta",
        args = {
          file.before_path,
          file.after_path,
          "--paging",
          "never",
          "--width",
          tostring(width),
          "--line-numbers",
          "--side-by-side",
        },
        on_stdout = function(_, data)
          table.insert(file.cached_diff_lines, data)
        end,
        on_exit = function(j, return_code)
          vim.defer_fn(function()
            file.cached_diff_lines = { table.unpack(file.cached_diff_lines, 5) }
            vim.schedule(function()
              M.handle_render_file(bufnr, file, start_lnum, end_lnum)
            end)
          end, 100)
        end,
      })
      job:start()
      return 0
    end
  end

  return M.handle_render_file(bufnr, file, start_lnum, end_lnum)
end

function M.handle_render_file(bufnr, file, start_lnum, end_lnum)
  local current_lnum = start_lnum

  local collapse_icon = file.opened and configs.options.icons.collapse_marks[2]
    or configs.options.icons.collapse_marks[1]
  local icon, _ = devicons.get_icon(file.path, nil, { default = true })
  local display_path = vim.fn.fnamemodify(file.path, ":.")
  icon = icon or ""
  local header_line = Line({
    Text(collapse_icon .. " ", "AiderComment"),
    Text(icon .. " "),
    Text(display_path),
  })
  header_line:render(bufnr, -1, current_lnum)
  current_lnum = current_lnum + 1

  if file.opened then
    local baleia = require("baleia").setup({})
    baleia.buf_set_lines(bufnr, start_lnum, end_lnum, false, file.cached_diff_lines)
    current_lnum = current_lnum + #file.cached_diff_lines
  else
    if end_lnum ~= nil then
      vim.api.nvim_buf_set_lines(bufnr, start_lnum, end_lnum, true, {})
    end
  end

  return current_lnum
end

function M.view_current_session_last_change()
  local session = sessions.current_session()
  if session == nil then
    utils.err("No active session.")
    return
  end
  local last_change = session:get_last_change()
  if last_change == nil then
    utils.info("No changes to preview.")
    return
  end
  M.diff(last_change)
end

return M
