local M = {}
local api, if_nil = vim.api, vim.F.if_nil

M.severity = {
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  HINT = 4,
  [1] = "ERROR",
  [2] = "WARN",
  [3] = "INFO",
  [4] = "HINT",
}

local diagnostic_severities = {
  [M.severity.ERROR] = { ctermfg = 1, guifg = "Red" },
  [M.severity.WARN] = { ctermfg = 3, guifg = "Orange" },
  [M.severity.INFO] = { ctermfg = 4, guifg = "LightBlue" },
  [M.severity.HINT] = { ctermfg = 7, guifg = "LightGrey" },
}

local function make_highlight_map(base_name)
  local result = {} --- @type table<vim.diagnostic.SeverityInt,string>
  for k in pairs(diagnostic_severities) do
    local name = M.severity[k]
    name = name:sub(1, 1) .. name:sub(2):lower()
    result[k] = "Diagnostic" .. base_name .. name
  end

  return result
end

-- TODO(lewis6991): these highlight maps can only be indexed with an integer, however there usage
-- implies they can be indexed with any vim.diagnostic.Severity
local floating_highlight_map = make_highlight_map("Floating")

local function get_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return api.nvim_get_current_buf()
  end
  return bufnr
end

local global_diagnostic_options = {
  signs = true,
  underline = true,
  virtual_text = true,
  float = true,
  update_in_insert = false,
  severity_sort = false,
}

local function enabled_value(option, namespace)
  local ns = namespace and M.get_namespace(namespace) or {}
  if ns.opts and type(ns.opts[option]) == "table" then
    return ns.opts[option]
  end

  local global_opt = global_diagnostic_options[option]
  if type(global_opt) == "table" then
    return global_opt
  end

  return {}
end

local function resolve_optional_value(option, value, namespace, bufnr)
  if not value then
    return false
  elseif value == true then
    return enabled_value(option, namespace)
  elseif type(value) == "function" then
    local val = value(namespace, bufnr) --- @type any
    if val == true then
      return enabled_value(option, namespace)
    else
      return val
    end
  elseif type(value) == "table" then
    return value
  end
  error("Unexpected option type: " .. vim.inspect(value))
end

local function get_resolved_options(opts, namespace, bufnr)
  local ns = namespace and M.get_namespace(namespace) or {}
  -- Do not use tbl_deep_extend so that an empty table can be used to reset to default values
  local resolved = vim.tbl_extend("keep", opts or {}, ns.opts or {}, global_diagnostic_options) --- @type table<string,any>
  for k in pairs(global_diagnostic_options) do
    if resolved[k] ~= nil then
      resolved[k] = resolve_optional_value(k, resolved[k], namespace, bufnr)
    end
  end
  return resolved
end

function M.open_float(opts, ...)
  -- Support old (bufnr, opts) signature
  local bufnr --- @type integer?
  if opts == nil or type(opts) == "number" then
    bufnr = opts
    opts = ... --- @type vim.diagnostic.Opts.Float
  else
    vim.validate({
      opts = { opts, "t", true },
    })
  end

  opts = opts or {}
  bufnr = get_bufnr(bufnr or opts.bufnr)

  do
    -- Resolve options with user settings from vim.diagnostic.config
    -- Unlike the other decoration functions (e.g. set_virtual_text, set_signs, etc.) `open_float`
    -- does not have a dedicated table for configuration options; instead, the options are mixed in
    -- with its `opts` table which also includes "keyword" parameters. So we create a dedicated
    -- options table that inherits missing keys from the global configuration before resolving.
    local t = global_diagnostic_options.float
    local float_opts = vim.tbl_extend("keep", opts, type(t) == "table" and t or {})
    opts = get_resolved_options({ float = float_opts }, nil, bufnr).float
  end

  local scope = ({ l = "line", c = "cursor" })[opts.scope] or opts.scope or "line"
  local lnum, col --- @type integer, integer
  local opts_pos = opts.pos
  if scope == "line" or scope == "cursor" then
    if not opts_pos then
      local pos = api.nvim_win_get_cursor(0)
      lnum = pos[1] - 1
      col = pos[2]
    elseif type(opts_pos) == "number" then
      lnum = opts_pos
    elseif type(opts_pos) == "table" then
      lnum, col = opts_pos[1], opts_pos[2]
    else
      error("Invalid value for option 'pos'")
    end
  else
    error("Invalid value for option 'scope'")
  end

  local diagnostics = vim.diagnostic.get(bufnr, opts)

  if scope == "line" then
    --- @param d vim.Diagnostic
    diagnostics = vim.tbl_filter(function(d)
      return lnum >= d.lnum and lnum <= d.end_lnum
    end, diagnostics)
  elseif scope == "cursor" then
    -- LSP servers can send diagnostics with `end_col` past the length of the line
    local line_length = #api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, true)[1]
    --- @param d vim.Diagnostic
    diagnostics = vim.tbl_filter(function(d)
      return d.lnum == lnum and math.min(d.col, line_length - 1) <= col and (d.end_col >= col or d.end_lnum > lnum)
    end, diagnostics)
  end

  if vim.tbl_isempty(diagnostics) then
    return
  end

  local severity_sort = if_nil(opts.severity_sort, global_diagnostic_options.severity_sort)
  if severity_sort then
    if type(severity_sort) == "table" and severity_sort.reverse then
      table.sort(diagnostics, function(a, b)
        return a.severity > b.severity
      end)
    else
      table.sort(diagnostics, function(a, b)
        return a.severity < b.severity
      end)
    end
  end

  local lines = {} --- @type string[]
  local highlights = {} --- @type table[]
  local header = if_nil(opts.header, "Diagnostics:")
  if header then
    vim.validate({
      header = {
        header,
        { "string", "table" },
        "'string' or 'table'",
      },
    })
    if type(header) == "table" then
      -- Don't insert any lines for an empty string
      if string.len(if_nil(header[1], "")) > 0 then
        table.insert(lines, header[1])
        table.insert(highlights, { hlname = header[2] or "Bold" })
      end
    elseif #header > 0 then
      table.insert(lines, header)
      table.insert(highlights, { hlname = "Bold" })
    end
  end

  local prefix_opt = if_nil(opts.prefix, (scope == "cursor" and #diagnostics <= 1) and "" or function(_, i)
    return string.format("%d. ", i)
  end)

  local prefix, prefix_hl_group --- @type string?, string?
  if prefix_opt then
    vim.validate({
      prefix = {
        prefix_opt,
        { "string", "table", "function" },
        "'string' or 'table' or 'function'",
      },
    })
    if type(prefix_opt) == "string" then
      prefix, prefix_hl_group = prefix_opt, "NormalFloat"
    elseif type(prefix_opt) == "table" then
      prefix, prefix_hl_group = prefix_opt[1] or "", prefix_opt[2] or "NormalFloat"
    end
  end

  local suffix_opt = if_nil(opts.suffix, function(diagnostic)
    return diagnostic.code and string.format(" [%s]", diagnostic.code) or ""
  end)

  local suffix, suffix_hl_group --- @type string?, string?
  if suffix_opt then
    vim.validate({
      suffix = {
        suffix_opt,
        { "string", "table", "function" },
        "'string' or 'table' or 'function'",
      },
    })
    if type(suffix_opt) == "string" then
      suffix, suffix_hl_group = suffix_opt, "NormalFloat"
    elseif type(suffix_opt) == "table" then
      suffix, suffix_hl_group = suffix_opt[1] or "", suffix_opt[2] or "NormalFloat"
    end
  end

  for i, diagnostic in ipairs(diagnostics) do
    if type(prefix_opt) == "function" then
      --- @cast prefix_opt fun(...): string?, string?
      local prefix0, prefix_hl_group0 = prefix_opt(diagnostic, i, #diagnostics)
      prefix, prefix_hl_group = prefix0 or "", prefix_hl_group0 or "NormalFloat"
    end
    if type(suffix_opt) == "function" then
      --- @cast suffix_opt fun(...): string?, string?
      local suffix0, suffix_hl_group0 = suffix_opt(diagnostic, i, #diagnostics)
      suffix, suffix_hl_group = suffix0 or "", suffix_hl_group0 or "NormalFloat"
    end
    --- @type string?
    local hiname = floating_highlight_map[assert(diagnostic.severity)]
    local message_lines = vim.split(diagnostic.message, "\n")
    for j = 1, #message_lines do
      local pre = j == 1 and prefix or string.rep(" ", #prefix)
      local suf = j == #message_lines and suffix or ""
      table.insert(lines, pre .. message_lines[j] .. suf)
      table.insert(highlights, {
        hlname = hiname,
        prefix = {
          length = j == 1 and #prefix or 0,
          hlname = prefix_hl_group,
        },
        suffix = {
          length = j == #message_lines and #suffix or 0,
          hlname = suffix_hl_group,
        },
      })
    end
  end

  -- Used by open_floating_preview to allow the float to be focused
  if not opts.focus_id then
    opts.focus_id = scope
  end
  local float_bufnr, winnr = vim.lsp.util.open_floating_preview(lines, "plaintext", opts)
  for i, hl in ipairs(highlights) do
    local line = lines[i]
    local prefix_len = hl.prefix and hl.prefix.length or 0
    local suffix_len = hl.suffix and hl.suffix.length or 0
    if prefix_len > 0 then
      api.nvim_buf_add_highlight(float_bufnr, -1, hl.prefix.hlname, i - 1, 0, prefix_len)
    end
    api.nvim_buf_add_highlight(float_bufnr, -1, hl.hlname, i - 1, prefix_len, #line - suffix_len)
    if suffix_len > 0 then
      api.nvim_buf_add_highlight(float_bufnr, -1, hl.suffix.hlname, i - 1, #line - suffix_len, -1)
    end
  end

  return float_bufnr, winnr
end

return M
