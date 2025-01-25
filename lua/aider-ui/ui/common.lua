local M = {}
local last_input_content = {}
local mapOpts = { noremap = true }
local utils = require("aider-ui.utils")

M.input = function(prompt, on_submit, opts)
  local Input = require("nui.input")
  local title = opts.title or (" Aider " .. prompt)
  local allow_empty = opts.allow_empty or false
  local default_value = opts.default_value or (last_input_content[prompt] or "")
  local popup = Input({
    position = "50%",
    relative = "editor",
    size = {
      width = 80,
      height = 2,
    },
    border = {
      padding = {
        left = 1,
      },
      style = { " ", " ", " ", " ", " ", " ", " ", " " },
      text = {
        top = title,
        top_align = "center",
        bottom_align = "right",
      },
    },
    win_options = {
      winhighlight = "Normal:AiderInputFloatNormal,FloatBorder:AiderInputFloatBorder",
    },
  }, {
    prompt = prompt,
    default_value = default_value,
    on_submit = function(value)
      if value == "" and not allow_empty then
        utils.warn("submit content is empty, skip send")
        return
      end
      on_submit(value)
      last_input_content[prompt] = ""
    end,
    on_change = function(value)
      last_input_content[prompt] = value
    end,
  })
  popup:map("n", "q", function()
    popup:unmount()
  end, mapOpts)
  popup:map("n", "<Esc>", function()
    popup:unmount()
  end, mapOpts)
  popup:mount()
  M.dim(popup.bufnr)
end

M.display_session_chat_history = function(session, bufnr, winid)
  session:chat_history(function(history)
    if not history then
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, history)
    local lnum = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(winid, { lnum, 0 })
  end)
end


local blend = 50

M.dim = function(bufnr, events)
  local backdrop_name = "AiderUiBackdrop"

  local zindex = 50

  local backdrop_bufnr = vim.api.nvim_create_buf(false, true)
  local winnr = vim.api.nvim_open_win(backdrop_bufnr, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = vim.o.lines,
    focusable = false,
    style = "minimal",
    zindex = zindex - 1, -- ensure it's below the reference window
  })

  vim.api.nvim_set_hl(0, backdrop_name, { bg = "#000000", default = true })
  vim.wo[winnr].winhighlight = "Normal:" .. backdrop_name
  vim.wo[winnr].winblend = blend
  vim.bo[backdrop_bufnr].buftype = "nofile"
  local autocmd_events = { "WinClosed", "BufLeave" }
  if events ~= nil then
    autocmd_events = events
  end

  -- close backdrop when the reference buffer is closed
  vim.api.nvim_create_autocmd(autocmd_events, {
    once = true,
    buffer = bufnr,
    callback = function()
      if vim.api.nvim_win_is_valid(winnr) then
        vim.api.nvim_win_close(winnr, true)
      end
      if vim.api.nvim_buf_is_valid(backdrop_bufnr) then
        vim.api.nvim_buf_delete(backdrop_bufnr, { force = true })
      end
    end,
  })
end

return M
