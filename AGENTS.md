# AGENTS.md — vim-circuit

## Overview

A Vim plugin that embeds OpenCode in Vim's built-in `:terminal`.
Single persistent terminal per project, toggle show/hide without losing
session state, commands and keymaps for session control, mode switching,
model selection, and more.

**Language:** Vimscript only. No Python, Lua, Node, or external build tools.

**Runtime requirements:** Vim 8.0+ with `+terminal`, `opencode` on `$PATH`, Git.

## Architecture

```
plugin/circuit.vim                ← loaded once at startup
  • g:loaded_circuit guard, +terminal feature check
  • g:circuit_* config defaults (get(g:, ...) pattern)
  • g:circuit_provider — must be 'opencode' (only supported backend)
  • :CTerm dispatcher + short command aliases
  • keymap registration (guarded by g:circuit_map_keys)
  • FocusGained/BufEnter autocommand for checktime

autoload/circuit.vim              ← lazy-loaded on first circuit# call
  • s: script-local state (term_bufnr, timer, mode, model)
  • s: helpers (get, git_root, build_cmd, open_split, provider, ...)
  • circuit# public functions (toggle, resume, continue, new, ...)
  • reads flags from circuit#providers#current()
  • tab-completion via circuit#complete()

autoload/circuit/providers.vim    ← provider registry
  • s:providers dict — opencode backend definition
  • circuit#providers#get(name) — returns the provider dict
  • circuit#providers#list() — returns provider names
  • circuit#providers#current() — returns the active provider dict

autoload/circuit/hooks.vim        ← thin hook dispatcher
  • circuit#hooks#fire(event) → doautocmd User CT{Event}

doc/circuit.txt                   ← vimdoc (generates HTML via CI)
  • full user documentation, 78-char width, vim help format

test/                             ← Vader test suite
  • test/vimrc — minimal runtime (loads plugin + Vader only)
  • test/*.vader — test files (providers, completion, features, etc.)
```

## Vimscript Conventions

### Functions

- Always `function! Name() abort` — `!` allows redefinition, `abort` fails
  fast on errors.
- Public API: `circuit#function_name()` — autoloaded.
- Private helpers: `s:function_name()` — script-local.
- Hooks submodule: `circuit#hooks#fire()`.

### Configuration variables

- Global: `g:circuit_*`, initialized with `get(g:, 'circuit_X', default)`.
- Buffer-local overrides: `b:circuit_*` take precedence (via `s:get()`).

### String comparisons

Use `==#` and `!=#` for case-sensitive compares. Never bare `==`.

### File headers

Every `.vim` file starts with:

```vim
" vim-circuit: <brief purpose>
" Maintainer: inknos
" License: GPL-3.0
```

### Section separators

```vim
" ---------------------------------------------------------------------------
" Section Name
" ---------------------------------------------------------------------------
```

### Formatting

- Two-space indentation, no tabs.
- Use `\` for line continuations.
- Use `l:` prefix for local variables inside functions.

## Vimdoc Conventions

File: `doc/circuit.txt`. Format: Vim help (`:help write-local-help`).

- Tags: `*circuit-name*` — lowercase, hyphen-separated.
- Command tags: `*:CTcommandname*`
- Config variable tags: `*g:circuit_variable*`
- Text width: 78 characters.
- Section separators: `=====` lines. Subsection separators: `-----` lines.
- `doc/tags` is gitignored — never commit it.

When editing source files, verify that any new or changed commands, keymaps,
config variables, or hooks are reflected in `doc/circuit.txt`.

## Adding a :CTerm Subcommand

Every subcommand touches four files. Work through them in order.

### 1. Implement the function (`autoload/circuit.vim`)

Add a public `circuit#yourcommand()` function in the appropriate section.
Use `s:` helpers for internal logic and `s:get()` to read config variables.

```vim
" ---------------------------------------------------------------------------
" Your Feature
" ---------------------------------------------------------------------------

function! circuit#yourcommand() abort
  if !s:term_alive()
    echo 'vim-circuit: no active terminal'
    return
  endif
  " ... implementation ...
  call circuit#hooks#fire('YourEvent')
endfunction
```

### 2. Wire up the dispatcher (`plugin/circuit.vim`)

Add an `elseif` branch in `s:dispatch()`:

```vim
elseif l:cmd ==# 'yourcommand'
  call circuit#yourcommand()
```

For subcommands with arguments, guard with `a:0 >= 2`:

```vim
elseif l:cmd ==# 'yourcommand'
  if a:0 >= 2
    call circuit#yourcommand(a:2)
  else
    echoerr 'vim-circuit: yourcommand requires an argument'
  endif
```

### 3. Register short alias and keymap (`plugin/circuit.vim`)

```vim
" Short alias
command! -nargs=0 CTyourcommand call circuit#yourcommand()

" Config variable (in "Configuration defaults" section)
let g:circuit_map_yourcommand = get(g:, 'circuit_map_yourcommand', '<leader>cy')

" Keymap (inside the `if g:circuit_map_keys` block)
execute 'nnoremap <silent> ' . g:circuit_map_yourcommand . ' :call circuit#yourcommand()<CR>'
```

### 4. Add tab-completion (`autoload/circuit.vim`)

Add `'yourcommand'` to the `l:subs` list in `circuit#complete()`. If the
subcommand takes sub-arguments, add a new `elseif l:sub ==# 'yourcommand'`
block.

### 5. Document (`doc/circuit.txt`)

- Add the command under the appropriate subsection in section 5 (Commands)
  with tag `*:CTyourcommand*`.
- Add the keymap to the table in section 6 (Keymaps).
- Add any new `g:circuit_*` variable to section 9 (Configuration).
- Add any new hook event to section 8 (Hooks).
- Update the TOC if you added a new subsection.

### Existing patterns to reference

| Feature | Function | Dispatcher | Alias | Keymap var |
|---|---|---|---|---|
| Toggle | `circuit#toggle()` | (default) | `:CT` | `g:circuit_map_toggle` |
| Resume | `circuit#resume()` | `resume` | `:CTresume` | `g:circuit_map_resume` |
| Model | `circuit#set_model()` | `model` | `:CTmodel` | — |
| Undo | `circuit#undo()` | `undo` | `:CTundo` | `g:circuit_map_undo` |
| Sessions | `circuit#sessions()` | `sessions` | `:CTsessions` | `g:circuit_map_sessions` |
| Stage file:line ref | `circuit#stage_ref()` | `ref` (also `:CTref` w/ range) | `:CTref` / `:CTaddtochat` | `g:circuit_map_stage_ref` |
| Send staged ref | `circuit#send_staged_ref()` | `refsend` | `:CTrefsend` | terminal `<C-l>` (if `g:circuit_tmap_c_l_sends_staged`) |

## Testing

**Clone, submodule, and `make test` / `make check`:** see the
**[Development](README.md#development)** section in the project `README.md`
(never duplicate that in `doc/circuit.txt` — that file is for end users).

The test driver is [Vader.vim](https://github.com/junegunn/vader.vim) as a
submodule at `test/vader.vim`.

### Test structure

- `test/vimrc` — minimal vimrc that loads only the plugin and Vader.
- `test/providers.vader` — unit tests for `circuit#providers#*` functions.
- `test/completion.vader` — tab-completion behavior.
- `test/features.vader` — feature tests (undo, redo, export, refs, plan, etc.).

### Writing tests

- Test public `circuit#` functions, not `s:` script-local functions.
- Use `redir => output` / `redir END` to capture `echo` output for assertion.
- Naming convention: `test/{module}.vader`.

## Linting

Static analysis uses [vint](https://github.com/Vimjas/vint).

```bash
make lint      # runs vint on autoload/ and plugin/
pip install vim-vint   # install vint
```

Configuration lives in `.vintrc.yaml`. Fix all warnings before committing.

## Constraints

- **No external dependencies.** Pure Vim plugin — no npm, pip, cargo.
- **No Neovim-only APIs.** Must work on Vim 8.0+ with `+terminal`.
- **No generated files.** Don't commit `doc/tags` or `build/`.
- **No unnecessary comments.** Comments explain *why*, not *what*.
- **Run `make check` before committing.** Lint + tests must pass.
