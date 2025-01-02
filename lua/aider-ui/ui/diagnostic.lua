local M = {}
local if_nil = vim.F.if_nil
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")

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
        lines = {} -- Track unique line numbers
      }
    end

    -- Add diagnostic
    table.insert(file_diagnostics[fname].diagnostics, {
      code = diagnostic.code,
      lnum = diagnostic.lnum,
      end_lnum = diagnostic.end_lnum,
      message = diagnostic.message
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
      lines = lines
    })
  end

  -- Send to session
  session:fix_diagnostic(diagnostics_list)
end

function M.diagnostic(opts)
  local scope = if_nil(opts and opts.scope, "buffer")
  local pickers = require("telescope.pickers")

  local lnum = nil
  if scope == "line" then
    lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local diagnostics = get_diagnostics_for_scope(bufnr, lnum)
  for idx, diagnostic in ipairs(diagnostics) do
    diagnostic.idx = idx
  end
  local added_items = {}
  local entry_maker = function(diagnostic)
    local prefix = added_items[diagnostic.idx] and "  " or "   "
    return {
      value = diagnostic.idx,
      ordinal = diagnostic.idx,
      display = prefix .. vim.split(diagnostic.message, "\n")[1],
    }
  end

  -- 使用 Telescope 显示诊断信息
  if #diagnostics > 0 then
    local previewer = require("telescope.previewers").new_buffer_previewer({
      define_preview = function(self, entry, status)
        for _, diagnostic in ipairs(diagnostics) do
          if diagnostic.idx == entry.value then
            local message = diagnostic.message
            local lines = vim.split(message, "\n")
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            return
          end
        end
      end,
    })

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
            table.insert(added_items, item.value)
            -- Refresh the Telescope entries
            local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
            picker:refresh(
              require("telescope.finders").new_table({
                results = diagnostics,
                entry_maker = entry_maker,
              }),
              { reset_prompt = true }
            )
          end)
          map("i", "<C-d>", function()
            local item = require("telescope.actions.state").get_selected_entry()
            for i, v in ipairs(added_items) do
              if v == item.value then
                table.remove(added_items, i)
                break
              end
            end
            -- Refresh the Telescope entries
            local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
            picker:refresh(
              require("telescope.finders").new_table({
                results = diagnostics,
                entry_maker = entry_maker,
              }),
              { reset_prompt = true }
            )
          end)
          map("i", "<CR>", function()
            local added_diagnostics = {}
            for _, v in ipairs(added_items) do
              for _, diagnostic in ipairs(diagnostics) do
                if diagnostic.idx == v then
                  table.insert(added_diagnostics, diagnostic)
                end
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

return M
