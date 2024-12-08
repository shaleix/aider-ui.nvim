# aider-ui.nvim

Aider UI for neovim

> Early development, issues is welcome.

## 🚀 Features

- Multiple Sessions support
- Friendly UI for add / read files
- Simplify multi-line input
- Command for Sync buffer files to aider
- Save / Load session with files

---

## 📦 Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Aider](https://aider.chat/docs/install/install.html) `>= 0.67.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

### Using Lazy.nvim

```lua
return {
  "shaleix/aider-ui.nvim",
  config = function()
    require("aider-ui").setup({
      python_path = "/path/to/python", -- python virtual env path, with aider install
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

defaults that you can override:

```lua
{
  icons = {
    folder = "",
  },

  -- !!! python env python
  python_path = "/usr/bin/python3",

  -- aider start command args
  aider_cmd_args = {
    "--no-check-update",
    "--no-auto-commits",
    "--dark-mode",
  },

  -- aider watch file cmd args, use aider_cmd_args with "--watch-files" if nil
  aider_cmd_args_watch_files = nil,

  -- session save dir path
  session_save_dir = ".aider_sessions",
}
```

### Usage

- `:AiderToggleSplit` toggle aider split and create default session
- `:AiderSyncOpenBuffers` sync open buffers to aider, (/add current buffer file, /read others).
- `:AiderCode` Send /code to aider with input massage

![code_input](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/code_input.png)

- `:AiderViewLastChange` view diff of last chat changes by aider, currently requires [delta](https://github.com/dandavison/delta) to be installed

![preview_change](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/preview_change.png)

- `:AiderNewSession` create new aider session for edit other files

![new_session](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/new_session.png)

## Commands

Session:
| Command | Desc |
| ---------------------------- | ----------------------------------------------- |
| AiderToggleSplit | toggle aider split, create session if no active |
| AiderNewSession | Create Aider Session |
| AiderSessionFinder | Use Telescope to select Aider session |
| AiderSwitchNextSession | Switch next aider session |
| AiderCloseCurrentSession | Close the current Aider session |

File:
| Command | Desc |
| ---------------------------- | ----------------------------------------------- |
| AiderAddCurrentBuffer | Add current buffer to Aider |
| AiderReadCurrentBuffer | Read current buffer into Aider |
| AiderSyncOpenBuffers | Sync open buffers to Aider |
| AiderAddFile | Add files to current Aider session |
| AiderReadFile | Read files into current Aider session |
| AiderReset | Reset and drop files in the current Aider session |

Chat:
| Command | Desc |
| ---------------------------- | ----------------------------------------------- |
| AiderCode | Show Aider /code input |
| AiderArchitect | Show Aider /architect input |
| AiderAsk | Show Aider /ask input |
| AiderCmd | Show Aider command input, maybe easy way to send Y/N to caider |
| AiderInterruptCurrentSession | Interrupt the current Aider session |
| AiderViewLastChange | Preview the last change in Aider |
| AiderLintCurrentBuffer | Lint the current buffer using Aider |

Others:
| Command | Desc |
| ---------------------------- | ----------------------------------------------- |
| AiderGitCommit | Commit changes using Aider |
| AiderSwitchModel | Switch Aider Model |
| AiderHistory | Show Aider Input History |
| AiderClearContext | Clear the context of the current Aider session |
| AiderSaveCurrentSession | Save the current Aider session to file |
| AiderLoadSession | Load a saved Aider session from select file |

## 🔑 Keybindings

no default keybindings


## Status Bar

for NvChad

```lua
-- chadrc.lua
-- example show session info, replace file content
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
      end
    }
  }
}
```

![nvchad_status](https://github.com/shaleix/aider-ui.nvim/blob/main/asset/status_bar.png)

todo: lualine component

