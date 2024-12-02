local uv = vim.loop

local Client = {}
local CHUNK_END = "\t\n\t\n"
local END_OF_MESSAGE = "\r\n\r\n"

function Client:connect(response_callback, chunk_response_callback)
  self.last_id = 1
  self.method = ""
  self.params = {}

  if response_callback == nil then
    response_callback = function() end
  end

  if chunk_response_callback == nil then
    chunk_response_callback = function() end
  end

  self.socket = assert(uv.new_tcp())
  self.socket:connect(self.host, self.port, function(err)
    if err then
      return
    end
    local response = ""

    self.socket:read_start(function(err, chunk)
      if err then
        return
      end
      if chunk then
        response = response .. chunk
        if vim.endswith(response, CHUNK_END) then
          local json_obj = vim.json.decode(vim.trim(response))
          vim.schedule(function()
            chunk_response_callback(json_obj, self.method, self.params)
          end)
          response = ""
        elseif vim.endswith(response, END_OF_MESSAGE) then
          response = vim.trim(response)
          local json_obj = vim.json.decode(response)
          vim.schedule(function()
            response_callback(json_obj, self.method, self.params)
          end)
          response = ""
        end
      end
    end)
  end)
end

function Client:send(method, params)
  self.last_id = self.last_id + 1
  local idx = self.last_id
  self.method = method
  self.params = params
  local data = vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params,
    id = idx,
  }) .. "\r\n\r\n"
  self.socket:write(data)
end

function Client:aider_code(params, on_response, on_chunk_response)
  self:connect(on_response, on_chunk_response)
  self:send("processing", params)
end

function Client:close()
  self.socket:shutdown()
  self.socket:close()
end

local function create_client(host, port)
  local client = { host = host, port = port }
  setmetatable(client, { __index = Client })
  return client
end

return {
  create_client = create_client,
}
