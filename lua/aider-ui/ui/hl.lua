local M = {}

M.colors = {
  H1 = "IncSearch",
  PromptTitle = "FloatTitle",
  Comment = "Comment",
  Normal = "NormalFloat",
  Error = "DiagnosticError",
  Warning = "DiagnosticWarn",
  Info = "DiagnosticInfo",
  Folder = "DiagnosticWarn",
  Button = "CursorLine",
  ButtonActive = "Visual",
  InputFloatBorder = "Normal",
  InputFloatNormal = "Normal",
}

M.did_setup = false

function M.set_hl()
  for hl_group, link in pairs(M.colors) do
    local hl = type(link) == "table" and link or { link = link }
    hl.default = true
    vim.api.nvim_set_hl(0, "Aider" .. hl_group, hl)
  end
end

function M.setup()
  if M.did_setup then
    return
  end

  M.did_setup = true

  M.set_hl()
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      M.set_hl()
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      M.set_hl()
    end,
  })
end

return M
