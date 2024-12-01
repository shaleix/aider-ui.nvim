local M = {}
local sessions = require("aider-ui.aider_sessions_manager")

local local_doc_dir = ".aider_doc"

local telescope = require("telescope.builtin")

function M.doc_files_finder()
  telescope.find_files({
    prompt_title = "Select a file in " .. local_doc_dir,
    cwd = local_doc_dir,
    no_ignore = true,
    follow = true,
    hidden = true,
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        if selection then
          sessions.current_session():read_files({ selection.path })
        end
        require("telescope.actions").close(prompt_bufnr)
      end)
      return true
    end,
  })
end

function M.add_files_finder()
  telescope.git_files({
    prompt_title = "Select a file to add",
    cwd = vim.loop.cwd(),
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        if selection then
          sessions.current_session():add_files({ selection.path })
        end
        require("telescope.actions").close(prompt_bufnr)
      end)
      return true
    end,
  })
end

return M
