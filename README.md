# vim-circuit

Agent CLI terminal integration for Vim. One keypress opens your agent in a split.
Another hides it. Your session persists across toggles.

Works with any supported agent CLI — not tied to a single vendor.

## Supported Providers

| Provider | CLI binary | Project |
|---|---|---|
| **OpenCode** (recommended) | `opencode` | [opencode-ai/opencode](https://github.com/opencode-ai/opencode) |
| Claude Code | `claude` | [anthropics/claude-code](https://github.com/anthropics/claude-code) |
| Cursor Agent | `agent` | [getcursor/cursor](https://www.cursor.com/) |
| Gemini CLI | `gemini` | [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |

> **vim-circuit does not handle authentication or API keys.**
> Each CLI must already be installed, authenticated, and working on its own
> before you use it through this plugin. If `opencode` (or whichever CLI you
> choose) doesn't work when you run it directly in a terminal, it won't work
> here either. Refer to each project's documentation for setup instructions.

## Features

- **Multi-provider**: switch between agent CLIs with a single config variable
- **Persistent terminal** with automatic session resume via `--continue`
- **Session switching**: resume, continue, new, from-PR — all tab-completable
- **Worktree support**: `--worktree` integration with optional tmux mode
- **Mode control**: plan, fast, and other interactive modes (provider-dependent)
- **Model switching**: use model aliases or full model names (provider-dependent)
- **Zoom toggle**: maximize/restore the agent split (tmux-style)
- **Send selection**: pipe visual selection to the agent with file context
- **Auto buffer reload**: detects files changed by the agent and reloads them
- **Lifecycle hooks**: `User CTOpen`, `CTReload`, etc.
- **Fully configurable**: every keymap, behavior, and CLI flag via `g:circuit_*`

Not every feature is available for every provider. The plugin warns you
when you try to use a feature that your provider doesn't support.

## Requirements

- Vim 8.0+ with `+terminal`
- A supported agent CLI installed and in `$PATH` (see [Supported Providers](#supported-providers))
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

## Provider Setup

**You must set `g:circuit_provider`** in your `.vimrc` to tell vim-circuit
which CLI to use. There is no auto-detection.

```vim
" Required — pick your provider
let g:circuit_provider = 'opencode'
```

Valid values: `'opencode'`, `'claude'`, `'gemini'`, `'agent'`.

If you need to override the CLI binary name or path (e.g. you renamed
the binary or it's not on `$PATH`), set `g:circuit_command`:

```vim
let g:circuit_provider = 'opencode'
let g:circuit_command = '/usr/local/bin/opencode'
```

When `g:circuit_command` is not set, the plugin uses the provider's
default binary name.

### Provider feature matrix

Not all CLIs support the same features. Here's what works where:

| Feature | Claude | Cursor Agent | Gemini | OpenCode |
|---|:---:|:---:|:---:|:---:|
| Continue session | ✓ | ✓ | ✓ | ✓ |
| Resume (picker) | ✓ | ✓ | ✓ | ✓ |
| Model switching | ✓ | ✓ | ✓ | ✓ |
| Permission/approval mode | ✓ | ✓ | ✓ | — |
| Verbose/debug | ✓ | — | ✓ | — |
| Worktree | ✓ | ✓ | ✓ | — |
| From PR | ✓ | — | — | — |
| Interactive modes | ✓ | ✓ | — | — |
| Health check | ✓ | ✓ | — | — |

## Quick Start

```vim
" Set your provider first
let g:circuit_provider = 'opencode'

:CTerm              " Toggle agent terminal (or <leader>c)
:CTerm resume       " Interactive session picker (or <leader>cr)
:CTerm model {name} " Switch model (or <leader>cm)
:CTerm worktree     " Launch in a git worktree (or <leader>cw)
:CTworktree!        " Launch worktree in tmux pane
```

## Commands

| Long Form | Short | Keymap | Description |
|---|---|---|---|
| `:CTerm` | `:CT` | `<leader>c` | Toggle terminal |
| `:CTerm resume` | `:CTresume` | `<leader>cr` | Session picker |
| `:CTerm continue` | `:CTcontinue` | `<leader>cc` | Resume last chat |
| `:CTerm new` | `:CTnew` | `<leader>cn` | New session |
| `:CTerm kill` | `:CTkill` | `<leader>ck` | Kill terminal |
| `:CTerm pr` | `:CTpr` | `<leader>cp` | Resume from PR (Claude only) |
| `:CTerm worktree` | `:CTworktree` | `<leader>cw` | Launch in git worktree |
| `:CTerm plan` | `:CTplan` | `<leader>cmp` | Toggle plan mode (provider-dependent) |
| `:CTerm fast` | `:CTfast` | `<leader>cmf` | Toggle fast mode (provider-dependent) |
| `:CTerm send` | `:CTsend` | `<leader>cs` (visual) | Send selection |
| `:CTerm chat` | `:CTchat` | `<leader>ch` | Free-form chat |
| `:CTerm model {name}` | `:CTmodel {name}` | — | Switch model |
| `:CTerm verbose` | `:CTverbose` | `<leader>cv` | Verbose toggle (provider-dependent) |
| `:CTerm doctor` | `:CTdoctor` | -- | Health check |
| `:CTerm version` | `:CTversion` | -- | Show versions |

## Configuration

Set any of these in your `.vimrc` before the plugin loads:

```vim
" Provider (required)
let g:circuit_provider = 'opencode'

" General
let g:circuit_position = 'bottom'       " right (default), left, top, bottom
let g:circuit_split_ratio = 0.3         " fraction of screen (default 0.4)
let g:circuit_permission_mode = 'plan'  " default mode for new sessions
let g:circuit_model = ''                " default model (provider-dependent)
let g:circuit_worktree_tmux = 1         " always use tmux for worktree
let g:circuit_map_keys = 0              " disable all default keymaps
```

See `:help circuit-configuration` for the full list.

## Hooks

```vim
autocmd User CTOpen echo "Agent session started"
autocmd User CTReload echohl WarningMsg | echo "Buffers reloaded" | echohl None
```

Events: `Open`, `ToggleShow`, `ToggleHide`, `Kill`, `Reload`, `ModeChange`,
`SessionChange`, `Worktree`.

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
