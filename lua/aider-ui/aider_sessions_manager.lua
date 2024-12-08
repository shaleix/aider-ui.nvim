local aider_session = require("aider-ui.aider_session")
local events = require("aider-ui.events")
local utils = require("aider-ui.utils")

local M = {
  current_job_id = nil,
  sessions = {},
}

M.get_current_session_name = function()
  if M.current_job_id == nil then
    return nil
  end

  for _, session in ipairs(M.sessions) do
    if session.job_id == M.current_job_id then
      return session.name
    end
  end

  return nil
end

M.validate_new_session_name = function(name)
  for _, session in ipairs(M.sessions) do
    if session.name == name then
      return false
    end
  end
  return true
end

function M.current_session()
  if M.current_job_id == nil then
    return nil
  end

  for _, session in ipairs(M.sessions) do
    if session.job_id == M.current_job_id then
      return session
    end
  end
  return nil
end

function M.create_session(new_session_name, on_started, cwd, watch_files)
  if new_session_name == nil then
    new_session_name = "default"
  end
  local bufnr = vim.api.nvim_create_buf(false, false)
  local current_session = aider_session.create(new_session_name, bufnr, {
    on_started = on_started,
    cwd = cwd,
    watch_files = watch_files,
    on_exit = function()
      M.delete_session(new_session_name)
    end,
  })
  table.insert(M.sessions, current_session)
  M.current_job_id = current_session.job_id
  return current_session
end

local function on_session_deleted()
  local ui = require("aider-ui.ui.side_split")
  if ui.is_split_visible() then
    ui.aider_hide()
  end
end

local function on_session_changed()
  local ui = require("aider-ui.ui.side_split")
  if #M.sessions == 0 then
    -- create new session
    return ui.show_aider_split()
  end
  if ui.is_split_visible() then
    return ui.show_aider_split()
  end
end

function M.next_session()
  local current_index = nil
  for i, session in ipairs(M.sessions) do
    if session.job_id == M.current_job_id then
      current_index = i
      break
    end
  end

  if current_index == nil then
    utils.err("No active session found.")
    return
  end

  local next_index = (current_index % #M.sessions) + 1
  local next_session = M.sessions[next_index]

  if next_session then
    M.current_job_id = next_session.job_id
    on_session_changed()
  else
    utils.err("No more sessions to switch to.")
  end
end

function M.switch_session_by_name(name)
  for _, session in ipairs(M.sessions) do
    if session.name == name then
      M.current_job_id = session.job_id
      on_session_changed()
      vim.api.nvim_exec_autocmds("User", { pattern = events.AiderSessionChanged })
      return
    end
  end
  utils.err("Session named " .. name .. " not found.")
end

M.sync_open_buffers = function()
  local current_session = M.current_session()
  if current_session == nil then
    current_session = on_session_changed()
  end
  if current_session ~= nil then
    current_session:sync_open_buffers()
  end
end

function M.delete_session(session_name)
  local delete_session = nil
  for i, session in ipairs(M.sessions) do
    if session.name == session_name then
      session:exit()
      delete_session = session
      table.remove(M.sessions, i)
      break
    end
  end
  if delete_session == nil then
    return
  end
  if M.current_job_id == delete_session.job_id then
    if #M.sessions > 0 then
      M.current_job_id = M.sessions[1].job_id
    else
      M.current_job_id = nil
    end
  end
  on_session_deleted()
end

function M.close_session()
  M.current_session():exit()

  for i, session in ipairs(M.sessions) do
    if session.job_id == M.current_job_id then
      table.remove(M.sessions, i)
      break
    end
  end

  if #M.sessions == 0 then
    M.current_job_id = nil
  else
    local next_session = M.sessions[1]
    M.current_job_id = next_session.job_id
  end
  on_session_changed()
end

function M.list_session_status()
  local status_list = {}
  for _, session in ipairs(M.sessions) do
    table.insert(status_list, {
      name = session.name,
      processing = session.processing,
      is_current = (session.job_id == M.current_job_id),
      need_confirm = session.need_confirm,
    })
  end
  return status_list
end

function M.save_session(file_path)
  local session = M.current_session()
  if session == nil then
    utils.err("No active session found.")
    return
  end
  session:save(file_path)
end

function M.get_current_bufnr()
  local bufnr
  for _, session in ipairs(M.sessions) do
    if session.job_id == M.current_job_id then
      bufnr = session.bufnr
      break
    end
  end
  return bufnr
end

function M.is_empty()
  return #M.sessions == 0
end

function M.add_files(file_paths)
  local current_session = M.current_session()
  if current_session == nil then
    M.create_session(nil, function()
      local session = M.current_session()
      if session ~= nil then
        session:add_files(file_paths)
      end
    end)
  else
    current_session:add_files(file_paths)
  end
end

M.read_files = function(file_paths)
  local current_session = M.current_session()
  if current_session == nil then
    M.create_session(nil, function()
      local session = M.current_session()
      if session ~= nil then
        session:sync_open_buffers()
      end
    end)
  else
    current_session:read_files(file_paths)
  end
end

return M
