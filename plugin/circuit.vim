" vim-circuit: commands, keymaps, and configuration
" Maintainer: inknos
" License: GPL-3.0

if exists('g:loaded_circuit')
  finish
endif
let g:loaded_circuit = 1

if !has('terminal')
  echoerr 'vim-circuit requires Vim compiled with +terminal'
  finish
endif

" ---------------------------------------------------------------------------
" Configuration defaults
" ---------------------------------------------------------------------------

let g:circuit_provider         = get(g:, 'circuit_provider', 'opencode')
let g:circuit_command          = get(g:, 'circuit_command', '')
let g:circuit_position         = get(g:, 'circuit_position', 'right')
let g:circuit_split_ratio      = get(g:, 'circuit_split_ratio', 0.5)
let g:circuit_enter_insert     = get(g:, 'circuit_enter_insert', 1)
let g:circuit_use_git_root     = get(g:, 'circuit_use_git_root', 1)
let g:circuit_model            = get(g:, 'circuit_model', '')
let g:circuit_extra_args       = get(g:, 'circuit_extra_args', '')

let g:circuit_plan_close_on_exec    = get(g:, 'circuit_plan_close_on_exec', 1)
let g:circuit_plan_filename_format  = get(g:, 'circuit_plan_filename_format', '%Y-%m-%d-%H%M')
let g:circuit_plan_mode             = get(g:, 'circuit_plan_mode', 0)

let g:circuit_start_on         = get(g:, 'circuit_start_on', 1)
let g:circuit_show_on          = get(g:, 'circuit_show_on', 1)

let g:circuit_auto_reload      = get(g:, 'circuit_auto_reload', 1)
let g:circuit_reload_interval  = get(g:, 'circuit_reload_interval', 1000)
let g:circuit_notify_reload    = get(g:, 'circuit_notify_reload', 1)

let g:circuit_hide_numbers     = get(g:, 'circuit_hide_numbers', 1)
let g:circuit_hide_signcolumn  = get(g:, 'circuit_hide_signcolumn', 1)

let g:circuit_map_keys         = get(g:, 'circuit_map_keys', 1)
" When 1, tnoremap <C-h> to window left (conflicts with Ctrl+Backspace in
" many CLIs, which also sends ^H). Default 0: use <M-h> for left instead.
let g:circuit_tmap_ch_left     = get(g:, 'circuit_tmap_ch_left', 0)
" In |terminal| mode, |<C-l>|: when a file ref is staged (see |:CTref|),
" send it to the TUI; otherwise |<C-w>|l. Set to `0` to always use
" |<C-w>|l and send via |:CTrefsend| only.
let g:circuit_tmap_c_l_sends_staged = get(g:, 'circuit_tmap_c_l_sends_staged', 1)
let g:circuit_vmap_c_l_sends_ref = get(g:, 'circuit_vmap_c_l_sends_ref', 1)
" When 0, do not run |:checktime| on FocusGained/BufEnter (only the timer
" may reload files). Can reduce cursor/redraw flicker with a busy :terminal.
let g:circuit_checktime_on_bufenter = get(g:, 'circuit_checktime_on_bufenter', 1)
let g:circuit_autoread_during_session = get(g:, 'circuit_autoread_during_session', 0)
let g:circuit_refsend_switch_tab = get(g:, 'circuit_refsend_switch_tab', 0)
let g:circuit_sendkeys_delay   = get(g:, 'circuit_sendkeys_delay', 200)
let g:circuit_server_mode      = get(g:, 'circuit_server_mode', 'lazy')

" Keymap variables (all overridable)
let g:circuit_map_toggle       = get(g:, 'circuit_map_toggle', '<leader>c')
let g:circuit_map_prompt       = get(g:, 'circuit_map_prompt', '<leader>[')

" ---------------------------------------------------------------------------
" Commands
" ---------------------------------------------------------------------------

" Main dispatcher
command! -nargs=* -complete=customlist,circuit#complete CTerm call s:dispatch(<f-args>)

" Short aliases
command! -nargs=0 CT         call circuit#toggle()
command! -nargs=0 CTresume   call circuit#resume()
command! -nargs=0 CTcontinue call circuit#continue()
command! -nargs=0 CTnew      call circuit#new()
command! -nargs=0 CTkill     call circuit#kill()
command! -nargs=0 CTplan      call circuit#set_mode('plan')
command! -nargs=0 CTplanopen  call circuit#plan_open()
command! -nargs=0 CTplanexec  call circuit#plan_exec()
command! -nargs=0 CTplanclose call circuit#plan_close()
command! -nargs=1 CTmodel    call circuit#set_model(<f-args>)
command! -nargs=0 CTversion  call circuit#version()
command! -nargs=0 -range   CTsend     call circuit#send_selection(<line1>, <line2>)
command! -range -nargs=0 CTref        call circuit#stage_ref(<line1>, <line2>)
command! -range -nargs=0 CTaddtochat  call circuit#stage_ref(<line1>, <line2>)
command! -nargs=0 -range   CTrefsend  call circuit#send_staged_ref()
command! -nargs=0 CTrefclear call circuit#clear_staged_refs()
command! -nargs=0 CTreflist  call circuit#list_staged_refs()
command! -nargs=0 CTchat     call circuit#chat()
command! -nargs=0 CTundo     call circuit#undo()
command! -nargs=0 CTredo     call circuit#redo()
command! -nargs=0 CTexport   call circuit#export()
command! -nargs=0 CTstats    call circuit#stats()
command! -nargs=0 CTsessions call circuit#sessions()
command! -nargs=0 CTprompt   call circuit#prompt()
command! -nargs=0 CTping     call circuit#ping()
command! -nargs=0 CTserve    call circuit#server_start()
command! -nargs=0 CTpick     call circuit#open_sessions()
command! -nargs=0 CTmodels   call circuit#open_models()

function! s:dispatch(...) abort
  if a:0 == 0
    call circuit#toggle()
    return
  endif

  let l:cmd = a:1

  if l:cmd ==# 'resume'
    call circuit#resume()
  elseif l:cmd ==# 'continue'
    call circuit#continue()
  elseif l:cmd ==# 'new'
    call circuit#new()
  elseif l:cmd ==# 'kill'
    call circuit#kill()
  elseif l:cmd ==# 'send'
    call circuit#send_selection()
  elseif l:cmd ==# 'ref'
    call circuit#stage_ref(line('.'), line('.'))
  elseif l:cmd ==# 'refsend'
    call circuit#send_staged_ref()
  elseif l:cmd ==# 'refclear'
    call circuit#clear_staged_refs()
  elseif l:cmd ==# 'reflist'
    call circuit#list_staged_refs()
  elseif l:cmd ==# 'chat'
    call circuit#chat()
  elseif l:cmd ==# 'version'
    call circuit#version()
  elseif l:cmd ==# 'plan'
    call circuit#set_mode('plan')
  elseif l:cmd ==# 'planopen'
    call circuit#plan_open()
  elseif l:cmd ==# 'planexec'
    call circuit#plan_exec()
  elseif l:cmd ==# 'planclose'
    call circuit#plan_close()
  elseif l:cmd ==# 'mode'
    if a:0 >= 2
      call circuit#set_mode(a:2)
    else
      echoerr 'vim-circuit: mode requires an argument'
    endif
  elseif l:cmd ==# 'model'
    if a:0 >= 2
      call circuit#set_model(a:2)
    else
      echoerr 'vim-circuit: model requires an argument'
    endif
  elseif l:cmd ==# 'undo'
    call circuit#undo()
  elseif l:cmd ==# 'redo'
    call circuit#redo()
  elseif l:cmd ==# 'export'
    call circuit#export()
  elseif l:cmd ==# 'stats'
    call circuit#stats()
  elseif l:cmd ==# 'sessions'
    call circuit#sessions()
  elseif l:cmd ==# 'position'
    if a:0 >= 2
      call circuit#set_position(a:2)
    else
      echoerr 'vim-circuit: position requires an argument (right/left/top/bottom)'
    endif
  elseif l:cmd ==# 'prompt'
    call circuit#prompt()
  elseif l:cmd ==# 'ping'
    call circuit#ping()
  elseif l:cmd ==# 'serve'
    call circuit#server_start()
  elseif l:cmd ==# 'pick'
    call circuit#open_sessions()
  elseif l:cmd ==# 'models'
    call circuit#open_models()
  else
    echoerr 'vim-circuit: unknown subcommand "' . l:cmd . '"'
  endif
endfunction

" ---------------------------------------------------------------------------
" Keymaps
" ---------------------------------------------------------------------------

if g:circuit_map_keys
  execute 'nnoremap <silent> ' . g:circuit_map_toggle . ' :call circuit#toggle()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_prompt . ' :call circuit#prompt()<CR>'

  " Terminal-mode window navigation
  " <C-h> omitted by default: same as Ctrl+Backspace in many terminals (^H)
  if g:circuit_tmap_ch_left
    tnoremap <silent> <C-h> <C-\><C-n><C-w>h
  endif
  tnoremap <silent> <M-h> <C-\><C-n><C-w>h
  tnoremap <silent> <C-j> <C-\><C-n><C-w>j
  tnoremap <silent> <C-k> <C-\><C-n><C-w>k
  if get(g:, 'circuit_tmap_c_l_sends_staged', 1)
    tnoremap <expr> <C-l> circuit#terminal_c_l()
  else
    tnoremap <silent> <C-l> <C-\><C-n><C-w>l
  endif
  tnoremap <silent> <C-v> <C-\><C-n>"+pi

  if g:circuit_vmap_c_l_sends_ref
    xnoremap <silent> <C-l> :<C-u>call circuit#stage_and_send_ref(line("'<"), line("'>"))<CR>
  endif
endif

" ---------------------------------------------------------------------------
" Autocommands
" ---------------------------------------------------------------------------

augroup circuit_autoread
  autocmd!
  autocmd FocusGained,BufEnter * if get(g:, 'circuit_checktime_on_bufenter', 1) && get(g:, 'circuit_auto_reload', 1) | checktime | endif
augroup END

if has('terminal') && exists('##TermClose')
  augroup circuit_termexit
    autocmd!
    autocmd TermClose * call circuit#on_termclose(0 + expand('<abuf>'))
  augroup END
endif

augroup circuit_quit
  autocmd!
  autocmd QuitPre * call circuit#kill()
augroup END

augroup circuit_server
  autocmd!
  if g:circuit_server_mode ==# 'start'
    autocmd VimEnter * call circuit#server_start()
  endif
  autocmd VimLeave * call circuit#server_stop()
augroup END
