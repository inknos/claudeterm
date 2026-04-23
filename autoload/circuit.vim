" vim-circuit: core functions
" Maintainer: inknos
" License: GPL-3.0

" ---------------------------------------------------------------------------
" Internal state
" ---------------------------------------------------------------------------
let s:term_bufnr = -1
let s:term_winid = -1
let s:is_zoomed = 0
let s:pre_zoom_winrestcmd = ''
let s:reload_timer = -1
let s:current_mode = ''
let s:current_model = ''
let s:verbose = 0

" ---------------------------------------------------------------------------
" Helpers
" ---------------------------------------------------------------------------

function! s:get(name, default) abort
  let l:bvar = 'b:circuit_' . a:name
  let l:gvar = 'g:circuit_' . a:name
  if exists(l:bvar)
    return eval(l:bvar)
  endif
  if exists(l:gvar)
    return eval(l:gvar)
  endif
  return a:default
endfunction

function! s:git_root() abort
  let l:root = trim(system('git rev-parse --show-toplevel 2>/dev/null'))
  if v:shell_error || empty(l:root)
    return getcwd()
  endif
  return l:root
endfunction

function! s:provider() abort
  if !circuit#providers#configured()
    return {}
  endif
  return circuit#providers#current()
endfunction

function! s:needs_provider() abort
  if circuit#providers#configured()
    return 0
  endif
  call s:show_setup_guide()
  return 1
endfunction

function! s:show_setup_guide() abort
  call s:open_split()
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  let l:lines = [
        \ '  vim-circuit: no provider configured',
        \ '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
        \ '',
        \ '  Add one of these to your .vimrc:',
        \ '',
        \ '    let g:circuit_provider = ''opencode''    (recommended)',
        \ '    let g:circuit_provider = ''claude''',
        \ '    let g:circuit_provider = ''gemini''',
        \ '    let g:circuit_provider = ''agent''',
        \ '',
        \ '  Then reload Vim and run :CTerm',
        \ '',
        \ '  Each CLI must be installed and authenticated separately.',
        \ '  vim-circuit does not manage API keys or credentials.',
        \ '',
        \ '  For details:  :help circuit-providers',
        \ ]
  call setline(1, l:lines)
  setlocal nomodifiable
endfunction

function! s:build_cmd(...) abort
  let l:p = s:provider()
  let l:override = s:get('command', '')
  let l:cmd = !empty(l:override) ? l:override : l:p.command
  let l:extra = s:get('extra_args', '')

  let l:mode = s:current_mode
  if empty(l:mode)
    let l:mode = s:get('permission_mode', '')
  endif
  if !empty(l:mode) && !empty(l:p.permission_flag)
    let l:cmd .= ' ' . l:p.permission_flag . ' ' . l:mode
  endif

  let l:model = s:current_model
  if empty(l:model)
    let l:model = s:get('model', '')
  endif
  if !empty(l:model) && !empty(l:p.model_flag)
    let l:cmd .= ' ' . l:p.model_flag . ' ' . l:model
  endif

  if s:verbose && !empty(l:p.verbose_flag)
    let l:cmd .= ' ' . l:p.verbose_flag
  endif

  if !empty(l:extra)
    let l:cmd .= ' ' . l:extra
  endif

  if a:0 > 0 && !empty(a:1)
    let l:cmd .= ' ' . a:1
  endif

  return l:cmd
endfunction

function! s:open_split() abort
  let l:pos = s:get('position', 'right')
  let l:ratio = s:get('split_ratio', 0.4)

  if l:pos ==# 'right'
    let l:size = float2nr(&columns * l:ratio)
    execute 'vertical botright ' . l:size . 'new'
  elseif l:pos ==# 'left'
    let l:size = float2nr(&columns * l:ratio)
    execute 'vertical topleft ' . l:size . 'new'
  elseif l:pos ==# 'bottom'
    let l:size = float2nr(&lines * l:ratio)
    execute 'botright ' . l:size . 'new'
  elseif l:pos ==# 'top'
    let l:size = float2nr(&lines * l:ratio)
    execute 'topleft ' . l:size . 'new'
  else
    let l:size = float2nr(&columns * l:ratio)
    execute 'vertical botright ' . l:size . 'new'
  endif
endfunction

function! s:configure_term_window() abort
  if s:get('hide_numbers', 1)
    setlocal nonumber norelativenumber
  endif
  if s:get('hide_signcolumn', 1)
    setlocal signcolumn=no
  endif
  setlocal nobuflisted
endfunction

function! s:focus_term() abort
  if s:get('enter_insert', 1)
    if mode() !=# 't'
      normal! i
    endif
  endif
endfunction

function! s:term_alive() abort
  return s:term_bufnr != -1 && bufexists(s:term_bufnr)
        \ && getbufvar(s:term_bufnr, '&buftype') ==# 'terminal'
        \ && term_getstatus(s:term_bufnr) =~# 'running'
endfunction

" ---------------------------------------------------------------------------
" Toggle
" ---------------------------------------------------------------------------

function! circuit#toggle() abort
  if s:needs_provider()
    return
  endif
  if s:term_alive()
    let l:winid = bufwinid(s:term_bufnr)
    if l:winid != -1
      call s:hide()
    else
      call s:show()
    endif
  else
    let l:cmd = s:build_cmd(s:provider().continue)
    call s:open_with_cmd(l:cmd)
  endif
endfunction

function! s:show() abort
  call s:open_split()
  execute 'buffer ' . s:term_bufnr
  let s:term_winid = win_getid()

  call s:configure_term_window()
  call circuit#hooks#fire('ToggleShow')
  call s:focus_term()
endfunction

function! s:hide() abort
  let l:winid = bufwinid(s:term_bufnr)
  if l:winid != -1
    let l:winnr = win_id2win(l:winid)
    execute l:winnr . 'wincmd w'
    hide
  endif
  call circuit#hooks#fire('ToggleHide')
endfunction

" ---------------------------------------------------------------------------
" Session management
" ---------------------------------------------------------------------------

function! circuit#resume() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  " OpenCode and similar: no --resume; use the same command as |circuit#sessions()|
  " (e.g. `opencode session list`) so :CTresume shows sessions instead of
  " an invalid `opencode --session` with no id.
  if empty(l:p.resume) && !empty(l:p.session_list_cmd)
    call s:kill_term_if_alive()
    let l:override = s:get('command', '')
    let l:bin = !empty(l:override) ? l:override : l:p.command
    let l:cmd = l:bin . ' ' . l:p.session_list_cmd
    call s:open_with_cmd(l:cmd)
    call circuit#hooks#fire('SessionChange')
    return
  endif
  if empty(l:p.resume)
    echo 'vim-circuit: resume not supported by ' . g:circuit_provider
    return
  endif
  call s:kill_term_if_alive()
  let l:cmd = s:build_cmd(l:p.resume)
  call s:open_with_cmd(l:cmd)
  call circuit#hooks#fire('SessionChange')
endfunction

function! circuit#continue() abort
  if s:needs_provider()
    return
  endif
  call s:kill_term_if_alive()
  let l:cmd = s:build_cmd(s:provider().continue)
  call s:open_with_cmd(l:cmd)
  call circuit#hooks#fire('SessionChange')
endfunction

function! circuit#new() abort
  if s:needs_provider()
    return
  endif
  call s:kill_term_if_alive()
  let l:cmd = s:build_cmd('')
  call s:open_with_cmd(l:cmd)
  call circuit#hooks#fire('SessionChange')
endfunction

function! circuit#from_pr() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.from_pr_flag)
    echo 'vim-circuit: from-pr not supported by ' . g:circuit_provider
    return
  endif
  call s:kill_term_if_alive()
  let l:cmd = s:build_cmd(l:p.from_pr_flag)
  call s:open_with_cmd(l:cmd)
  call circuit#hooks#fire('SessionChange')
endfunction

function! circuit#kill() abort
  call s:kill_term_if_alive()
  call circuit#hooks#fire('Kill')
endfunction

" Called on |TermClose| (plugin) when a terminal's job ended; also used by
" tests and future integrations.
function! circuit#on_termclose(bufnr) abort
  if a:bufnr !=# s:term_bufnr
    return
  endif
  call s:cleanup_after_circuit_job_exit()
endfunction

function! s:close_circuit_buffer_window() abort
  if s:term_bufnr ==# -1
    return
  endif
  let l:buf = s:term_bufnr
  if !bufexists(l:buf)
    return
  endif
  let l:winid = bufwinid(l:buf)
  if l:winid !=# -1
    let l:save = win_getid()
    let l:target = win_id2win(l:winid)
    execute l:target . 'wincmd w'
    quit!
    if win_id2win(l:save) > 0
      call win_gotoid(l:save)
    endif
  endif
  if bufexists(l:buf)
    execute 'bwipeout! ' . l:buf
  endif
endfunction

" After the agent CLI (e.g. opencode) exits, close the split, wipe the buffer,
" and fire |CTTermExited| — distinct from CTKill (|circuit#kill()|).
function! s:cleanup_after_circuit_job_exit() abort
  call s:stop_reload_timer()
  if s:term_bufnr ==# -1
    return
  endif
  if !bufexists(s:term_bufnr)
    let s:term_bufnr = -1
    let s:term_winid = -1
    let s:is_zoomed = 0
    return
  endif
  if s:term_alive()
    return
  endif
  call s:close_circuit_buffer_window()
  let s:term_bufnr = -1
  let s:term_winid = -1
  let s:is_zoomed = 0
  call circuit#hooks#fire('TermExited')
endfunction

function! s:kill_term_if_alive() abort
  call s:stop_reload_timer()
  if s:term_alive()
    call s:close_circuit_buffer_window()
  endif
  let s:term_bufnr = -1
  let s:term_winid = -1
  let s:is_zoomed = 0
endfunction

function! s:open_with_cmd(cmd) abort
  let l:cwd = s:get('use_git_root', 1) ? s:git_root() : getcwd()

  let l:saved_dir = getcwd()
  execute 'lcd ' . fnameescape(l:cwd)
  call s:open_split()
  execute 'terminal ++curwin ++close ' . a:cmd
  execute 'lcd ' . fnameescape(l:saved_dir)
  let s:term_bufnr = bufnr('%')
  let s:term_winid = win_getid()

  call s:configure_term_window()
  call s:start_reload_timer()
  call circuit#hooks#fire('Open')
  call s:focus_term()
endfunction

" ---------------------------------------------------------------------------
" Mode control (sends slash commands to the running session)
" ---------------------------------------------------------------------------

function! circuit#set_mode(mode) abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.modes)
    echo 'vim-circuit: interactive modes not supported by ' . g:circuit_provider
    return
  endif

  if !s:term_alive()
    call circuit#toggle()
  else
    let l:winid = bufwinid(s:term_bufnr)
    if l:winid == -1
      call s:show()
    endif
  endif

  call term_sendkeys(s:term_bufnr, l:p.mode_prefix . a:mode . "\n")
  let s:current_mode = a:mode
  call circuit#hooks#fire('ModeChange')
endfunction

" ---------------------------------------------------------------------------
" Model switching
" ---------------------------------------------------------------------------

function! circuit#set_model(model) abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.model_flag)
    echo 'vim-circuit: model switching not supported by ' . g:circuit_provider
    return
  endif
  let s:current_model = a:model
  call s:kill_term_if_alive()
  let l:cmd = s:build_cmd(l:p.continue)
  call s:open_with_cmd(l:cmd)
endfunction

" ---------------------------------------------------------------------------
" Worktree
" ---------------------------------------------------------------------------

function! circuit#worktree(name, bang) abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.worktree_flag)
    echo 'vim-circuit: worktree not supported by ' . g:circuit_provider
    return
  endif

  call s:kill_term_if_alive()

  let l:override = s:get('command', '')
  let l:cmd = !empty(l:override) ? l:override : l:p.command
  let l:cmd .= ' ' . l:p.worktree_flag
  if !empty(a:name)
    let l:cmd .= ' ' . a:name
  endif
  let l:use_tmux = a:bang || s:get('worktree_tmux', 0)
  if l:use_tmux && !empty(l:p.tmux_flag)
    let l:cmd .= ' ' . l:p.tmux_flag
  endif

  let l:cwd = s:get('use_git_root', 1) ? s:git_root() : getcwd()
  let l:saved_dir = getcwd()
  execute 'lcd ' . fnameescape(l:cwd)
  call s:open_split()
  execute 'terminal ++curwin ++close ' . l:cmd
  execute 'lcd ' . fnameescape(l:saved_dir)

  let s:term_bufnr = bufnr('%')
  let s:term_winid = win_getid()

  call s:configure_term_window()
  call s:start_reload_timer()
  call circuit#hooks#fire('Worktree')
  call s:focus_term()
endfunction

" ---------------------------------------------------------------------------
" Verbose toggle
" ---------------------------------------------------------------------------

function! circuit#toggle_verbose() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.verbose_flag)
    echo 'vim-circuit: verbose not supported by ' . g:circuit_provider
    return
  endif
  let s:verbose = !s:verbose
  call s:kill_term_if_alive()
  let l:cmd = s:build_cmd(l:p.continue)
  call s:open_with_cmd(l:cmd)
  echo 'vim-circuit: verbose ' . (s:verbose ? 'ON' : 'OFF')
endfunction

" ---------------------------------------------------------------------------
" Zoom
" ---------------------------------------------------------------------------

function! circuit#zoom() abort
  if !s:term_alive()
    echo 'vim-circuit: no active terminal'
    return
  endif

  let l:winid = bufwinid(s:term_bufnr)
  if l:winid == -1
    call s:show()
    return
  endif

  if s:is_zoomed
    let s:is_zoomed = 0
    execute s:pre_zoom_winrestcmd
    call circuit#hooks#fire('ZoomOut')
  else
    let s:pre_zoom_winrestcmd = winrestcmd()
    let l:winnr = win_id2win(l:winid)
    execute l:winnr . 'wincmd w'
    wincmd |
    wincmd _
    let s:is_zoomed = 1
    call circuit#hooks#fire('ZoomIn')
  endif
endfunction

" ---------------------------------------------------------------------------
" Send selection
" ---------------------------------------------------------------------------

function! circuit#send_selection() abort
  if !s:term_alive()
    echo 'vim-circuit: no active terminal'
    return
  endif

  let l:lines = getline("'<", "'>")
  if empty(l:lines)
    return
  endif

  let l:fname = expand('%:t')
  let l:header = '# From ' . l:fname
  let l:text = l:header . "\n" . join(l:lines, "\n") . "\n"

  call term_sendkeys(s:term_bufnr, l:text)
endfunction

" ---------------------------------------------------------------------------
" Chat (free-form prompt)
" ---------------------------------------------------------------------------

function! circuit#chat() abort
  let l:msg = input('circuit> ')
  if empty(l:msg)
    return
  endif

  if !s:term_alive()
    call circuit#toggle()
  else
    let l:winid = bufwinid(s:term_bufnr)
    if l:winid == -1
      call s:show()
    endif
  endif

  let l:fname = expand('#:t')
  let l:context = ''
  if !empty(l:fname)
    let l:context = '(context: ' . l:fname . ') '
  endif

  call term_sendkeys(s:term_bufnr, l:context . l:msg . "\n")
endfunction

" ---------------------------------------------------------------------------
" Position change
" ---------------------------------------------------------------------------

function! circuit#set_position(pos) abort
  if index(['right', 'left', 'top', 'bottom'], a:pos) == -1
    echoerr 'vim-circuit: invalid position "' . a:pos . '". Use right/left/top/bottom.'
    return
  endif
  let g:circuit_position = a:pos
  if s:term_alive() && bufwinid(s:term_bufnr) != -1
    call s:hide()
    call s:show()
  endif
endfunction

" ---------------------------------------------------------------------------
" Doctor / Version
" ---------------------------------------------------------------------------

function! circuit#doctor() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.doctor_cmd)
    echo 'vim-circuit: health check not supported by ' . g:circuit_provider
    return
  endif
  let l:override = s:get('command', '')
  let l:bin = !empty(l:override) ? l:override : l:p.command
  echo trim(system(l:bin . ' ' . l:p.doctor_cmd . ' 2>&1'))
endfunction

function! circuit#version() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  let l:override = s:get('command', '')
  let l:bin = !empty(l:override) ? l:override : l:p.command
  let l:cli_ver = trim(system(l:bin . ' ' . l:p.version_flag . ' 2>&1'))
  echo 'vim-circuit:  0.1.0'
  echo 'provider:     ' . g:circuit_provider
  echo 'cli version:  ' . l:cli_ver
  echo 'vim:          ' . v:version
  echo 'terminal:     ' . (has('terminal') ? '+terminal' : '-terminal')
endfunction

" ---------------------------------------------------------------------------
" Auto-reload
" ---------------------------------------------------------------------------

function! s:start_reload_timer() abort
  call s:stop_reload_timer()
  let l:interval = s:get('reload_interval', 1000)
  let s:reload_timer = timer_start(l:interval, function('s:reload_check'), {'repeat': -1})
endfunction

function! s:stop_reload_timer() abort
  if s:reload_timer != -1
    call timer_stop(s:reload_timer)
    let s:reload_timer = -1
  endif
endfunction

function! s:reload_check(timer_id) abort
  if s:term_bufnr !=# -1 && !s:term_alive()
    call s:cleanup_after_circuit_job_exit()
    return
  endif
  if !s:term_alive()
    call s:stop_reload_timer()
    return
  endif
  if !s:get('auto_reload', 1)
    return
  endif
  let l:reloaded = 0
  for l:bufnr in range(1, bufnr('$'))
    if buflisted(l:bufnr) && l:bufnr != s:term_bufnr
          \ && getbufvar(l:bufnr, '&buftype') ==# ''
          \ && !empty(bufname(l:bufnr))
      let l:fname = fnamemodify(bufname(l:bufnr), ':p')
      if getftime(l:fname) > getbufvar(l:bufnr, 'circuit_mtime', 0)
        call setbufvar(l:bufnr, 'circuit_mtime', getftime(l:fname))
        if bufloaded(l:bufnr)
          execute 'checktime ' . l:bufnr
          let l:reloaded = 1
        endif
      endif
    endif
  endfor
  if l:reloaded
    if s:get('notify_reload', 1)
      echohl WarningMsg | echo 'vim-circuit: buffers reloaded' | echohl None
    endif
    call circuit#hooks#fire('Reload')
  endif
endfunction

" ---------------------------------------------------------------------------
" Undo / Redo
" ---------------------------------------------------------------------------

function! circuit#undo() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  let l:cmd = get(l:p.slash_commands, 'undo', '')
  if empty(l:cmd)
    echo 'vim-circuit: undo not supported by ' . g:circuit_provider
    return
  endif
  if !s:term_alive()
    echo 'vim-circuit: no active terminal'
    return
  endif
  call term_sendkeys(s:term_bufnr, l:cmd . "\n")
  call circuit#hooks#fire('Undo')
endfunction

function! circuit#redo() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  let l:cmd = get(l:p.slash_commands, 'redo', '')
  if empty(l:cmd)
    echo 'vim-circuit: redo not supported by ' . g:circuit_provider
    return
  endif
  if !s:term_alive()
    echo 'vim-circuit: no active terminal'
    return
  endif
  call term_sendkeys(s:term_bufnr, l:cmd . "\n")
  call circuit#hooks#fire('Redo')
endfunction

" ---------------------------------------------------------------------------
" Export
" ---------------------------------------------------------------------------

function! circuit#export() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  let l:cmd = get(l:p.slash_commands, 'export', '')
  if empty(l:cmd)
    echo 'vim-circuit: export not supported by ' . g:circuit_provider
    return
  endif
  if !s:term_alive()
    echo 'vim-circuit: no active terminal'
    return
  endif
  call term_sendkeys(s:term_bufnr, l:cmd . "\n")
  call circuit#hooks#fire('Export')
endfunction

" ---------------------------------------------------------------------------
" Stats
" ---------------------------------------------------------------------------

function! circuit#stats() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.stats_cmd)
    echo 'vim-circuit: stats not supported by ' . g:circuit_provider
    return
  endif
  let l:override = s:get('command', '')
  let l:bin = !empty(l:override) ? l:override : l:p.command
  echo trim(system(l:bin . ' ' . l:p.stats_cmd . ' 2>&1'))
endfunction

" ---------------------------------------------------------------------------
" Session list
" ---------------------------------------------------------------------------

function! circuit#sessions() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  if empty(l:p.session_list_cmd)
    call circuit#resume()
    return
  endif
  call s:kill_term_if_alive()
  let l:override = s:get('command', '')
  let l:bin = !empty(l:override) ? l:override : l:p.command
  let l:cmd = l:bin . ' ' . l:p.session_list_cmd
  call s:open_with_cmd(l:cmd)
  call circuit#hooks#fire('SessionList')
endfunction

" ---------------------------------------------------------------------------
" Tab-completion helper
" ---------------------------------------------------------------------------

function! circuit#complete(arglead, cmdline, cursorpos) abort
  let l:parts = split(a:cmdline, '\s\+')
  let l:nparts = len(l:parts)

  if l:nparts <= 2
    let l:subs = ['resume', 'continue', 'new', 'kill', 'pr', 'worktree',
          \ 'plan', 'fast', 'mode', 'zoom', 'position', 'send', 'chat',
          \ 'model', 'verbose', 'doctor', 'version',
          \ 'undo', 'redo', 'export', 'stats', 'sessions']
    return filter(copy(l:subs), 'v:val =~# "^" . a:arglead')
  endif

  let l:sub = l:parts[1]
  let l:cur = circuit#providers#current()
  if l:sub ==# 'mode'
    let l:modes = empty(l:cur) ? [] : l:cur.modes
    return filter(copy(l:modes), 'v:val =~# "^" . a:arglead')
  elseif l:sub ==# 'model'
    let l:models = empty(l:cur) ? [] : l:cur.models
    return filter(copy(l:models), 'v:val =~# "^" . a:arglead')
  elseif l:sub ==# 'position'
    let l:positions = ['right', 'left', 'top', 'bottom']
    return filter(copy(l:positions), 'v:val =~# "^" . a:arglead')
  endif

  return []
endfunction
