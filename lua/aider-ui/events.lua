local Event = {
  __handlers = {},
}

function Event:new()
  local o = {
    __handlers = {},
  }
  setmetatable(o, { __index = Event })
  return o
end

function Event:add_handler(callback, name)
  table.insert(self.__handlers, { callback = callback, name = name })
end

function Event:emit(data)
  for _, item in ipairs(self.__handlers) do
    pcall(item.callback, data)
  end
end

return {
  SessionStarted = Event:new(),
  ChatStart = Event:new(),
  ChatCompleted = Event:new(),
}
