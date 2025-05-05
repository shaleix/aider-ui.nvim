local M = {}
local if_nil = vim.F.if_nil
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")
local SEVERITY = vim.diagnostic.severity
local entry_display = require("telescope.pickers.entry_display")

local errlist_type_map = {
  [SEVERITY.ERROR] = "E",
  [SEVERITY.WARN] = "W",
  [SEVERITY.INFO] = "I",
  [SEVERITY.HINT] = "N",
}

--diagnostic: {
--     _tags = {
--       unnecessary = true
--     },
--     bufnr = 2,
--     code = "unused-local",
--     col = 8,
--     end_col = 17,
--     end_lnum = 17,
--     lnum = 17,
--     message = "Unused local `telescope`.",
--     namespace = 59,
--     severity = 4,
--     source = "Lua Diagnostics.",
--     user_data = {
--       lsp = {
--         code = "unused-local"
--       }
--     }
--   }
local function get_diagnostics_for_scope(bufnr, lnum)
  local diagnostics = vim.diagnostic.get(bufnr)

  if lnum ~= nil then
    diagnostics = vim.tbl_filter(function(d)
      return lnum >= d.lnum and lnum <= d.end_lnum
    end, diagnostics)
  end

  return diagnostics
end

local function fix_diagnostics(diagnostics)
  local session = sessions.current_session()
  if session == nil then
    utils.err("No active session.")
    return
  end

  -- Group diagnostics by file
  local file_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    local fname = vim.api.nvim_buf_get_name(diagnostic.bufnr)
    if not file_diagnostics[fname] then
      file_diagnostics[fname] = {
        fname = fname,
        diagnostics = {},
        lines = {}, -- Track unique line numbers
      }
    end

    -- Add diagnostic
    table.insert(file_diagnostics[fname].diagnostics, {
      code = diagnostic.code,
      lnum = diagnostic.lnum,
      end_lnum = diagnostic.end_lnum,
      message = diagnostic.message,
    })
    -- Track line numbers for context
    for lnum = diagnostic.lnum, diagnostic.end_lnum do
      file_diagnostics[fname].lines[lnum] = true
    end
  end

  -- Convert to list format and prepare lines
  local diagnostics_list = {}
  for _, file in pairs(file_diagnostics) do
    -- Convert lines table to sorted list
    local lines = {}
    for lnum in pairs(file.lines) do
      table.insert(lines, lnum)
    end
    table.sort(lines)
    table.insert(diagnostics_list, {
      fname = file.fname,
      diagnostics = file.diagnostics,
      lines = lines,
    })
  end

  -- Send to session
  session:fix_diagnostic(diagnostics_list)
end

local function handle_buffer_diagnostics()
  local bufnr = vim.api.nvim_get_current_buf()
  local diagnostics = get_diagnostics_for_scope(bufnr)

  if #diagnostics > 0 then
    -- Sort diagnostics by severity (most severe first) and then by line number
    table.sort(diagnostics, function(a, b)
      if a.severity == b.severity then
        return a.lnum < b.lnum
      end
      return a.severity < b.severity
    end)

    local added_items = {}
    for idx, diagnostic in ipairs(diagnostics) do
      diagnostic.idx = idx
      table.insert(added_items, false)
    end
    local display_items = {
      { width = 4 },
      { width = 7 },
      { remaining = true },
    }

    local displayer = entry_display.create({
      separator = "▏",
      items = display_items,
    })
    local make_display = function(entry)
      local pos = string.format("%s %s", errlist_type_map[entry.type], entry.lnum)
      local line_info = {
        pos,
        "DiagnosticSign" .. SEVERITY[entry.type],
      }
      local prefix = added_items[entry.value] and "  " or "   "

      return displayer({
        {
          prefix,
          "DiagnosticSignError",
        },
        line_info,
        {
          entry.text,
        },
      })
    end

    local entry_maker = function(diagnostic)
      local message = vim.split(diagnostic.message, "\n")[1]
      return {
        value = diagnostic.idx,
        ordinal = message,
        display = make_display,
        lnum = diagnostic.lnum,
        end_lnum = diagnostic.end_lnum,
        col = diagnostic.col,
        end_col = diagnostic.end_col,
        text = message,
        type = diagnostic.severity,
        severity = diagnostic.severity,
        bufnr = diagnostic.bufnr,
        -- display = prefix .. message,
      }
    end

    -- 使用 Telescope 显示诊断信息
    local previewer = require("telescope.previewers").new_buffer_previewer({
      define_preview = function(self, entry, status)
        local message = entry.text
        local lines = vim.split(message, "\n")
        -- Prefix each line with "> "
        for i, line in ipairs(lines) do
          lines[i] = "> " .. line
        end
        local file_buf = entry.bufnr
        local start_lnum = entry.lnum
        local end_lnum = entry.end_lnum
        -- Get code context from the original buffer
        local code_lines = vim.api.nvim_buf_get_lines(file_buf, start_lnum, end_lnum + 1, false)
        -- Get filetype for syntax highlighting
        local filetype = vim.api.nvim_get_option_value("filetype", { buf = file_buf })
        -- Combine message and code
        local preview_lines = {}
        table.insert(preview_lines, "```" .. filetype)
        -- Add line numbers to code lines
        for i, line in ipairs(code_lines) do
          if i == 1 then
            -- Add column markers for first line
            local marker = string.rep(" ", entry.col) .. string.rep("^", entry.end_col - entry.col)
            table.insert(preview_lines, line)
            table.insert(preview_lines, marker)
          else
            table.insert(preview_lines, line)
          end
        end
        table.insert(preview_lines, "```")
        vim.list_extend(preview_lines, lines)
        table.insert(preview_lines, "")
        -- Write to preview buffer
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
        vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
        vim.api.nvim_set_option_value("conceallevel", 2, { win = self.state.winid })
      end,
    })

    local pickers = require("telescope.pickers")
    pickers
      .new({}, {
        prompt_title = "Send diagnostics to Aider",
        layout_strategy = "vertical",
        layout_config = {
          width = 0.6,
          height = 0.7,
          preview_cutoff = 1,
          preview_height = function(_, _, max_lines)
            local h = math.floor(max_lines * 0.2)
            return math.max(h, 10)
          end,
        },
        finder = require("telescope.finders").new_table({
          results = diagnostics,
          entry_maker = entry_maker,
        }),
        previewer = previewer,
        sorter = require("telescope.config").values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          map("i", "<C-a>", function()
            local item = require("telescope.actions.state").get_selected_entry()
            added_items[item.value] = true
            -- Refresh the current entry display
            local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
            local row = picker:get_selection_row()
            picker:refresh(
              require("telescope.finders").new_table({
                results = diagnostics,
                entry_maker = entry_maker,
              }),
              { reset_prompt = false }
            )
            vim.defer_fn(function()
              picker:set_selection(row + 1)
            end, 5)
          end)
          map("i", "<C-d>", function()
            local item = require("telescope.actions.state").get_selected_entry()
            added_items[item.value] = false
            -- Refresh the Telescope entries
            local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
            local row = picker:get_selection_row()
            picker:refresh(
              require("telescope.finders").new_table({
                results = diagnostics,
                entry_maker = entry_maker,
              }),
              { reset_prompt = false }
            )
            vim.defer_fn(function()
              picker:set_selection(row)
            end, 5)
          end)
          map("i", "<CR>", function()
            local added_diagnostics = {}
            for idx, diagnostic in ipairs(diagnostics) do
              if added_items[idx] then
                table.insert(added_diagnostics, diagnostic)
              end
            end
            fix_diagnostics(added_diagnostics)
            require("telescope.actions").close(prompt_bufnr)
          end)
          return true
        end,
      })
      :find()
  end
end

local function handle_line_diagnostics()
  local NuiText = require("nui.text")
  local NuiLine = require("nui.line")
  local Popup = require("nui.popup")
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local bufnr = vim.api.nvim_get_current_buf()
  local diagnostics = get_diagnostics_for_scope(bufnr, lnum)

  table.sort(diagnostics, function(a, b)
    if a.severity == b.severity then
      return a.lnum < b.lnum
    end
    return a.severity < b.severity
  end)

  if #diagnostics == 0 then
    utils.info("No diagnostics on current line")
    return
  end

  local selected = {}
  for idx, _ in ipairs(diagnostics) do
    selected[idx] = false
  end

  local total_lines = 0
  for _, diag in ipairs(diagnostics) do
    total_lines = total_lines + #vim.split(diag.message, "\n")
  end

  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local win_height = vim.api.nvim_win_get_height(0)

  local position = {
    row = cursor_row < (win_height / 2) and 2 or -total_lines - 1,
    col = 0,
  }

  local popup = Popup({
    enter = true,
    focusable = true,
    position = position,
    relative = "cursor",
    border = {
      style = "rounded",
      text = {
        top = NuiText(" Aider Lint ", "Comment"),
        bottom = NuiText("a,i,x,o to toggle | <CR> to fix | q to dismiss", "Comment"),
        bottom_align = "right",
      },
    },
    size = {
      width = 80,
      height = total_lines,
    },
  })

  local row_map = {}
  local refresh = function()
    row_map = {}
    local lines = {}
    for idx, diag in ipairs(diagnostics) do
      local msg_lines = vim.split(diag.message, "\n")
      for line_idx, line_text in ipairs(msg_lines) do
        local style_name = ""
        if diag.severity == SEVERITY.ERROR then
          style_name = "DiagnosticError"
        elseif diag.severity == SEVERITY.WARN then
          style_name = "DiagnosticWarn"
        elseif diag.severity == SEVERITY.INFO then
          style_name = "DiagnosticInfo"
        else
          style_name = "DiagnosticHint"
        end

        local components = {}
        if line_idx == 1 then
          components = {
            NuiText("[" .. (selected[idx] and "x" or " ") .. "]", style_name),
            NuiText(" " .. line_text, style_name),
          }
        else
          components = {
            NuiText("    " .. line_text, style_name),
          }
        end

        local diag_line = NuiLine(components)
        table.insert(lines, diag_line)
        table.insert(row_map, idx)
      end
    end

    for i, line in ipairs(lines) do
      line:render(popup.bufnr, -1, i)
    end
  end

  popup:map("n", { " ", "a", "i", "x", "o" }, function()
    local row = vim.api.nvim_win_get_cursor(popup.winid)[1]
    if row <= #row_map then
      local diag_idx = row_map[row]
      if diag_idx then
        selected[diag_idx] = not selected[diag_idx]
        refresh()
      end
    end
  end)

  popup:map("n", "<CR>", function()
    local selected_diagnostics = {}
    for i, sel in pairs(selected) do
      if sel then
        table.insert(selected_diagnostics, diagnostics[i])
      end
    end
    if #selected_diagnostics == 0 then
      utils.err("No diagnostics selected")
    else
      fix_diagnostics(selected_diagnostics)
      popup:unmount()
    end
  end)
  popup:map("n", "q", function()
    popup:unmount()
  end)

  popup:mount()
  refresh()
end

function M.diagnostic(opts)
  local scope = if_nil(opts and opts.scope, "buffer")
  if scope == "buffer" then
    handle_buffer_diagnostics()
  elseif scope == "line" then
    handle_line_diagnostics()
  else
    error("Unsupported scope type: " .. scope)
  end
end

return M
