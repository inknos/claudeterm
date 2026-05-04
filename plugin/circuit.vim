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

let g:circuit_provider         = get(g:, 'circuit_provider', '')
let g:circuit_command          = get(g:, 'circuit_command', '')
let g:circuit_position         = get(g:, 'circuit_position', 'right')
let g:circuit_split_ratio      = get(g:, 'circuit_split_ratio', 0.4)
let g:circuit_enter_insert     = get(g:, 'circuit_enter_insert', 1)
let g:circuit_use_git_root     = get(g:, 'circuit_use_git_root', 1)
let g:circuit_permission_mode  = get(g:, 'circuit_permission_mode', '')
let g:circuit_model            = get(g:, 'circuit_model', '')
let g:circuit_extra_args       = get(g:, 'circuit_extra_args', '')
let g:circuit_worktree_tmux    = get(g:, 'circuit_worktree_tmux', 0)

let g:circuit_plan_close_on_exec = get(g:, 'circuit_plan_close_on_exec', 1)

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
" When 0, do not run |:checktime| on FocusGained/BufEnter (only the timer
" may reload files). Can reduce cursor/redraw flicker with a busy :terminal.
let g:circuit_checktime_on_bufenter = get(g:, 'circuit_checktime_on_bufenter', 1)
let g:circuit_autoread_during_session = get(g:, 'circuit_autoread_during_session', 0)

" Keymap variables (all overridable)
let g:circuit_map_toggle       = get(g:, 'circuit_map_toggle', '<leader>c')
let g:circuit_map_resume       = get(g:, 'circuit_map_resume', '<leader>cr')
let g:circuit_map_continue     = get(g:, 'circuit_map_continue', '<leader>cc')
let g:circuit_map_new          = get(g:, 'circuit_map_new', '<leader>cn')
let g:circuit_map_kill         = get(g:, 'circuit_map_kill', '<leader>ck')
let g:circuit_map_pr           = get(g:, 'circuit_map_pr', '<leader>cp')
let g:circuit_map_zoom         = get(g:, 'circuit_map_zoom', '<leader>cz')
let g:circuit_map_zoom_term    = get(g:, 'circuit_map_zoom_term', '<C-w>z')
let g:circuit_map_send         = get(g:, 'circuit_map_send', '<leader>cs')
let g:circuit_map_stage_ref    = get(g:, 'circuit_map_stage_ref', '<leader>ca')
let g:circuit_map_chat         = get(g:, 'circuit_map_chat', '<leader>ch')
let g:circuit_map_verbose      = get(g:, 'circuit_map_verbose', '<leader>cv')
let g:circuit_map_mode_plan    = get(g:, 'circuit_map_mode_plan', '<leader>cmp')
let g:circuit_map_mode_fast    = get(g:, 'circuit_map_mode_fast', '<leader>cmf')
let g:circuit_map_worktree     = get(g:, 'circuit_map_worktree', '<leader>cw')
let g:circuit_map_undo         = get(g:, 'circuit_map_undo', '<leader>cu')
let g:circuit_map_redo         = get(g:, 'circuit_map_redo', '<leader>cU')
let g:circuit_map_export       = get(g:, 'circuit_map_export', '<leader>ce')
let g:circuit_map_sessions     = get(g:, 'circuit_map_sessions', '<leader>cl')
let g:circuit_map_plan_open    = get(g:, 'circuit_map_plan_open', '<leader>cpo')
let g:circuit_map_plan_exec    = get(g:, 'circuit_map_plan_exec', '<leader>cpx')
let g:circuit_map_prompt       = get(g:, 'circuit_map_prompt', '<leader>[')
let g:circuit_map_refsend      = get(g:, 'circuit_map_refsend', '<C-l>')

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
command! -nargs=0 CTpr       call circuit#from_pr()
command! -nargs=0 CTzoom     call circuit#zoom()
command! -nargs=0 CTplan      call circuit#set_mode('plan')
command! -nargs=0 CTfast      call circuit#set_mode('fast')
command! -nargs=0 CTnormal    call circuit#set_mode('normal')
command! -nargs=0 CTplanopen  call circuit#plan_open()
command! -nargs=0 CTplanexec  call circuit#plan_exec()
command! -nargs=0 CTplanclose call circuit#plan_close()
command! -nargs=1 CTmodel    call circuit#set_model(<f-args>)
command! -nargs=0 CTverbose  call circuit#toggle_verbose()
command! -nargs=0 CTdoctor   call circuit#doctor()
command! -nargs=0 CTversion  call circuit#version()
command! -nargs=0 -range   CTsend     call circuit#send_selection(<line1>, <line2>)
command! -range -nargs=0 CTref        call circuit#stage_ref(<line1>, <line2>)
command! -range -nargs=0 CTaddtochat  call circuit#stage_ref(<line1>, <line2>)
command! -nargs=0 -range   CTrefsend  call circuit#send_staged_ref()
command! -nargs=0 CTrefclear call circuit#clear_staged_refs()
command! -nargs=0 CTreflist  call circuit#list_staged_refs()
command! -nargs=0 CTchat     call circuit#chat()
command! -nargs=? -bang CTworktree call circuit#worktree(<q-args>, <bang>0)
command! -nargs=0 CTundo     call circuit#undo()
command! -nargs=0 CTredo     call circuit#redo()
command! -nargs=0 CTexport   call circuit#export()
command! -nargs=0 CTstats    call circuit#stats()
command! -nargs=0 CTsessions call circuit#sessions()
command! -nargs=0 CTprompt   call circuit#prompt()

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
  elseif l:cmd ==# 'pr'
    call circuit#from_pr()
  elseif l:cmd ==# 'zoom'
    call circuit#zoom()
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
  elseif l:cmd ==# 'verbose'
    call circuit#toggle_verbose()
  elseif l:cmd ==# 'doctor'
    call circuit#doctor()
  elseif l:cmd ==# 'version'
    call circuit#version()
  elseif l:cmd ==# 'plan'
    call circuit#set_mode('plan')
  elseif l:cmd ==# 'fast'
    call circuit#set_mode('fast')
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
      echoerr 'vim-circuit: mode requires an argument (plan/fast/normal)'
    endif
  elseif l:cmd ==# 'model'
    if a:0 >= 2
      call circuit#set_model(a:2)
    else
      echoerr 'vim-circuit: model requires an argument'
    endif
  elseif l:cmd ==# 'worktree'
    call circuit#worktree(a:0 >= 2 ? a:2 : '', 0)
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
  else
    echoerr 'vim-circuit: unknown subcommand "' . l:cmd . '"'
  endif
endfunction

" ---------------------------------------------------------------------------
" Keymaps
" ---------------------------------------------------------------------------

if g:circuit_map_keys
  " Session management
  execute 'nnoremap <silent> ' . g:circuit_map_toggle   . ' :call circuit#toggle()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_resume   . ' :call circuit#resume()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_continue . ' :call circuit#continue()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_new      . ' :call circuit#new()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_kill     . ' :call circuit#kill()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_pr       . ' :call circuit#from_pr()<CR>'

  " Window
  execute 'nnoremap <silent> ' . g:circuit_map_zoom     . ' :call circuit#zoom()<CR>'
  execute 'tnoremap <silent> ' . g:circuit_map_zoom_term . ' <C-\><C-n>:call circuit#zoom()<CR>'

  " Code context
  execute 'vnoremap <silent> ' . g:circuit_map_send
        \ . " :CTsend<CR>"
  execute 'nnoremap <silent> ' . g:circuit_map_stage_ref
        \ . " :.CTref<CR>"
  execute 'vnoremap <silent> ' . g:circuit_map_stage_ref
        \ . " :CTref<CR>"
  execute 'vnoremap <silent> ' . g:circuit_map_refsend
        \ . " :<C-u>call circuit#stage_and_send_ref(line(\"'<\"), line(\"'>\"))<CR>"
  execute 'nnoremap <silent> ' . g:circuit_map_chat     . ' :call circuit#chat()<CR>'

  " Verbose
  execute 'nnoremap <silent> ' . g:circuit_map_verbose  . ' :call circuit#toggle_verbose()<CR>'

  " Mode control (sends /plan or /fast slash commands to the session)
  execute 'nnoremap <silent> ' . g:circuit_map_mode_plan . " :call circuit#set_mode('plan')<CR>"
  execute 'nnoremap <silent> ' . g:circuit_map_mode_fast . " :call circuit#set_mode('fast')<CR>"

  " Plan workflow
  execute 'nnoremap <silent> ' . g:circuit_map_plan_open . ' :call circuit#plan_open()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_plan_exec . ' :call circuit#plan_exec()<CR>'

  " Command prompt
  execute 'nnoremap <silent> ' . g:circuit_map_prompt . ' :call circuit#prompt()<CR>'

  " Worktree
  execute 'nnoremap <silent> ' . g:circuit_map_worktree    . " :call circuit#worktree('', 0)<CR>"

  " Provider features
  execute 'nnoremap <silent> ' . g:circuit_map_undo     . ' :call circuit#undo()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_redo     . ' :call circuit#redo()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_export   . ' :call circuit#export()<CR>'
  execute 'nnoremap <silent> ' . g:circuit_map_sessions . ' :call circuit#sessions()<CR>'

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
