" vim-circuit: provider registry
" Maintainer: inknos
" License: GPL-3.0

" ---------------------------------------------------------------------------
" Provider dictionaries
" ---------------------------------------------------------------------------

let s:providers = {}

let s:providers.opencode = {
      \ 'command': 'opencode',
      \ 'continue': '--continue',
      \ 'model_flag': '--model',
      \ 'version_flag': '--version',
      \ 'stats_cmd': 'stats',
      \ 'session_list_cmd': 'session list',
      \ 'modes': ['plan'],
      \ 'mode_prefix': '/',
      \ 'models': [],
      \ 'plan_dir': '.opencode/plans',
      \ 'slash_commands': {
      \   'undo': '/undo',
      \   'redo': '/redo',
      \   'export': '/export',
      \ },
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
