" vim-circuit: provider registry
" Maintainer: inknos
" License: GPL-3.0

" ---------------------------------------------------------------------------
" Provider dictionaries
" ---------------------------------------------------------------------------

let s:providers = {}

let s:providers.claude = {
      \ 'command': 'claude',
      \ 'continue': '--continue',
      \ 'resume': '--resume',
      \ 'model_flag': '--model',
      \ 'permission_flag': '--permission-mode',
      \ 'verbose_flag': '--verbose',
      \ 'worktree_flag': '--worktree',
      \ 'tmux_flag': '--tmux',
      \ 'from_pr_flag': '--from-pr',
      \ 'version_flag': '--version',
      \ 'doctor_cmd': 'doctor',
      \ 'stats_cmd': '',
      \ 'session_list_cmd': '',
      \ 'modes': ['plan', 'fast', 'normal'],
      \ 'mode_prefix': '/',
      \ 'models': ['sonnet', 'opus', 'haiku'],
      \ 'plan_dir': '~/.claude/plans',
      \ 'exit_plan_cmd': 'normal',
      \ 'slash_commands': {
      \   'undo': '',
      \   'redo': '',
      \   'export': '',
      \ },
      \ 'env': {},
      \ }

let s:providers.agent = {
      \ 'command': 'agent',
      \ 'continue': '--continue',
      \ 'resume': '--resume',
      \ 'model_flag': '--model',
      \ 'permission_flag': '--mode',
      \ 'verbose_flag': '',
      \ 'worktree_flag': '--worktree',
      \ 'tmux_flag': '',
      \ 'from_pr_flag': '',
      \ 'version_flag': '--version',
      \ 'doctor_cmd': 'about',
      \ 'stats_cmd': '',
      \ 'session_list_cmd': 'ls',
      \ 'modes': ['plan', 'ask'],
      \ 'mode_prefix': '/',
      \ 'models': [],
      \ 'plan_dir': '',
      \ 'exit_plan_cmd': '',
      \ 'slash_commands': {
      \   'undo': '',
      \   'redo': '',
      \   'export': '',
      \ },
      \ 'env': {},
      \ }

let s:providers.gemini = {
      \ 'command': 'gemini',
      \ 'continue': '-r "latest"',
      \ 'resume': '-r',
      \ 'model_flag': '--model',
      \ 'permission_flag': '--approval-mode',
      \ 'verbose_flag': '--debug',
      \ 'worktree_flag': '--worktree',
      \ 'tmux_flag': '',
      \ 'from_pr_flag': '',
      \ 'version_flag': '--version',
      \ 'doctor_cmd': '',
      \ 'stats_cmd': '',
      \ 'session_list_cmd': '--list-sessions',
      \ 'modes': [],
      \ 'mode_prefix': '/',
      \ 'models': ['pro', 'flash', 'flash-lite'],
      \ 'plan_dir': '',
      \ 'exit_plan_cmd': '',
      \ 'slash_commands': {
      \   'undo': '',
      \   'redo': '',
      \   'export': '',
      \ },
      \ 'env': {},
      \ }

let s:providers.opencode = {
      \ 'command': 'opencode',
      \ 'continue': '--continue',
      \ 'resume': '',
      \ 'model_flag': '--model',
      \ 'permission_flag': '',
      \ 'verbose_flag': '',
      \ 'worktree_flag': '',
      \ 'tmux_flag': '',
      \ 'from_pr_flag': '',
      \ 'version_flag': '--version',
      \ 'doctor_cmd': '',
      \ 'stats_cmd': 'stats',
      \ 'session_list_cmd': 'session list',
      \ 'modes': ['plan'],
      \ 'mode_prefix': '/',
      \ 'models': [],
      \ 'plan_dir': '.opencode/plans',
      \ 'exit_plan_cmd': '',
      \ 'slash_commands': {
      \   'undo': '/undo',
      \   'redo': '/redo',
      \   'export': '/export',
      \ },
      \ 'env': {'OPENCODE_EXPERIMENTAL_PLAN_MODE': '1'},
      \ }

" ---------------------------------------------------------------------------
" Public API
" ---------------------------------------------------------------------------

function! circuit#providers#get(name) abort
  if !has_key(s:providers, a:name)
    throw 'vim-circuit: unknown provider "' . a:name . '"'
          \ . '. Valid: ' . join(sort(keys(s:providers)), ', ')
  endif
  return s:providers[a:name]
endfunction

function! circuit#providers#list() abort
  return keys(s:providers)
endfunction

function! circuit#providers#current() abort
  let l:name = get(g:, 'circuit_provider', '')
  if empty(l:name)
    return {}
  endif
  return circuit#providers#get(l:name)
endfunction

function! circuit#providers#configured() abort
  return !empty(get(g:, 'circuit_provider', ''))
endfunction
