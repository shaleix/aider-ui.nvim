# aider-ui.nvim

Aider UI for neovim

> Early development, issue is welcome.

## 🚀 Features

- Multiple Sessions support
- Friendly UI for add / read files
- Simplify multi-line input
- Sync buffer files to aider

---

## 📦 Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Aider](https://aider.chat/docs/install/install.html) `>= 0.64.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

### Using Lazy.nvim

```lua
return {
  "shaleix/aider-ui.nvim",
  config = function()
    require("aider-ui").setup({
      python_path = "/path/to/python", -- python virtual env`` path, with aider install
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

  -- session save dir path
  session_save_dir = ".aider_sessions",
}
```

### Usage

`:AiderToggleSplit` toggle aider split and create default session


## Commands

| Command                      | Desc                                            |
| ---------------------------- | ----------------------------------------------- |
| AiderToggleSplit             | toggle aider split, create session if no active |
| AiderAddCurrentBuffer        | Add current buffer to Aider                     |
| AiderReadCurrentBuffer       | Read current buffer into Aider                  |
| AiderHistory                 | Show Aider Input History                        |
| AiderSwitchModel             | Switch Aider Model                              |
| AiderInterruptCurrentSession | Interrupt the current Aider session             |
| AiderGitCommit               | Commit changes using Aider                      |
| AiderShowSessionInfo         | Show Aider session info                         |
| AiderShowFiles               | Show Aider files                                |
| AiderCode                    | Show Aider /code input                          |
| AiderArchitect               | Show Aider /architect input                     |
| AiderAsk                     | Show Aider /ask input                           |
| AiderSyncOpenBuffers         | Sync open buffers with Aider                    |
| AiderAddFile                 | Add files to current Aider session              |
| AiderReadFile                | Read files into current Aider session           |
| AiderNewSession              | Create Aider Session                            |
| AiderSessionFinder           | Use Telescope to select Aider session           |
| AiderSwitchNextSession       | Switch next aider session                       |
| AiderPreviewLastChange       | Preview the last change in Aider                |
| AiderLintCurrentBuffer       | Lint the current buffer using Aider             |
| AiderCmd                     | Show Aider command input                        |

## 🔑 Keybindings

no default keybindings
