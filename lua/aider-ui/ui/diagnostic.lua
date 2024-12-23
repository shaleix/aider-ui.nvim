local M = {}
local api, if_nil = vim.api, vim.F.if_nil

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
  local telescope = require("telescope.builtin")
  local pickers = require("telescope.pickers")

  local lnum = nil
  if scope == "line" then
    lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local diagnostics = get_diagnostics_for_scope(bufnr, lnum)

  -- 使用 Telescope 显示诊断信息
  if #diagnostics > 0 then
    local previewer = require("telescope.previewers").new_buffer_previewer({
      define_preview = function(self, entry, status)
        -- local session = session_map[entry.value]
        -- if session then
        --   session:list_files(function(result)
        --     local lines = session:get_file_content(result)
        --     if lines == nil then
        --       return
        --     end
        --     vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        --   end)
        -- end
      end,
    })

    pickers
      .new({}, {
        prompt_title = "Send diagnostics to Aider",
        layout_config = {
          width = 120,
          height = 35,
        },
        finder = require("telescope.finders").new_table({
          results = diagnostics,
          entry_maker = function(session)
            return {
              value = session.message,
              ordinal = session.message,
              display = session.message,
            }
          end,
        }),
        previewer = previewer,
        sorter = require("telescope.config").values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          map("i", "<C-a>", function()
            local item = require("telescope.actions.state").get_selected_entry()
            print(item)
          end)
          map("i", "<C-d>", function()
            local item = require("telescope.actions.state").get_selected_entry()
            print(item)
          end)
          return true
        end,
      })
      :find()
  end
end

return M
