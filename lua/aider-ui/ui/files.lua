local config_module = require("aider-ui.config")
if not config_module then
  error("Failed to load config module: aider-ui.config - " .. debug.traceback())
elseif not config_module.options then
  error("Failed to load config options from aider-ui.config - " .. debug.traceback())
end
local config = config_module.options
local M = {}

local function group_tree_paths(paths)
  local tree = {}
  for _, path in ipairs(paths) do
    local parts = vim.split(path, "/", { plain = true })
    local current_node = tree
    local current_path = ""
    for i, part in ipairs(parts) do
      local found = false
      for _, child in ipairs(current_node) do
        if child.name == part then
          current_node = child.children
          current_path = child.path
          found = true
          break
        end
      end
      if not found then
        local new_node = {
          type = (i == #parts and "file" or "folder"),
          name = part,
          path = current_path .. (current_path == "" and "" or "/") .. part,
        }
        if i < #parts then
          new_node.children = {}
        end
        table.insert(current_node, new_node)
        current_node = new_node.children
        current_path = new_node.path
      end
    end
  end

  local function merge_folders(node, parent_name)
    if node.type == "folder" and #node.children == 1 and node.children[1].type == "folder" then
      node.name = node.name .. "/" .. node.children[1].name
      node.path = node.path .. "/" .. node.children[1].name
      node.children = node.children[1].children
      merge_folders(node, node.name)
    elseif node.type == "folder" and #node.children > 0 then
      for _, child in ipairs(node.children) do
        merge_folders(child, node.name)
      end
    end
  end

  for _, root in ipairs(tree) do
    merge_folders(root, "")
  end

  return tree
end

local function get_node_content(node, indent)
  local NuiLine = require("nui.line")
  local NuiText = require("nui.text")
  if node.type == "folder" then
    return NuiLine({
      NuiText(string.rep("  ", indent)),
      NuiText(config.icons.folder, "AiderFolder"),
      NuiText(" " .. node.name),
    })
  elseif node.type == "file" then
    local icon, hl = require("nvim-web-devicons").get_icon(node.name, nil, { default = true })
    return NuiLine({
      NuiText(string.rep("  ", indent)),
      NuiText(icon or "", hl),
      NuiText(" " .. node.name),
    })
  else
    return NuiLine({
      NuiText(string.rep("  ", indent) .. node.name),
    })
  end
end

local function traverse_tree(node, indent, aider_type)
  local lines = {}
  local lines_path = {}
  for _, child in ipairs(node) do
    table.insert(lines, get_node_content(child, indent))
    table.insert(lines_path, { path = child.path, type = child.type, aider_type = aider_type })
    if child.type == "folder" and child.children then
      local sub_lines, sub_lines_path = traverse_tree(child.children, indent + 1, aider_type)
      vim.list_extend(lines, sub_lines)
      vim.list_extend(lines_path, sub_lines_path)
    end
  end
  return lines, lines_path
end

local function get_file_content(files_data, coder_info)
  local current_cwd = vim.fn.getcwd():gsub("\\", "/")
  local display_cwd = coder_info.cwd:gsub("\\", "/")

  if #display_cwd >= #current_cwd and string.sub(display_cwd, 1, #current_cwd) == current_cwd then
    display_cwd = "." .. string.sub(display_cwd, #current_cwd + 1, #display_cwd)
  end
  local NuiLine = require("nui.line")
  local NuiText = require("nui.text")
  local added, readonly = files_data.added, files_data.readonly

  local coder_info_line = NuiLine({
    NuiText("- Main model: ", "Comment"),
    NuiText(coder_info.main_model, "AiderValue"),
    NuiText(" with ", "Comment"),
    NuiText(coder_info.edit_format, "AiderValue"),
    NuiText(" edit format", "Comment"),
  })

  local cwd_line = NuiLine({
    NuiText("- Cur path: ", "Comment"),
    NuiText(display_cwd, "AiderValue"),
  })

  local lines = { NuiLine(), coder_info_line, cwd_line, NuiLine() }
  local lines_path = { {}, {}, {}, {} }

  local added_count = added and #added or 0
  table.insert(
    lines,
    NuiLine({
      NuiText(" Added Files "),
      NuiText("(" .. added_count .. ")", "AiderComment"),
    })
  )
  table.insert(lines_path, {})
  if added ~= nil and #added > 0 then
    local group_paths = group_tree_paths(added)
    local add_lines, add_lines_path = traverse_tree(group_paths, 1, "add")
    vim.list_extend(lines, add_lines)
    vim.list_extend(lines_path, add_lines_path)
  end

  table.insert(lines, NuiLine())
  table.insert(lines, NuiLine())
  table.insert(lines_path, {})
  table.insert(lines_path, {})

  local readonly_count = readonly and #readonly or 0
  table.insert(
    lines,
    NuiLine({
      NuiText(" Read-only Files "),
      NuiText("(" .. readonly_count .. ")", "AiderComment"),
    })
  )
  table.insert(lines_path, {})
  if readonly ~= nil and #readonly > 0 then
    local group_paths = group_tree_paths(readonly)
    local read_lines, read_lines_path = traverse_tree(group_paths, 1, "read")
    vim.list_extend(lines, read_lines)
    vim.list_extend(lines_path, read_lines_path)
  end
  return lines, lines_path
end

---@class FileBuffer
---@field bufnr integer
---@field session table
---@field lines_node table[]
local FileBuffer = {}

---Create a new FileBuffer instance
---@param bufnr integer Buffer number
---@param session table Aider session
---@return FileBuffer
function M.new_file_buffer(bufnr, session)
  local self = {}
  setmetatable(self, { __index = FileBuffer })
  self.bufnr = bufnr
  self.session = session
  return self
end

function FileBuffer:keybind(popup, layout)
  popup:map("n", "dd", function()
    local line_num = vim.fn.line(".")
    local node = self.lines_node[line_num]
    if node.type == nil then
      return
    end
    self.session:drop_files({ node.path }, function()
      self:update_file_content()
    end)
  end)
  popup:map("n", "c", function()
    local line_num = vim.fn.line(".")
    local node = self.lines_node[line_num]
    if node.type ~= "file" then
      return
    end
    self.session:exchange_files({ node.path }, function()
      self:update_file_content()
    end)
  end)
  popup:map("n", "<CR>", function()
    local line_num = vim.fn.line(".")
    local node = self.lines_node[line_num]
    if node.type == "file" then
      if layout ~= nil then
        layout:unmount()
      else
        popup:unmount()
      end
      vim.cmd.edit(node.path)
    end
  end)
end

function FileBuffer:update_file_content()
  local files_data = nil
  local coder_info_data = nil

  local function update_if_ready()
    if files_data ~= nil and coder_info_data ~= nil then
      local file_lines, lines_node = get_file_content(files_data, coder_info_data)
      for i, line in ipairs(file_lines) do
        line:render(self.bufnr, -1, i)
      end
      vim.api.nvim_buf_set_lines(self.bufnr, #file_lines, -1, false, {})
      self.lines_node = lines_node
      -- Optionally, you can use coder_info_data here if needed
    end
  end

  self.session:list_files(function(res)
    files_data = res
    update_if_ready()
  end)

  self.session:get_coder_info(function(res)
    coder_info_data = res
    update_if_ready()
  end)
end

return M
