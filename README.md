# vim-circuit

OpenCode terminal integration for Vim. One keypress opens your agent in a split.
Another hides it. Your session persists across toggles.

Powered by [OpenCode](https://github.com/opencode-ai/opencode).

> **vim-circuit does not handle authentication or API keys.**
> OpenCode must already be installed, authenticated, and working on its own
> before you use it through this plugin. If `opencode` doesn't work when you
> run it directly in a terminal, it won't work here either. Refer to the
> OpenCode documentation for setup instructions.

## Features

- **Persistent terminal** with automatic session resume via `--continue`
- **Session management**: resume, continue, new — all tab-completable
- **Plan mode**: enter plan mode, review plans in a Vim buffer, execute
- **Model switching**: restart with a different model via `:CTmodel`
- **Send selection**: pipe visual selection to OpenCode with file context
- **File references**: stage `file:line` refs and send them to the TUI
- **Auto buffer reload**: detects files changed by the agent and reloads them
- **Server API**: managed `opencode serve` for reliable prompt delivery
- **Undo / Redo / Export**: send slash commands to the running session
- **Command palette**: floating popup for quick access to all commands
- **Lifecycle hooks**: `User CTOpen`, `CTReload`, etc.
- **Fully configurable**: every keymap, behavior, and CLI flag via `g:circuit_*`

## Requirements

- Vim 8.0+ with `+terminal`
- [OpenCode](https://github.com/opencode-ai/opencode) installed and in `$PATH`
- The CLI must be authenticated and functional — run it standalone first
- Git

## Installation

### vim-plug

```vim
Plug 'inknos/vim-circuit'
```

### Native packages

```bash
git clone https://github.com/inknos/vim-circuit.git \
  ~/.vim/pack/plugins/start/vim-circuit
```

Then run `:helptags ALL` in Vim.

## Quick Start

```vim
:CTerm              " Toggle OpenCode terminal (or <leader>c)
:CTerm resume       " Session list
:CTerm model {name} " Switch model
:CTerm plan         " Enter plan mode
```

If you need to override the CLI binary path:

```vim
let g:circuit_command = '/usr/local/bin/opencode'
```

## Commands

| Long Form | Short | Description |
|---|---|---|
| `:CTerm` | `:CT` | Toggle terminal |
| `:CTerm resume` | `:CTresume` | Session list |
| `:CTerm continue` | `:CTcontinue` | Resume last chat |
| `:CTerm new` | `:CTnew` | New session |
| `:CTerm kill` | `:CTkill` | Kill terminal |
| `:CTerm plan` | `:CTplan` | Enter plan mode |
| `:CTerm send` | `:CTsend` | Send selection |
| `:CTerm chat` | `:CTchat` | Free-form chat |
| `:CTerm model {name}` | `:CTmodel {name}` | Switch model |
| `:CTerm undo` | `:CTundo` | Send `/undo` |
| `:CTerm redo` | `:CTredo` | Send `/redo` |
| `:CTerm export` | `:CTexport` | Send `/export` |
| `:CTerm stats` | `:CTstats` | Show stats |
| `:CTerm sessions` | `:CTsessions` | Session list |
| `:CTerm version` | `:CTversion` | Show versions |
| `:CTerm prompt` | `:CTprompt` | Command palette |

## Configuration

Set any of these in your `.vimrc` before the plugin loads:

```vim
" General
let g:circuit_position = 'bottom'       " right (default), left, top, bottom
let g:circuit_split_ratio = 0.3         " fraction of screen (default 0.4)
let g:circuit_model = ''                " default model
let g:circuit_map_keys = 0              " disable all default keymaps
```

See `:help circuit-configuration` for the full list.

## Hooks

```vim
autocmd User CTOpen echo "OpenCode session started"
autocmd User CTReload echohl WarningMsg | echo "Buffers reloaded" | echohl None
```

Events: `Open`, `ToggleShow`, `ToggleHide`, `Kill`, `Reload`, `ModeChange`,
`SessionChange`, `Undo`, `Redo`, `Export`, `SessionList`.

See `:help circuit-hooks` for details.

## Documentation

Full documentation is available via `:help circuit` after installation.

HTML docs are generated from the vimdoc source and are available
[here](https://inknos.github.io/vim-circuit). User-facing help lives in
`doc/circuit.txt` (Vim help format), not in this file.

## Development

This repository is a normal Vim plugin layout; **running the test suite
requires the [Vader.vim](https://github.com/junegunn/vader.vim) submodule** at
`test/vader.vim` (a gitlink, not a copy of the files in the parent tree).

Clone with submodules so `test/vader.vim` is checked out:

```bash
git clone --recurse-submodules https://github.com/inknos/vim-circuit.git
# or, if you already cloned without submodules:
cd vim-circuit && git submodule update --init
```

Run tests (needs Vim with `+terminal`):

```bash
make test     # all test/*.vader, headless Vim
make check    # lint (vint) + test — install: pip install vim-vint
```

| Path | Role |
|------|------|
| `test/vimrc` | Minimal config: plugin + Vader only |
| `test/*.vader` | Test files (see `AGENTS.md` for naming and how to add cases) |

## License

GPL-3.0
