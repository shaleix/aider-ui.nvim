local M = {}
local api, if_nil = vim.api, vim.F.if_nil

--return example: { {
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
--   } }
local function get_diagnostics_for_scope(bufnr, lnum)
  local diagnostics = vim.diagnostic.get(bufnr)

  if lnum ~= nil then
    diagnostics = vim.tbl_filter(function(d)
      return lnum >= d.lnum and lnum <= d.end_lnum
    end, diagnostics)
  end

  return diagnostics
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
    local prefix = added_items[diagnostic.idx] and "+" or ""
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
            for _, v in ipairs(added_items) do
              for _, diagnostic in ipairs(diagnostics) do
                if diagnostic.idx == v then
                  print(vim.inspect(diagnostic))
                end
              end
            end
          end)
          return true
        end,
      })
      :find()
  end
end

return M
