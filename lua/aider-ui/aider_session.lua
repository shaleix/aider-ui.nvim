local rpc = require("aider-ui.rpc")
local utils = require("aider-ui.utils")
local configs = require("aider-ui.config").options

---@alias handle_res fun(res: table)

---@class Session
---@field name string
---@field job_id number
---@field port number
---@field on_started function|nil
---@field modify_history table
---@field bufnr number
---@field confirm_tips string|nil
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
  if watch_files then
    aider_cmd_args = configs.aider_cmd_args_watch_files
  else
    aider_cmd_args = configs.aider_cmd_args
  end
  for _, arg in ipairs(aider_cmd_args) do
    table.insert(cmd_args, arg)
  end
  local cmd = table.concat(cmd_args, " ")
  local s = {
    port = nil,
    bufnr = bufnr,
    name = session_name,
    confirm_tips = nil,
    modify_history = {},
    processing = true,
    need_confirm = false,
    last_file_content_bufnr = nil,
    last_info_content_bufnr = nil,
    on_started = opts.on_started,
  }
  local linsten_process = function()
    local client = s:get_client()
    client:connect(function(res)
      s:handle_process_status(res)
    end, function(res)
      s:handle_process_chunk_response(res)
    end)
    client:send("process_status", {})
  end
  s.job_id = vim.api.nvim_buf_call(bufnr, function()
    local term_opts = {
      bufnr = bufnr,
      on_stdout = function(job_id, data, event)
        if s.port ~= nil or data == nil then
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
    }
    if cwd then
      term_opts.cwd = cwd
    end
    if on_exit then
      term_opts.on_exit = on_exit
    end
    return vim.fn.termopen(cmd, term_opts)
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
function Session:handle_process_status(res)
  utils.info(res.result)
end

---@param res table
function Session:handle_process_chunk_response(res)
  if res.type == "aider_start" then
    self.processing = false
    utils.info(res.message)
    if self.on_started ~= nil then
      self.on_started()
    end
  elseif res.type == "confirm_ask" then
    utils.warn(res.prompt, "Aider Confirm (" .. self.name .. ")")
    self.confirm_info = res.prompt
    self.need_confirm = true
  elseif res.type == "notify" then
    utils.info(res.message, "Aider Command Message")
  elseif res.type == "cmd_start" then
    self.processing = true
    utils.info(res.message, "Aider Command Message")
  elseif res.type == "cmd_complete" then
    self.processing = false
    self.need_confirm = false
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

---@param message string
function Session:git_commit(message)
  self:send_cmd("/commit " .. message)
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
      self:send_cmd('fix-diagnostics')
    end
  end)
  client:send("fix_diagnostic", diagnostics)
end

return {
  create = create,
}
