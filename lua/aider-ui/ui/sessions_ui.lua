local M = {}
local sessions = require("aider-ui.aider_sessions_manager")
local configs = require("aider-ui.config").options
local common = require("aider-ui.ui.common")
local files = require("aider-ui.ui.files")
local utils = require("aider-ui.utils")
local mapOpts = { noremap = true }

local function update_session_info(bufnr)
  local current_session = sessions.current_session()
  if current_session == nil then
    utils.err("aider session not start")
    return
  end
  current_session:get_announcements(function(announcements)
    local lines = {}
    for _, announcement in ipairs(announcements) do
      table.insert(lines, announcement)
    end
    table.insert(lines, "")
    table.insert(lines, "")

    current_session:list_files(function(result)
      local file_lines = current_session:get_file_content(result)
      vim.list_extend(lines, file_lines)

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end)
  end)
end

function M.session_finder()
  local session_map = {}
  for _, session in ipairs(sessions.sessions) do
    session_map[session.name] = session
  end
  local session_status = sessions.list_session_status()

  -- 移除当前会话
  session_status = vim.tbl_filter(function(session)
    return session.is_current == false
  end, session_status)

  local pickers = require("telescope.pickers")
  local previewer = require("telescope.previewers").new_buffer_previewer({
    define_preview = function(self, entry, status)
      local session = session_map[entry.value]
      if session then
        session:list_files(function(result)
          local lines = session:get_file_content(result)
          if lines == nil then
            return
          end
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end)
      end
    end,
  })

  pickers
    .new({}, {
      prompt_title = "Select a Aider Session",
      layout_config = {
        width = 120,
        height = 35,
      },
      finder = require("telescope.finders").new_table({
        results = session_status,
        entry_maker = function(session)
          return {
            value = session.name,
            ordinal = session.name,
            display = session.name,
          }
        end,
      }),
      previewer = previewer,
      sorter = require("telescope.config").values.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        map("i", "<CR>", function()
          vim.api.nvim_input("<C-[>")
          local selected_session = require("telescope.actions.state").get_selected_entry()
          require("telescope.actions").close(prompt_bufnr)
          sessions.switch_session_by_name(selected_session.value)
        end)
        map("i", "<C-d>", function()
          local selected_session = require("telescope.actions.state").get_selected_entry()
          if selected_session then
            sessions.delete_session(selected_session.value)
            M.session_finder()
          end
        end)
        return true
      end,
    })
    :find()
end

M.save_session = function()
  local current_session = sessions.current_session()
  if current_session == nil then
    utils.err("aider session not start")
    return
  end

  local NuiText = require("nui.text")
  local Popup = require("nui.popup")
  local Input = require("nui.input")
  local Layout = require("nui.layout")
  local layout
  local top_popup = Popup({
    position = "50%",
    size = {
      width = 80,
      height = 1,
    },
    border = {
      padding = {
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = NuiText(" Save Aider Session ", "AiderPromptTitle"),
        top_align = "center",
      },
    },
    buf_options = {
      filetype = "aider-fixed-content",
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
        top = " Session Name ",
      },
    },
    win_options = {
      winhighlight = "NormalFloat:Normal,Normal:Normal",
    },
  }, {
    prompt = " > ",
    default_value = sessions.get_current_session_name() or "",
    on_submit = function(value)
      layout:unmount()
      local session_save_dir = configs.session_save_dir
      local file_path = vim.fn.fnamemodify(vim.fn.expand(session_save_dir), ":p") .. "/" .. value
      sessions.save_session(file_path)
    end,
  })

  layout = Layout(
    {
      position = "45%",
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

  top_popup:map("n", "q", handle_quite, mapOpts)
  top_popup:map("n", "<Esc>", handle_quite, mapOpts)
  top_popup:map("i", "<C-q>", handle_quite, mapOpts)
  top_popup:map("n", "<C-q>", handle_quite, mapOpts)
  top_popup:map("n", "<Tab>", function()
    vim.api.nvim_set_current_win(bottom_input.winid)
  end, mapOpts)
  top_popup:map("n", "<C-j>", function()
    vim.api.nvim_set_current_win(bottom_input.winid)
  end, mapOpts)

  bottom_input:map("n", "<Tab>", function()
    vim.api.nvim_set_current_win(top_popup.winid)
  end, mapOpts)
  bottom_input:map("n", "q", handle_quite, mapOpts)
  bottom_input:map("n", "<Esc>", handle_quite, mapOpts)
  bottom_input:map("i", "<C-q>", handle_quite, mapOpts)
  bottom_input:map("n", "<C-q>", handle_quite, mapOpts)
  bottom_input:map("i", "<C-k>", function()
    vim.api.nvim_set_current_win(top_popup.winid)
  end, mapOpts)
  bottom_input:map("n", "<C-k>", function()
    vim.api.nvim_set_current_win(top_popup.winid)
  end, mapOpts)

  original_winid = vim.api.nvim_get_current_win()

  layout:mount()
  local file_buf = files.new_file_buffer(top_popup.bufnr, current_session)
  file_buf:keybind(top_popup)
  file_buf:update_file_content()
  return top_popup
end

M.session_loader = function()
  local current_session = sessions.current_session()
  if current_session == nil then
    utils.err("aider session not start")
    return
  end

  local session_save_dir = require("aider-ui.config").options.session_save_dir
  require("telescope.builtin").find_files({
    prompt_title = "Select aider session to load",
    cwd = session_save_dir,
    no_ignore = false,
    follow = true,
    hidden = true,
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        if selection then
          local session_path = vim.fn.join({ session_save_dir, selection.value }, "/")
          print(session_path)
          current_session:load(session_path)
        end
        require("telescope.actions").close(prompt_bufnr)
      end)
      return true
    end,
  })
end

function M.show_session_info()
  local current_session = sessions.current_session()
  if current_session == nil then
    utils.err("aider session not start")
    return
  end

  local Popup = require("nui.popup")

  local popup = Popup({
    position = "50%",
    relative = "editor",
    size = {
      width = 90,
      height = 32,
    },
    border = {
      padding = {
        left = 1,
        right = 1,
      },
      style = "rounded",
      text = {
        top = " Session Info ",
        top_align = "center",
      },
    },
    buf_options = {
      filetype = "aider-fixed-content",
    },
    win_options = {},
    enter = true,
  })

  update_session_info(popup.bufnr)

  local handle_quite = function()
    popup:unmount()
  end

  popup:map("n", "q", handle_quite, mapOpts)
  popup:map("n", "<Esc>", handle_quite, mapOpts)
  popup:map("i", "<C-q>", handle_quite, mapOpts)
  popup:map("n", "<C-q>", handle_quite, mapOpts)

  popup:map("n", "dd", function()
    local current_line = vim.api.nvim_buf_get_lines(popup.bufnr, vim.fn.line(".") - 1, vim.fn.line("."), false)[1]
    if current_line and current_line:match("^%s") then
      current_line = vim.trim(current_line)
      current_session:drop_files({ current_line }, function()
        update_session_info(popup.bufnr)
      end)
    end
  end, mapOpts)

  popup:map("n", "c", function()
    local current_line = vim.api.nvim_buf_get_lines(popup.bufnr, vim.fn.line(".") - 1, vim.fn.line("."), false)[1]
    if current_line and current_line:match("^%s") then
      current_line = vim.trim(current_line)
      current_session:exchange_files({ current_line }, function()
        update_session_info(popup.bufnr)
      end)
    end
  end, mapOpts)

  popup:mount()
end

function M.create_session_in_working_dir(cwd)
  local title = " Aider New Session "
  common.input("Name: ", function(session_name)
    if session_name == "" then
      utils.warn("Session name is required")
      return
    end

    local is_valid = sessions.validate_new_session_name(session_name)
    if not is_valid then
      utils.warn("Session name already exist")
      return
    end
    sessions.create_session(session_name, function() end, cwd)
    require("aider-ui.ui.side_split").show_aider_split()
  end, { title = title })
end

return M
