# aider-ui.nvim

A Neovim UI plugin for Aider

> Early development stage - issues and feedback are welcome!

## 🚀 Features

- Multiple session support
- Intuitive UI for adding/reading files
- Simplified multi-line input
- Sync buffer files to Aider
- Fix diagnostics directly from Neovim
- Save/Load sessions with associated files

---

## 📦 Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Aider](https://aider.chat/docs/install.html) `>= 0.67.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) plugin manager
- [delta](https://github.com/dandavison/delta) & [baleia.nvim](https://github.com/m00qek/baleia.nvim) for diff view

### Using Lazy.nvim

```lua
return {
  "shaleix/aider-ui.nvim",
  dependencies = {
    "m00qek/baleia.nvim",
  },
  config = function()
    require("aider-ui").setup({
      python_path = "/path/to/python", -- Path to Python virtual environment with Aider installed
      -- -- aider command start arguments
      -- aider_cmd_args = {
      --   "--deepseek",
      --   "--no-check-update",
      --   "--no-auto-commits",
      --   "--dark-mode",
      -- }
    })
  end,
}
```

### Default Configuration

Default settings (can be overridden):

```lua
{
  icons = {
    folder = "",
  },

  -- Path to Python executable (must have Aider installed)
  python_path = "/usr/bin/python3",

  -- aider start command args or function return args
  aider_cmd_args = {
    "--no-check-update",
    "--no-auto-commits",
    "--dark-mode",
  },

  -- session save dir path
  session_save_dir = ".aider_sessions",
}
```

### Usage

- `:AiderToggleSplit` toggle aider split and create default session
- `:AiderSyncOpenBuffers` - Sync open buffers to Aider (add current buffer file, read others)
- `:AiderCode` - Send `/code` command to Aider with input message

![code_input](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/code_input.png)

- `:AiderViewLastChange` - View diff of last chat changes (requires [delta](https://github.com/dandavison/delta))

![preview_change](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/preview_change.png)

- `:AiderDiagnosticBuffer` - Fix diagnostics by sending to Aider

![diagnostics](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/diagnostics.png)

- `:AiderNewSession` - Create new Aider session for editing other files

![new_session](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/new_session.png)

## Commands

### Session Management

| Command                  | Description                                         |
| ------------------------ | --------------------------------------------------- |
| AiderToggleSplit         | Toggle Aider split (creates session if none active) |
| AiderNewSession          | Create new Aider session                            |
| AiderSessionFinder       | Select Aider session using Telescope                |
| AiderSwitchNextSession   | Switch to next Aider session                        |
| AiderCloseCurrentSession | Close current Aider session                         |

### File Operations

| Command                | Description                                   |
| ---------------------- | --------------------------------------------- |
| AiderAddCurrentBuffer  | Add current buffer to Aider                   |
| AiderReadCurrentBuffer | Read current buffer into Aider                |
| AiderSyncOpenBuffers   | Sync open buffers to Aider                    |
| AiderAddFile           | Add files to current Aider session            |
| AiderReadFile          | Read files into current Aider session         |
| AiderReset             | Reset and drop files in current Aider session |

### Chat Operations

| Command                      | Description                                               |
| ---------------------------- | --------------------------------------------------------- |
| AiderCode                    | Show Aider /code input                                    |
| AiderArchitect               | Show Aider /architect input                               |
| AiderAsk                     | Show Aider /ask input                                     |
| AiderCmd                     | Show Aider command input (easy way to send Y/N responses) |
| AiderInterruptCurrentSession | Interrupt current Aider session                           |
| AiderViewLastChange          | Preview last change in Aider                              |
| AiderLintCurrentBuffer       | Lint current buffer using Aider                           |

### Diagnostics

| Command               | Description                                |
| --------------------- | ------------------------------------------ |
| AiderDiagnosticBuffer | Send current buffer's diagnostics to Aider |
| AiderDiagnosticLine   | Send current line's diagnostics to Aider   |

### Other Commands

| Command                 | Description                            |
| ----------------------- | -------------------------------------- |
| AiderGitCommit          | Commit changes using Aider             |
| AiderSwitchModel        | Switch Aider model                     |
| AiderHistory            | Show Aider input history               |
| AiderClearContext       | Clear context of current Aider session |
| AiderSaveCurrentSession | Save current Aider session to file     |
| AiderLoadSession        | Load saved Aider session from file     |

## 🔑 Keybindings

No default keybindings are provided

## Status Bar Integration

Example integration with NvChad:

```lua
-- chadrc.lua
-- Example showing session info (replace file content)
M.ui = {
  statusline = {
    modules = {
      file = function()
        local session_status = require("aider-ui").session_status()
        local session_info = ""
        for _, status in ipairs(session_status) do
          local indicator
          if status.need_confirm then
            indicator = "%#AiderConfirmIndicator#" .. " " .. "%*"
          elseif status.processing then
            indicator = "%#AiderProcessingIndicator#" .. " " .. "%*"
          else
            indicator = ""
          end
          local hi_name = status.is_current and "%#AiderCurrentSession#" .. status.name .. "%*" or status.name
          local name_with_indicator = indicator .. hi_name
          local session_name = status.is_current and "[" .. name_with_indicator .. "]" or name_with_indicator
          session_info = session_info .. session_name .. " "
        end
        return "%#StText# " .. session_info
      end,
    },
  },
}
```

![nvchad_status](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/status_bar.png)

todo: lualine component
