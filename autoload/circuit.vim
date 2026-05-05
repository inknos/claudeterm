" vim-circuit: core functions
" Maintainer: inknos
" License: GPL-3.0

" ---------------------------------------------------------------------------
" Internal state
" ---------------------------------------------------------------------------
let s:term_bufnr = -1
let s:term_winid = -1
let s:reload_timer = -1
let s:current_mode = ''
let s:current_model = ''
let s:verbose = 0
let s:autoread_save = 0
let s:autoread_armed = 0
let s:staged_file_refs = []
let s:plan_bufnr = -1
let s:pre_plan_bufnr = -1
let s:prompt_winid = -1
let s:prompt_text = ''
let s:prompt_matches = []
let s:prompt_selected = 0
let s:prompt_prefix = ''
let s:prompt_props = []

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

function! s:get_toggle(prefix, key) abort
  let l:specific = a:prefix . '_' . a:key
  let l:bspec = 'b:circuit_' . l:specific
  if exists(l:bspec)
    return eval(l:bspec)
  endif
  let l:gspec = 'g:circuit_' . l:specific
  if exists(l:gspec)
    return eval(l:gspec)
  endif
  return s:get(a:prefix, 1)
endfunction

function! s:maybe_start(key) abort
  if s:term_alive()
    return 1
  endif
  if !s:get_toggle('start_on', a:key)
    echo 'vim-circuit: no active terminal'
    return 0
  endif
  call circuit#toggle()
  return s:term_alive()
endfunction

function! s:maybe_show(key) abort
  if bufwinid(s:term_bufnr) ==# -1 && s:get_toggle('show_on', a:key)
    call s:show()
  endif
endfunction

function! s:maybe_enable_autoread_for_session() abort
  if !s:get('autoread_during_session', 0) || s:autoread_armed
    return
  endif
  let s:autoread_save = &autoread
  set autoread
  let s:autoread_armed = 1
endfunction

function! s:maybe_restore_autoread_after_session() abort
  if !s:autoread_armed
    return
  endif
  let &autoread = s:autoread_save
  let s:autoread_armed = 0
endfunction

function! s:git_root() abort
  let l:root = trim(system('git rev-parse --show-toplevel 2>/dev/null'))
  if v:shell_error || empty(l:root)
    return getcwd()
  endif
  return l:root
endfunction

" Staged ref: `relpath:line` or `relpath:start-end` (relative to git root
" when |g:circuit_use_git_root| is 1, else to |getcwd()|).
function! s:ref_path_pretty() abort
  let l:abs = expand('%:p')
  if !empty(l:abs)
    let l:rel = s:relpath_for_file_ref(l:abs)
  else
    let l:bn = bufname('%')
    if !empty(l:bn)
      let l:rel = s:relpath_for_file_ref(fnamemodify(l:bn, ':p'))
    else
      let l:rel = 'buffer' . bufnr('%')
    endif
  endif
  " Normalize to `/` (many CLIs; consistent when Windows yields backslashes)
  if l:rel =~# '\\'
    return tr(l:rel, '\', '/')
  endif
  return l:rel
endfunction

function! s:relpath_for_file_ref(abs) abort
  if s:get('use_git_root', 1)
    let l:r = s:git_root()
    if !empty(l:r)
      if a:abs ==# l:r
        return '.'
      endif
      let l:lr = len(l:r)
      if len(a:abs) > l:lr
            \ && (a:abs[l:lr] ==# '/' || a:abs[l:lr] ==# '\')
            \ && strpart(a:abs, 0, l:lr) ==# l:r
        return strpart(a:abs, l:lr + 1)
      endif
    endif
  endif
  return fnamemodify(a:abs, ':.')
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
    call s:maybe_restore_autoread_after_session()
    return
  endif
  if s:term_alive()
    return
  endif
  call s:close_circuit_buffer_window()
  let s:term_bufnr = -1
  let s:term_winid = -1
  call s:maybe_restore_autoread_after_session()
  call circuit#hooks#fire('TermExited')
endfunction

function! s:kill_term_if_alive() abort
  call s:stop_reload_timer()
  if s:term_alive()
    call s:close_circuit_buffer_window()
  endif
  let s:term_bufnr = -1
  let s:term_winid = -1
  call s:maybe_restore_autoread_after_session()
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
  call s:maybe_enable_autoread_for_session()
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

  if !s:maybe_start('mode')
    return
  endif
  call s:maybe_show('mode')

  call term_sendkeys(s:term_bufnr, l:p.mode_prefix . a:mode . "\n")
  let s:current_mode = a:mode
  call circuit#hooks#fire('ModeChange')
endfunction

" ---------------------------------------------------------------------------
" Plan workflow (open / exec / close)
" ---------------------------------------------------------------------------

function! s:latest_plan_file(dir) abort
  let l:expanded = expand(a:dir)
  let l:files = glob(l:expanded . '/*.md', 0, 1)
  if empty(l:files)
    return ''
  endif
  let l:best = l:files[0]
  let l:best_t = getftime(l:best)
  for l:f in l:files[1:]
    let l:t = getftime(l:f)
    if l:t > l:best_t
      let l:best = l:f
      let l:best_t = l:t
    endif
  endfor
  return l:best
endfunction

function! circuit#plan_open() abort
  if s:needs_provider()
    return
  endif

  if s:plan_bufnr != -1 && bufexists(s:plan_bufnr)
    let l:winid = bufwinid(s:plan_bufnr)
    if l:winid != -1
      call win_gotoid(l:winid)
      return
    endif
  endif

  let l:p = s:provider()
  let l:plan_file = ''
  if !empty(l:p.plan_dir)
    let l:dir = l:p.plan_dir
    if l:dir[0] !=# '/' && l:dir[0] !=# '~'
      let l:dir = s:git_root() . '/' . l:dir
    endif
    let l:plan_file = s:latest_plan_file(l:dir)
  endif

  let s:pre_plan_bufnr = bufnr('%')

  if !empty(l:plan_file)
    execute 'edit ' . fnameescape(l:plan_file)
  else
    enew
    setlocal buftype=nofile filetype=markdown
    file [circuit-plan]
  endif

  setlocal autoread
  let s:plan_bufnr = bufnr('%')
  call circuit#hooks#fire('PlanOpen')
endfunction

function! circuit#plan_exec() abort
  if s:needs_provider()
    return
  endif
  if s:plan_bufnr == -1 || !bufexists(s:plan_bufnr)
    echo 'vim-circuit: no plan buffer open (use :CTplanopen)'
    return
  endif
  if !s:term_alive()
    echo 'vim-circuit: no active terminal'
    return
  endif

  let l:lines = getbufline(s:plan_bufnr, 1, '$')
  let l:text = join(l:lines, "\n")
  if empty(trim(l:text))
    echo 'vim-circuit: plan buffer is empty'
    return
  endif

  let l:p = s:provider()
  if s:current_mode ==# 'plan' && !empty(l:p.exit_plan_cmd)
    call term_sendkeys(s:term_bufnr,
          \ l:p.mode_prefix . l:p.exit_plan_cmd . "\n")
    let s:current_mode = l:p.exit_plan_cmd
  endif

  call term_sendkeys(s:term_bufnr, "Execute this plan:\n" . l:text . "\n")
  call circuit#hooks#fire('PlanExec')

  if s:get('plan_close_on_exec', 1)
    call circuit#plan_close()
  endif
endfunction

function! circuit#plan_close() abort
  if s:plan_bufnr == -1 || !bufexists(s:plan_bufnr)
    echo 'vim-circuit: no plan buffer to close'
    return
  endif

  let l:winid = bufwinid(s:plan_bufnr)
  if l:winid != -1
    call win_gotoid(l:winid)
  endif

  if s:pre_plan_bufnr != -1 && bufexists(s:pre_plan_bufnr)
    execute 'buffer ' . s:pre_plan_bufnr
  else
    enew
  endif

  execute 'bdelete ' . s:plan_bufnr
  let s:plan_bufnr = -1
  let s:pre_plan_bufnr = -1
  call circuit#hooks#fire('PlanClose')
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
  call s:maybe_enable_autoread_for_session()
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
" Send selection
" ---------------------------------------------------------------------------

function! circuit#send_selection(...) abort
  if !s:maybe_start('send')
    return
  endif

  if a:0 >= 2
    let l:lo = min([a:1, a:2])
    let l:hi = max([a:1, a:2])
    let l:lines = getline(l:lo, l:hi)
  else
    let l:lines = getline("'<", "'>")
  endif
  if empty(l:lines)
    return
  endif

  call s:maybe_show('send')
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

  if !s:maybe_start('chat')
    return
  endif
  call s:maybe_show('chat')

  let l:fname = expand('#:t')
  let l:context = ''
  if !empty(l:fname)
    let l:context = '(context: ' . l:fname . ') '
  endif

  call term_sendkeys(s:term_bufnr, l:context . l:msg . "\n")
endfunction

" ---------------------------------------------------------------------------
" File:line reference (staged, then send from :terminal)
" ---------------------------------------------------------------------------

function! circuit#stage_ref(line1, line2) abort
  let l:a = a:line1
  let l:b = a:line2
  if l:a > l:b
    let l:tmp = l:a
    let l:a = l:b
    let l:b = l:tmp
  endif
  if l:a == l:b
    let l:ref = s:ref_path_pretty() . ':' . l:a
  else
    let l:ref = s:ref_path_pretty() . ':' . l:a . '-' . l:b
  endif
  call add(s:staged_file_refs, l:ref)
  echo 'vim-circuit: staged ' . l:ref . ' (' . len(s:staged_file_refs) . ' pending)'
  call circuit#hooks#fire('ChatRefStaged')
endfunction

function! circuit#stage_and_send_ref(line1, line2) abort
  let s:staged_file_refs = []
  call circuit#stage_ref(a:line1, a:line2)
  call circuit#send_staged_ref()
endfunction

function! circuit#send_staged_ref() abort
  if empty(s:staged_file_refs)
    echo 'vim-circuit: no staged refs; use :CTref (see :help CTref)'
    return
  endif
  if !s:maybe_start('refsend')
    return
  endif
  call s:maybe_show('refsend')
  let l:text = join(s:staged_file_refs, "\n") . "\n"
  call term_sendkeys(s:term_bufnr, l:text)
  let s:staged_file_refs = []
  call circuit#hooks#fire('ChatRefSent')
  if bufwinid(s:term_bufnr) !=# -1
    call s:focus_term()
  endif
endfunction

" Expression mapping for |terminal| mode: send staged refs and Enter,
" or fall back to window right (|<C-w>|l).
function! circuit#terminal_c_l() abort
  if !empty(s:staged_file_refs) && s:term_alive()
    let l:text = join(s:staged_file_refs, "\n") . "\n"
    call term_sendkeys(s:term_bufnr, l:text)
    let s:staged_file_refs = []
    call circuit#hooks#fire('ChatRefSent')
    return ''
  endif
  return "\<C-\><C-n><C-w>l"
endfunction

function! circuit#clear_staged_refs() abort
  let s:staged_file_refs = []
  echo 'vim-circuit: staged refs cleared'
  call circuit#hooks#fire('ChatRefCleared')
endfunction

function! circuit#list_staged_refs() abort
  if empty(s:staged_file_refs)
    echo 'vim-circuit: no staged refs'
    return
  endif
  echo 'vim-circuit: staged refs (' . len(s:staged_file_refs) . '):'
  let l:i = 1
  for l:ref in s:staged_file_refs
    echo '  ' . l:i . '. ' . l:ref
    let l:i += 1
  endfor
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
  let l:save_win = win_getid()
  let l:save_view = winsaveview()
  let l:reloaded = 0
  for l:bufnr in range(1, bufnr('$'))
    if buflisted(l:bufnr) && l:bufnr != s:term_bufnr
          \ && getbufvar(l:bufnr, '&buftype') ==# ''
          \ && !empty(bufname(l:bufnr))
      let l:fname = fnamemodify(bufname(l:bufnr), ':p')
      if getftime(l:fname) > getbufvar(l:bufnr, 'circuit_mtime', 0)
        call setbufvar(l:bufnr, 'circuit_mtime', getftime(l:fname))
        if bufloaded(l:bufnr)
          silent! execute 'checktime ' . l:bufnr
          let l:reloaded = 1
        endif
      endif
    endif
  endfor
  if win_id2win(l:save_win) > 0
    noautocmd call win_gotoid(l:save_win)
    call winrestview(l:save_view)
  endif
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
          \ 'plan', 'fast', 'mode', 'position', 'send', 'chat',
          \ 'ref', 'refsend', 'refclear', 'reflist', 'model', 'verbose',
          \ 'doctor', 'version', 'undo', 'redo', 'export', 'stats',
          \ 'sessions', 'planopen', 'planexec', 'planclose',
          \ 'prompt']
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

" ---------------------------------------------------------------------------
" Floating command prompt (command palette)
" ---------------------------------------------------------------------------

let s:prompt_needs_arg = ['mode', 'model', 'position']

function! s:prompt_get_items(prefix) abort
  if empty(a:prefix)
    return circuit#complete('', 'CTerm ', 6)
  endif
  return circuit#complete('', 'CTerm ' . a:prefix . ' ', 6 + len(a:prefix) + 1)
endfunction

function! s:prompt_render() abort
  let l:prompt = empty(s:prompt_prefix)
        \ ? '> ' . s:prompt_text
        \ : s:prompt_prefix . '> ' . s:prompt_text
  let l:lines = [l:prompt]
  let l:props = []
  let l:i = 0
  for l:m in s:prompt_matches
    let l:line = '  ' . l:m
    if l:i ==# s:prompt_selected
      call add(l:props, #{
            \ line: len(l:lines) + 1,
            \ hl: 'PmenuSel',
            \ })
    endif
    call add(l:lines, l:line)
    let l:i += 1
  endfor
  if empty(s:prompt_matches)
    call add(l:lines, '  (no matches)')
  endif
  let s:prompt_props = l:props
  return l:lines
endfunction

function! s:prompt_apply_props() abort
  if s:prompt_winid < 1
    return
  endif
  let l:bufnr = winbufnr(s:prompt_winid)
  if l:bufnr < 1
    return
  endif
  for l:p in s:prompt_props
    call prop_type_add('CircuitSel', #{
          \ bufnr: l:bufnr,
          \ highlight: l:p.hl,
          \ override: 1,
          \ })
    let l:text = getbufline(l:bufnr, l:p.line)
    if !empty(l:text)
      call prop_add(l:p.line, 1, #{
            \ type: 'CircuitSel',
            \ length: len(l:text[0]),
            \ bufnr: l:bufnr,
            \ })
    endif
  endfor
endfunction

function! s:prompt_clear_props() abort
  if s:prompt_winid < 1
    return
  endif
  let l:bufnr = winbufnr(s:prompt_winid)
  if l:bufnr < 1
    return
  endif
  silent! call prop_type_delete('CircuitSel', #{bufnr: l:bufnr})
endfunction

function! s:fuzzy_match(str, pattern) abort
  let l:si = 0
  let l:pi = 0
  let l:slen = len(a:str)
  let l:plen = len(a:pattern)
  while l:si < l:slen && l:pi < l:plen
    if a:str[l:si] ==# a:pattern[l:pi]
      let l:pi += 1
    endif
    let l:si += 1
  endwhile
  return l:pi ==# l:plen
endfunction

function! s:prompt_update() abort
  let s:prompt_matches = s:prompt_get_items(s:prompt_prefix)
  if !empty(s:prompt_text)
    call filter(s:prompt_matches, 's:fuzzy_match(v:val, s:prompt_text)')
  endif
  if s:prompt_selected >= len(s:prompt_matches)
    let s:prompt_selected = max([0, len(s:prompt_matches) - 1])
  endif
  call s:prompt_clear_props()
  call popup_settext(s:prompt_winid, s:prompt_render())
  call s:prompt_apply_props()
endfunction

function! s:prompt_filter(winid, key) abort
  if a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
    call popup_close(a:winid, -1)
    return 1
  endif
  if a:key ==# "\<CR>"
    if !empty(s:prompt_matches)
      call popup_close(a:winid, s:prompt_selected + 1)
    else
      call popup_close(a:winid, -1)
    endif
    return 1
  endif
  if a:key ==# "\<Tab>" || a:key ==# "\<Down>" || a:key ==# "\<C-n>"
    if !empty(s:prompt_matches)
      let s:prompt_selected = (s:prompt_selected + 1) % len(s:prompt_matches)
      call s:prompt_clear_props()
      call popup_settext(a:winid, s:prompt_render())
      call s:prompt_apply_props()
    endif
    return 1
  endif
  if a:key ==# "\<S-Tab>" || a:key ==# "\<Up>" || a:key ==# "\<C-p>"
    if !empty(s:prompt_matches)
      let s:prompt_selected = (s:prompt_selected - 1 + len(s:prompt_matches))
            \ % len(s:prompt_matches)
      call s:prompt_clear_props()
      call popup_settext(a:winid, s:prompt_render())
      call s:prompt_apply_props()
    endif
    return 1
  endif
  if a:key ==# "\<BS>"
    if !empty(s:prompt_text)
      let s:prompt_text = s:prompt_text[:-2]
      let s:prompt_selected = 0
      call s:prompt_update()
    endif
    return 1
  endif
  if a:key ==# "\<C-u>"
    let s:prompt_text = ''
    let s:prompt_selected = 0
    call s:prompt_update()
    return 1
  endif
  if a:key =~# '^[[:print:]]$'
    let s:prompt_text .= a:key
    let s:prompt_selected = 0
    call s:prompt_update()
    return 1
  endif
  return 1
endfunction

function! s:prompt_callback(winid, result) abort
  let s:prompt_winid = -1
  if a:result <= 0 || empty(s:prompt_matches)
    return
  endif
  let l:cmd = s:prompt_matches[a:result - 1]
  if empty(s:prompt_prefix) && index(s:prompt_needs_arg, l:cmd) >= 0
    call s:prompt_open(l:cmd)
    return
  endif
  if !empty(s:prompt_prefix)
    execute 'CTerm ' . s:prompt_prefix . ' ' . l:cmd
  else
    execute 'CTerm ' . l:cmd
  endif
endfunction

function! s:prompt_open(prefix) abort
  let s:prompt_text = ''
  let s:prompt_selected = 0
  let s:prompt_prefix = a:prefix
  let s:prompt_matches = s:prompt_get_items(a:prefix)
  let s:prompt_winid = popup_create(s:prompt_render(), {
        \ 'filter': function('s:prompt_filter'),
        \ 'callback': function('s:prompt_callback'),
        \ 'title': ' Circuit ',
        \ 'minwidth': 35,
        \ 'maxwidth': 50,
        \ 'maxheight': 20,
        \ 'border': [],
        \ 'borderchars': ["\u2500", "\u2502", "\u2500", "\u2502",
        \   "\u256d", "\u256e", "\u256f", "\u2570"],
        \ 'borderhighlight': ['Comment'],
        \ 'highlight': 'Normal',
        \ 'padding': [0, 1, 0, 1],
        \ 'pos': 'center',
        \ 'zindex': 200,
        \ })
  call s:prompt_apply_props()
endfunction

function! circuit#prompt() abort
  if !has('popupwin')
    let l:cmd = input('CTerm> ', '', 'customlist,circuit#complete')
    if !empty(l:cmd)
      execute 'CTerm ' . l:cmd
    endif
    return
  endif
  call s:prompt_open('')
endfunction
