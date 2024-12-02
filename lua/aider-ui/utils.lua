local M = {}

local function get_notify_msg(msg)
  if type(msg) == "table" then
    return table.concat(msg, "\n")
  end
  return msg
end

M.info = function(msg, title)
  vim.notify(get_notify_msg(msg), vim.log.levels.INFO, { title = title or "Aider Info" })
end

M.err = function(msg, title)
  vim.notify(get_notify_msg(msg), vim.log.levels.ERROR, { title = title or "Aider Error" })
end

M.warn = function(msg, title)
  vim.notify(get_notify_msg(msg), vim.log.levels.WARN, { title = title or "Aider Warning" })
end

M.dir_path = string.sub(debug.getinfo(1).source, 2, string.len("/utils.lua") * -1)

local function in_targets(path, target_files)
  for _, file in ipairs(target_files) do
    if string.find(path, file) then
      return true
    end
  end
  return false
end

M.reload_buffers = function(target_files)
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    if in_targets(path, target_files) then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("e")
      end)
    end
  end
end

function M.scroll_bottom(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.api.nvim_input("<C-\\><C-n>G")
  end)
end

local sep_symbol = " > "

local function find_symbol(symbols, line, col)
  for _, symbol in ipairs(symbols) do
    if
      symbol.range.start.line <= line
      and symbol.range["end"].line >= line
      and symbol.range.start.character <= col
      and (symbol.range["end"].line > line or symbol.range["end"].character >= col)
    then
      local child_symbol = nil
      if symbol.children then
        child_symbol = find_symbol(symbol.children, line, col)
      end
      if child_symbol then
        return symbol.name .. sep_symbol .. child_symbol
      else
        return symbol.name
      end
    end
    if symbol.children then
      local child = find_symbol(symbol.children, line, col)
      if child then
        return symbol.name .. sep_symbol .. child
      end
    end
  end
  return nil
end

function M.get_current_path(callback, on_not_supported)
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line, col = pos[1] - 1, pos[2]

  local path = vim.api.nvim_buf_get_name(0)
  local file_name = (path == "" and "Empty") or path:match("([^/\\]+)[/\\]*$")

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  }

  -- local symbols = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 500)
  vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, function(err, symbols)
    if not symbols then
      return nil
    end

    local symbol = find_symbol(symbols, line, col)
    if not symbol then
      return nil
    end
    symbol = file_name .. sep_symbol .. symbol
    if callback ~= nil then
      callback(symbol)
    end
  end, function()
    if on_not_supported ~= nil then
      on_not_supported()
    end
  end)
end

return M
