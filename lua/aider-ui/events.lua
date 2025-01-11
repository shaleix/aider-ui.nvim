local Event = {
  __handlers = {},
}

function Event:new(opt)
  local o = {
    __handlers = {},
  }
  if opt ~= nil and opt.throttle_time ~= nil then
    o.throttle_time = opt.throttle_time
  else
    o.throttle_time = 0
  end
  setmetatable(o, { __index = Event })
  return o
end

function Event:add_handler(callback, name)
  table.insert(self.__handlers, { callback = callback, name = name })
end

function Event:emit(data)
  if self.throttle_time > 0 then
    if not self.last_emit_time then
      self.last_emit_time = 0
    end

    local current_time = vim.loop.now()
    if current_time - self.last_emit_time < self.throttle_time then
      return
    end

    self.last_emit_time = current_time
  end

  for _, item in ipairs(self.__handlers) do
    pcall(item.callback, data)
  end
end

return {
  SessionStarted = Event:new(),
  ChatStart = Event:new(),
  ChatCompleted = Event:new(),
  GetOutput = Event:new({ throttle_time = 100 }),
}
