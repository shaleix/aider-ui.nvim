local rpc = require("aider-ui.rpc")
local utils = require("aider-ui.utils")
local configs = require("aider-ui.config").options
local events = require("aider-ui.events")

---@alias handle_res fun(res: table)
---@class ConfirmInfo
---@field question string 确认问题
---@field default string 默认选项值
---@field options {label: string, value: string}[] 选项列表
---@field subject string[]? 可选主题文本（分行显示）
---@field last_confirm_output_idx integer 输出历史中的索引，用于定位确认请求时的输出位置

---@class Session
---@field name string
---@field job_id number
---@field port number
---@field dir string|nil
---@field watch_files boolean
---@field on_started function|nil
---@field modify_history {path: string, abs_path: string, before_path: string, after_path: string, diff_summary: {added: integer, removed: integer}}[]
---@field bufnr number
---@field confirm_info ConfirmInfo|nil
---@field processing boolean
---@field need_confirm boolean
---@field last_file_content_bufnr number|nil
---@field last_info_content_bufnr number|nil
local Session = {}

local function common_on_response(res, method, params)
  if res.error and res.error ~= nil then
    utils.err(vim.inspect(res.error))
  else
    local result_str = vim.inspect(res.result)
    result_str = result_str:sub(2, -2)
    utils.info(result_str)
  end
end

---@param session_name string
---@param bufnr number
---@param opts table
---@return Session
local function create(session_name, bufnr, opts)
  local cwd = opts.cwd or nil
  local watch_files = opts.watch_files or false
  local on_exit = opts.on_exit or function() end

  local python_path = configs.python_path
  local server_path = utils.dir_path .. "aider_server.py"
  local cmd_args = {
    python_path,
    server_path,
  }
  local aider_cmd_args
  if type(configs.aider_cmd_args) == "function" then
    aider_cmd_args = configs.aider_cmd_args(watch_files)
  elseif type(configs.aider_cmd_args) == "table" then
    aider_cmd_args = configs.aider_cmd_args
  else
    aider_cmd_args = {}
  end

  for _, arg in ipairs(aider_cmd_args) do
    table.insert(cmd_args, arg)
  end
  local cmd = table.concat(cmd_args, " ")
  local s = {
    port = nil,
    bufnr = bufnr,
    name = session_name,
    confirm_info = nil,
    modify_history = {},
    processing = true,
    need_confirm = false,
    last_file_content_bufnr = nil,
    last_info_content_bufnr = nil,
    on_started = opts.on_started,
    dir = cwd or ".",
    watch_files = watch_files,
    exited = false,
  }
  local linsten_process = function()
    local client = s:get_client()
    client:connect(function(res)
      if res.result ~= nil then
        pcall(function(result)
          s:handle_notify(result)
        end, res.result)
      end
      if s.exited then
        return
      end
      client:send("notify", {})
    end)
    client:send("notify", {})
  end
  s.job_id = vim.api.nvim_buf_call(bufnr, function()
    local term_opts = {
      bufnr = bufnr,
      on_stdout = function(job_id, data, event)
        if s.port ~= nil or data == nil then
          if s.processing then
            events.GetOutput:emit({ job_id = job_id })
          end
          return
        end
        for _, line in pairs(data) do
          local port_match = line:match("Aider server port: (%d+)")
          if port_match then
            s.port = tonumber(port_match)
            linsten_process()
          end
        end
      end,
      cwd = cwd,
      on_exit = on_exit,
      term = true,
    }
    return vim.fn.jobstart(cmd, term_opts)
  end)
  setmetatable(s, { __index = Session })
  return s
end

---@return Client
function Session:get_client()
  return rpc.create_client("127.0.0.1", self.port)
end

---@param cmd string
function Session:send_cmd(cmd)
  vim.fn.chansend(self.job_id, cmd .. "\n")
end

function Session:interrupt()
  vim.fn.chansend(self.job_id, vim.api.nvim_replace_termcodes("<C-c>", true, true, true))
  self.processing = false
  self.need_confirm = false
end

---@param on_response? handle_res
function Session:exit(on_response)
  local client = self:get_client()
  client:connect(function(res)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error))
    else
      utils.info("Aider Exit")
    end
    if on_response then
      on_response(res.result)
    end
  end)
  client:send("exit", {})
end

---@param res table
function Session:handle_notify(res)
  if res.type == "aider_start" then
    self.processing = false
    utils.info(res.message)
    if self.on_started ~= nil then
      self.on_started()
    end
    events.SessionStarted:emit({ session = self })
  elseif res.type == "confirm_ask" then
    if not configs.auto_pop_confirm then
      utils.warn(res.prompt, "Aider Confirm (" .. self.name .. ")")
    end
    self.confirm_info = res.confirm_info
    self.need_confirm = true
    events.AskConfirm:emit({ session = self })
  elseif res.type == "confirm_complete" then
    self.confirm_info = nil
    self.need_confirm = false
  elseif res.type == "notify" then
    utils.info(res.message, "Aider Command Message")
  elseif res.type == "cmd_start" then
    self.processing = true
    events.ChatStart:emit({ session = self })
    utils.info(res.message, "Aider Command Message")
  elseif res.type == "cmd_complete" then
    self.processing = false
    self.need_confirm = false
    events.ChatCompleted:emit({ session = self })
    if res.message ~= nil and res.message ~= "" then
      utils.info(res.message, "Aider Command Message")
    end
    if res.modified_info ~= nil then
      table.insert(self.modify_history, res.modified_info)
      local files = {}
      for _, item in ipairs(res.modified_info) do
        table.insert(files, item.abs_path)
      end
      utils.reload_buffers(files)
    end
  elseif res.type == "aider_exit" then
    self.processing = false
    self.need_confirm = false
    self.exited = true
    events.SessionExit:emit({ session = self })
    utils.info("Aider session exited", "Aider")
  end
end

---@param content string
function Session:ask(content)
  self:send_cmd("{\n" .. "/ask " .. content .. "\n}")
end

---@param content string
function Session:code(content)
  self:send_cmd("{\n" .. "/code " .. content .. "\n}")
end

---@param content string
function Session:architect(content)
  self:send_cmd("{\n" .. "/architect " .. content .. "\n}")
end

---@param filenames string
function Session:lint(filenames)
  self:send_cmd("/lint " .. filenames)
end

---@param on_response? handle_res
function Session:clear(on_response)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_response ~= nil then
      on_response(res.result)
    end
  end)
  client:send("clear", {})
end

---@param on_response? handle_res
function Session:reset(on_response)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_response ~= nil then
      on_response(res.result)
    end
  end)
  client:send("reset", {})
end

local get_all_buffers = function()
  local buffers = vim.api.nvim_list_bufs()
  local buffer_paths = {}
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local file_path = vim.api.nvim_buf_get_name(buf)
      if file_path ~= "" and vim.fn.filereadable(file_path) == 1 then
        table.insert(buffer_paths, file_path)
      end
    end
  end
  return buffer_paths
end

function Session:sync_open_buffers()
  local buffer_paths = get_all_buffers()
  local current_buffer_path = vim.fn.expand("%:p")
  local add_buffers = {}
  local read_only_buffers = {}

  for _, path in ipairs(buffer_paths) do
    if path == current_buffer_path then
      table.insert(add_buffers, path)
    else
      table.insert(read_only_buffers, path)
    end
  end

  if #add_buffers > 0 then
    self:add_files(add_buffers)
  end

  if #read_only_buffers > 0 then
    self:read_files(read_only_buffers)
  end

  if #buffer_paths == 0 then
    utils.info("No buffers to send.")
  end
end

---@param callback? handle_res
function Session:list_files(callback)
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), method .. " error (Aider)")
    else
      if callback ~= nil then
        callback(res.result)
      end
    end
  end)
  client:send("list_files", {})
end

---@param file_paths string[]
---@param on_res? handle_res
function Session:add_files(file_paths, on_res)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_res ~= nil then
      on_res(res.result)
    end
  end)
  client:send("add_files", file_paths)
end

---@param file_paths string[]
---@param on_res? handle_res
function Session:read_files(file_paths, on_res)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_res ~= nil then
      on_res(res.result)
    end
  end)
  client:send("read_files", file_paths)
end

---@param file_paths string[]
---@param on_res? handle_res
function Session:drop_files(file_paths, on_res)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_res ~= nil then
      on_res(res.result)
    end
  end)
  client:send("drop", file_paths)
end

---@param file_paths string[]
---@param on_res? handle_res
function Session:exchange_files(file_paths, on_res)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_res ~= nil then
      on_res(res.result)
    end
  end)
  client:send("exchange_files", file_paths)
end

---@param callback? handle_res
function Session:get_announcements(callback)
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), method .. " error (Aider)")
    else
      if callback ~= nil then
        callback(res.result)
      end
    end
  end)
  client:send("get_announcements", {})
end

---@return table?
function Session:get_last_change()
  if #self.modify_history > 0 then
    return self.modify_history[#self.modify_history]
  else
    return nil
  end
end

---@param callback? handle_res
function Session:get_input_history(callback)
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), "get_input_history error (Aider)")
    else
      if callback ~= nil then
        callback(res.result)
      end
    end
  end)
  client:send("get_history", {})
end

---@param callback? handle_res
function Session:chat_history(callback)
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), "chat_history error (Aider)")
    else
      if callback ~= nil then
        callback(res.result)
      end
    end
  end)
  client:send("chat_history", {})
end

---@param callback? handle_res
---@param params table {start_index: number, end_index: number?}
function Session:get_output_history(params, callback)
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), "get_output_history error (Aider)")
    else
      if callback ~= nil then
        callback(res.result)
      end
    end
  end)
  client:send("get_output_history", params or {})
end

---@param message string
function Session:git_commit(message)
  self:send_cmd("/commit " .. message)
end

---@param message string
function Session:run(message)
  self:send_cmd("/run " .. message)
end

---@param path string
---@param on_response? handle_res
function Session:save(path, on_response)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_response ~= nil then
      on_response(res.result)
    end
  end)
  client:send("save", path)
end

---@param path string
---@param on_response? handle_res
function Session:load(path, on_response)
  local client = self:get_client()
  client:connect(function(res, method, params)
    common_on_response(res, method, params)
    if on_response ~= nil then
      on_response(res.result)
    end
  end)
  client:send("load", path)
end

--------------------------------------------------------
--- llm model
--------------------------------------------------------

---@param on_response? handle_res
function Session:list_models(on_response)
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), "list_models error (Aider)")
    else
      if on_response ~= nil then
        on_response(res.result)
      end
    end
  end)
  client:send("list_models", {})
end

---@param model_name string
function Session:model(model_name)
  self:send_cmd("/model " .. model_name)
end

---@param diagnostics table[] List of file diagnostics
function Session:fix_diagnostic(diagnostics)
  if self.processing then
    utils.warn("Aider is currently processing another command")
    return
  end
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), "fix_diagnostic error (Aider)")
    else
      self:send_cmd("fix-diagnostics")
    end
  end)
  client:send("fix_diagnostic", diagnostics)
end

---@param callback? handle_res
function Session:get_coder_info(callback)
  local client = self:get_client()
  client:connect(function(res, method, params)
    if res.error and res.error ~= nil then
      utils.err(vim.inspect(res.error), "get_coder_info error (Aider)")
    else
      if callback ~= nil then
        callback(res.result)
      end
    end
  end)
  client:send("get_coder_info", {})
end

return {
  create = create,
}
