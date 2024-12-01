local M = {}
local sessions = require("aider-ui.aider_sessions_manager")
local utils = require("aider-ui.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")

function M.switch_model()
  local current_session = sessions.current_session()
  if not current_session then
    utils.err("No active Aider session found", "Error")
    return
  end

  current_session:list_models(function(models)
    if not models or #models == 0 then
      utils.warn("No models available", "Warning")
      return
    end

    pickers
      .new({}, {
        prompt_title = "Select a Model",
        layout_config = {
          width = 100,
          height = 0.6,
        },
        finder = finders.new_table({
          results = models,
          entry_maker = function(model)
            return {
              value = model,
              ordinal = model,
              display = model,
            }
          end,
        }),
        sorter = require("telescope.config").values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          map("i", "<CR>", function()
            local selected_model = require("telescope.actions.state").get_selected_entry()
            if selected_model then
              current_session:model(selected_model.value, function(res)
                if res.error then
                  utils.err("Failed to switch model: " .. res.error.message, "Error")
                else
                  utils.info("Model switched to: " .. selected_model.value, "Success")
                end
              end)
            end
            require("telescope.actions").close(prompt_bufnr)
          end)
          return true
        end,
      })
      :find()
  end)
end

return M
