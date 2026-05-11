" vim-circuit: core functions
" Maintainer: inknos
" License: GPL-3.0

" ---------------------------------------------------------------------------
" Internal state
" ---------------------------------------------------------------------------
let s:term_bufnr = -1
let s:term_winid = -1
let s:reload_timer = -1
let s:current_model = ''
let s:autoread_save = 0
let s:autoread_armed = 0
let s:staged_file_refs = []
let s:just_started = 0
let s:server_job = -1
let s:server_port = 0

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

function! s:msg(text) abort
  echo 'vim-circuit: ' . a:text
endfunction

function! s:warn(text) abort
  echohl WarningMsg | echomsg 'vim-circuit: ' . a:text | echohl None
endfunction

function! s:err(text) abort
  echoerr 'vim-circuit: ' . a:text
endfunction

function! s:maybe_start(key) abort
  if s:term_alive()
    let s:just_started = 0
    return 1
  endif
  if !s:get_toggle('start_on', a:key)
    call s:warn('no active terminal')
    return 0
  endif
  call circuit#toggle()
  if s:term_alive()
    let s:just_started = 1
    return 1
  endif
  return 0
endfunction

function! s:sendkeys_cb(text, timer_id) abort
  if s:term_alive()
    call term_sendkeys(s:term_bufnr, a:text)
  endif
endfunction

function! s:term_sendkeys_safe(text) abort
  if s:just_started
    let s:just_started = 0
    let l:delay = s:get('sendkeys_delay', 200)
    call timer_start(l:delay, function('s:sendkeys_cb', [a:text]))
  else
    call term_sendkeys(s:term_bufnr, a:text)
  endif
endfunction

" Check if the TUI has rendered its prompt by scraping the terminal screen.
function! s:tui_ready() abort
  if !s:term_alive()
    return 0
  endif
  let l:rows = term_getsize(s:term_bufnr)[0]
  let l:row = l:rows
  while l:row > 0
    let l:cells = term_scrape(s:term_bufnr, l:row)
    let l:line = join(map(copy(l:cells), 'v:val.chars'), '')
    if l:line =~# '\(Ask anything\|┃\|╹\)'
      return 1
    endif
    let l:row -= 1
  endwhile
  return 0
endfunction

" Retry callback: wait for TUI to render, then POST /tui/append-prompt.
function! s:append_prompt_retry(ctx, timer_id) abort
  let a:ctx.tries += 1
  if s:tui_ready() && s:server_post('/tui/append-prompt', {'text': a:ctx.text})
    call timer_stop(a:timer_id)
    return
  endif
  if a:ctx.tries >= a:ctx.max_tries
    call timer_stop(a:timer_id)
    if s:term_alive()
      let s:just_started = 1
      call s:term_sendkeys_safe(a:ctx.text . "\n")
    endif
  endif
endfunction

" Start a fresh session with {text} pre-filled as the initial prompt.
" Opens the terminal via toggle(), waits for the TUI to render, then
" POSTs /tui/append-prompt.  Falls back to term_sendkeys on timeout.
function! s:start_with_prompt(text, key) abort
  call circuit#toggle()
  if !s:term_alive()
    return
  endif
  let l:clean = substitute(a:text, '\n\+$', '', '')
  if s:tui_ready() && s:server_post('/tui/append-prompt', {'text': l:clean})
    return
  endif
  let l:ctx = {'text': l:clean, 'tries': 0, 'max_tries': 15}
  call timer_start(200, function('s:append_prompt_retry', [l:ctx]),
        \ {'repeat': l:ctx.max_tries})
endfunction

" Deliver {text} to the agent via the best available channel for {key}.
" Server API > term_sendkeys > auto-start with prompt pre-fill.
" Returns 1 on success, 0 if auto-start is disabled and no terminal.
function! s:send_text(text, key) abort
  if s:server_running() && s:term_alive()
    call s:maybe_show(a:key)
    call s:server_submit_prompt(a:text)
  elseif s:term_alive()
    call s:maybe_show(a:key)
    call s:term_sendkeys_safe(a:text)
  else
    if !s:get_toggle('start_on', a:key)
      call s:warn('no active terminal')
      return 0
    endif
    call s:start_with_prompt(a:text, a:key)
    call s:maybe_show(a:key)
  endif
  return 1
endfunction

" Append {text} to the TUI prompt without submitting.
" Like s:send_text() but strips trailing newlines and skips submit.
function! s:append_text(text, key) abort
  let l:clean = substitute(a:text, '\n\+$', '', '')
  if s:server_running() && s:term_alive()
    call s:maybe_show(a:key)
    call s:server_append_prompt(l:clean)
  elseif s:term_alive()
    call s:maybe_show(a:key)
    call s:term_sendkeys_safe(l:clean)
  else
    if !s:get_toggle('start_on', a:key)
      call s:warn('no active terminal')
      return 0
    endif
    call s:start_with_prompt(a:text, a:key)
    call s:maybe_show(a:key)
  endif
  return 1
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

" Guard: verify that a provider is configured and that its {field} is
" non-empty.  Returns the provider dict on success, or {} when the
" feature is missing (after warning the user).
function! s:check_supported(field, label) abort
  if s:needs_provider()
    return {}
  endif
  let l:p = s:provider()
  if empty(l:p[a:field])
    call s:warn(a:label . ' not supported')
    return {}
  endif
  return l:p
endfunction

" Return the effective CLI binary: the user's b:/g:circuit_command
" override if set, otherwise the provider's default command.
function! s:resolve_bin() abort
  let l:override = s:get('command', '')
  return !empty(l:override) ? l:override : s:provider().command
endfunction

" Look up a provider slash command by {key} and send it to the running
" terminal, then fire {hook}.  Warns if the command is unsupported or
" no terminal is active.
function! s:send_slash_cmd(key, hook) abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  let l:cmd = get(l:p.slash_commands, a:key, '')
  if empty(l:cmd)
    call s:warn(a:key . ' not supported')
    return
  endif
  if s:server_running()
    if s:server_tui_cmd(a:key)
      call circuit#hooks#fire(a:hook)
    else
      call s:warn(a:key . ' failed (server returned error)')
    endif
    return
  endif
  if !s:term_alive()
    call s:warn('no active terminal')
    return
  endif
  call term_sendkeys(s:term_bufnr, l:cmd . "\n")
  call circuit#hooks#fire(a:hook)
endfunction

" Run a provider's CLI subcommand (e.g. doctor, stats) via system()
" and echo the output.  {provider_field} is the key in the provider
" dict holding the subcommand string; {label} is the human-readable
" feature name for the unsupported warning.
function! s:run_cli_cmd(provider_field, label) abort
  let l:p = s:check_supported(a:provider_field, a:label)
  if empty(l:p)
    return
  endif
  echo trim(system(s:resolve_bin() . ' ' . l:p[a:provider_field] . ' 2>&1'))
endfunction

function! s:show_setup_guide() abort
  call s:open_split()
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  let l:lines = [
        \ '  vim-circuit: opencode not found',
        \ '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
        \ '',
        \ '  Install opencode and make sure it is on $PATH.',
        \ '  https://github.com/opencode-ai/opencode',
        \ '',
        \ '  The CLI must be authenticated and functional.',
        \ '  Run `opencode` standalone first to verify.',
        \ '',
        \ '  Then reload Vim and run :CTerm',
        \ '',
        \ '  For details:  :help circuit',
        \ ]
  call setline(1, l:lines)
  setlocal nomodifiable
endfunction

function! s:build_cmd(...) abort
  let l:p = s:provider()
  let l:cmd = s:resolve_bin()
  call s:server_ensure()
  let l:url = s:server_url()
  if !empty(l:url)
    let l:cmd .= ' attach ' . l:url
  endif
  let l:extra = s:get('extra_args', '')

  let l:model = s:current_model
  if empty(l:model)
    let l:model = s:get('model', '')
  endif
  if !empty(l:model) && !empty(l:p.model_flag)
    let l:cmd .= ' ' . l:p.model_flag . ' ' . l:model
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

function! s:goto_term_tab() abort
  if s:term_bufnr ==# -1 || !bufexists(s:term_bufnr)
    return
  endif
  let l:winid = bufwinid(s:term_bufnr)
  if l:winid !=# -1
    call win_gotoid(l:winid)
    call s:focus_term()
    return
  endif
  for l:tab in range(1, tabpagenr('$'))
    for l:b in tabpagebuflist(l:tab)
      if l:b ==# s:term_bufnr
        execute 'tabnext ' . l:tab
        let l:winid = bufwinid(s:term_bufnr)
        if l:winid !=# -1
          call win_gotoid(l:winid)
        endif
        call s:focus_term()
        return
      endif
    endfor
  endfor
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
  call s:kill_term_if_alive()
  let l:cmd = s:resolve_bin() . ' ' . l:p.session_list_cmd
  call s:open_with_cmd(l:cmd)
  call circuit#hooks#fire('SessionChange')
endfunction

function! circuit#continue() abort
  if s:needs_provider()
    return
  endif
  call s:restart_session(s:provider().continue, 'SessionChange')
endfunction

function! circuit#new() abort
  if s:needs_provider()
    return
  endif
  call s:restart_session('', 'SessionChange')
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

" After the opencode process exits, close the split, wipe the buffer,
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

" Kill any running terminal, rebuild the CLI command with {extra}
" appended, open a fresh terminal split, and fire {hook} (if non-empty).
function! s:restart_session(extra, hook) abort
  call s:kill_term_if_alive()
  let l:cmd = s:build_cmd(a:extra)
  call s:open_with_cmd(l:cmd)
  if !empty(a:hook)
    call circuit#hooks#fire(a:hook)
  endif
endfunction

" Open a terminal split running {cmd}.  lcd to the project root, start
" the job, configure the window, arm autoread and the reload timer.
" Optional second arg overrides the hook name (default 'Open').
function! s:open_with_cmd(cmd, ...) abort
  let l:cwd = s:get('use_git_root', 1) ? s:git_root() : getcwd()

  let l:saved_dir = getcwd()
  execute 'lcd ' . fnameescape(l:cwd)
  call s:open_split()
  let l:opts = {'curwin': 1, 'term_finish': 'close'}
  call term_start(a:cmd, l:opts)
  execute 'lcd ' . fnameescape(l:saved_dir)
  let s:term_bufnr = bufnr('%')
  let s:term_winid = win_getid()

  call s:configure_term_window()
  call s:maybe_enable_autoread_for_session()
  call s:start_reload_timer()
  call circuit#hooks#fire(a:0 > 0 ? a:1 : 'Open')
  call s:focus_term()
endfunction

" ---------------------------------------------------------------------------
" Model switching
" ---------------------------------------------------------------------------

function! circuit#set_model(model) abort
  let l:p = s:check_supported('model_flag', 'model switching')
  if empty(l:p)
    return
  endif
  let s:current_model = a:model
  call s:restart_session(l:p.continue, '')
endfunction

" ---------------------------------------------------------------------------
" Send selection
" ---------------------------------------------------------------------------

function! circuit#send_selection(...) abort
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

  let l:fname = expand('%:t')
  let l:header = '# From ' . l:fname
  let l:text = l:header . "\n" . join(l:lines, "\n") . "\n"

  call s:send_text(l:text, 'send')
endfunction

" ---------------------------------------------------------------------------
" Chat (free-form prompt)
" ---------------------------------------------------------------------------

function! circuit#chat() abort
  let l:msg = input('circuit> ')
  if empty(l:msg)
    return
  endif

  let l:fname = expand('#:t')
  let l:context = ''
  if !empty(l:fname)
    let l:context = '(context: ' . l:fname . ') '
  endif
  let l:text = l:context . l:msg . "\n"

  call s:send_text(l:text, 'chat')
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
  call s:msg('staged ' . l:ref . ' (' . len(s:staged_file_refs) . ' pending)')
  call circuit#hooks#fire('ChatRefStaged')
endfunction

function! circuit#stage_and_send_ref(line1, line2) abort
  let s:staged_file_refs = []
  call circuit#stage_ref(a:line1, a:line2)
  call circuit#send_staged_ref()
endfunction

function! circuit#send_staged_ref() abort
  if empty(s:staged_file_refs)
    call s:warn('no staged refs; use :CTref (see :help CTref)')
    return
  endif
  let l:text = join(s:staged_file_refs, "\n") . "\n"
  if !s:append_text(l:text, 'refsend')
    return
  endif
  let s:staged_file_refs = []
  call circuit#hooks#fire('ChatRefSent')
  if s:get('refsend_switch_tab', 0)
    call s:goto_term_tab()
  elseif bufwinid(s:term_bufnr) !=# -1
    call win_gotoid(bufwinid(s:term_bufnr))
    call s:focus_term()
  endif
endfunction

" Expression mapping for |terminal| mode: append staged refs to prompt
" (without submitting), or fall back to window right (|<C-w>|l).
" When refs are staged but the terminal has exited, delegate to
" send_staged_ref which can auto-start a new session with --prompt.
function! circuit#terminal_c_l() abort
  if !empty(s:staged_file_refs)
    if s:term_alive()
      let l:text = join(s:staged_file_refs, "\n") . "\n"
      call s:append_text(l:text, 'refsend')
      let s:staged_file_refs = []
      call circuit#hooks#fire('ChatRefSent')
      return ''
    endif
    call circuit#send_staged_ref()
    return ''
  endif
  return "\<C-\><C-n><C-w>l"
endfunction

function! circuit#clear_staged_refs() abort
  let s:staged_file_refs = []
  call s:msg('staged refs cleared')
  call circuit#hooks#fire('ChatRefCleared')
endfunction

function! circuit#list_staged_refs() abort
  if empty(s:staged_file_refs)
    call s:msg('no staged refs')
    return
  endif
  call s:msg('staged refs (' . len(s:staged_file_refs) . '):')
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
    call s:err('invalid position "' . a:pos . '". Use right/left/top/bottom.')
    return
  endif
  let g:circuit_position = a:pos
  if s:term_alive() && bufwinid(s:term_bufnr) != -1
    call s:hide()
    call s:show()
  endif
endfunction

" ---------------------------------------------------------------------------
" Version
" ---------------------------------------------------------------------------

function! circuit#version() abort
  if s:needs_provider()
    return
  endif
  let l:p = s:provider()
  let l:cli_ver = trim(system(s:resolve_bin() . ' ' . l:p.version_flag . ' 2>&1'))
  echo 'vim-circuit:  0.2.0'
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
      call s:warn('buffers reloaded')
    endif
    call circuit#hooks#fire('Reload')
  endif
endfunction

" ---------------------------------------------------------------------------
" Undo / Redo
" ---------------------------------------------------------------------------

function! circuit#undo() abort
  call s:send_slash_cmd('undo', 'Undo')
endfunction

function! circuit#redo() abort
  call s:send_slash_cmd('redo', 'Redo')
endfunction

" ---------------------------------------------------------------------------
" Export
" ---------------------------------------------------------------------------

function! circuit#export() abort
  call s:send_slash_cmd('export', 'Export')
endfunction

" ---------------------------------------------------------------------------
" Stats
" ---------------------------------------------------------------------------

function! circuit#stats() abort
  call s:run_cli_cmd('stats_cmd', 'stats')
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
  let l:cmd = s:resolve_bin() . ' ' . l:p.session_list_cmd
  call s:open_with_cmd(l:cmd)
  call circuit#hooks#fire('SessionList')
endfunction

" ---------------------------------------------------------------------------
" Server API
" ---------------------------------------------------------------------------

function! s:server_url() abort
  if s:server_port > 0
    return 'http://127.0.0.1:' . s:server_port
  endif
  return ''
endfunction

function! s:server_on_stdout(ch, msg) abort
  let l:m = matchstr(a:msg, 'listening on http://[^:]\+:\zs\d\+')
  if !empty(l:m)
    let s:server_port = str2nr(l:m)
  endif
endfunction

function! s:server_running() abort
  return type(s:server_job) == v:t_job
        \ && job_status(s:server_job) ==# 'run'
endfunction

function! s:server_start() abort
  if s:server_running()
    return
  endif
  let l:bin = s:resolve_bin()
  let l:cmd = l:bin . ' serve --port 0'
  let l:opts = {
        \ 'out_cb': function('s:server_on_stdout'),
        \ 'err_io': 'null',
        \ 'stoponexit': 'term',
        \ }
  let s:server_port = 0
  let s:server_job = job_start(l:cmd, l:opts)
endfunction

function! s:server_stop() abort
  if s:server_running()
    call job_stop(s:server_job)
  endif
  let s:server_job = -1
  let s:server_port = 0
endfunction

" Start the server if not running and mode allows it.  Blocks briefly
" until the port is known (max ~2 s).
function! s:server_ensure() abort
  let l:mode = s:get('server_mode', 'lazy')
  if l:mode ==# 'manual'
    return
  endif
  if s:server_port > 0 && s:server_running()
    return
  endif
  if !s:server_running()
    call s:server_start()
  endif
  let l:tries = 0
  while s:server_port == 0 && l:tries < 20
    sleep 100m
    let l:tries += 1
  endwhile
endfunction

" Hit GET /global/health and return {'ok': 1/0, 'error': '...'}.
function! s:server_ping() abort
  let l:url = s:server_url()
  if empty(l:url)
    return {'ok': 0, 'error': 'server not running'}
  endif
  let l:out = trim(system('curl -s -o /dev/null -w "%{http_code}"'
        \ . ' ' . shellescape(l:url . '/global/health')))
  let l:err = v:shell_error
  if l:err || l:out !~# '^2'
    return {'ok': 0, 'error': 'server unreachable (HTTP ' . l:out . ')'}
  endif
  return {'ok': 1, 'error': ''}
endfunction

" POST JSON {body} to {path} on the managed server.
" Returns 1 when the server responds with "true", 0 otherwise.
function! s:server_post(path, body) abort
  let l:url = s:server_url()
  if empty(l:url)
    return 0
  endif
  let l:out = trim(system('curl -s -X POST -H "Content-Type: application/json"'
        \ . ' -d ' . shellescape(json_encode(a:body))
        \ . ' ' . shellescape(l:url . a:path)))
  return !v:shell_error && l:out ==# 'true'
endfunction

" Send a TUI command (e.g. 'undo', 'plan') via POST /tui/execute-command.
function! s:server_tui_cmd(command) abort
  return s:server_post('/tui/execute-command', {'command': a:command})
endfunction

" Clear the TUI prompt and append {text} without submitting.
function! s:server_append_prompt(text) abort
  call s:server_post('/tui/clear-prompt', {})
  return s:server_post('/tui/append-prompt', {'text': a:text})
endfunction

" Clear the TUI prompt, append {text}, and submit it.
function! s:server_submit_prompt(text) abort
  call s:server_post('/tui/clear-prompt', {})
  if !s:server_post('/tui/append-prompt', {'text': a:text})
    return 0
  endif
  return s:server_post('/tui/submit-prompt', {})
endfunction

function! circuit#server_start() abort
  if s:server_running()
    call s:msg('server already running (' . s:server_url() . ')')
    return
  endif
  call s:server_start()
  let l:tries = 0
  while s:server_port == 0 && l:tries < 20
    sleep 100m
    let l:tries += 1
  endwhile
  if s:server_port > 0
    call s:msg('server started (' . s:server_url() . ')')
  else
    call s:warn('server failed to start')
  endif
endfunction

function! circuit#server_stop() abort
  call s:server_stop()
endfunction

function! circuit#ping() abort
  let l:was_running = s:server_running()
  call s:server_ensure()
  if !l:was_running && s:server_port > 0
    call s:msg('started server at ' . s:server_url())
  endif
  let l:result = s:server_ping()
  if l:result.ok
    call s:msg('server OK (' . s:server_url() . ')')
  else
    call s:warn(l:result.error)
  endif
endfunction

" ---------------------------------------------------------------------------
" TUI pickers (server-only)
" ---------------------------------------------------------------------------

function! circuit#pick_session() abort
  call s:server_ensure()
  if !s:server_running()
    call s:warn('server not running')
    return
  endif
  if !s:server_post('/tui/open-sessions', {})
    call s:warn('failed to open sessions picker')
  endif
endfunction

function! circuit#pick_model() abort
  call s:server_ensure()
  if !s:server_running()
    call s:warn('server not running')
    return
  endif
  if !s:server_post('/tui/open-models', {})
    call s:warn('failed to open models picker')
  endif
endfunction

" ---------------------------------------------------------------------------
" Tab-completion helper
" ---------------------------------------------------------------------------

function! circuit#complete(arglead, cmdline, cursorpos) abort
  let l:parts = split(a:cmdline, '\s\+')
  let l:nparts = len(l:parts)

  if l:nparts <= 2
    let l:subs = ['resume', 'continue', 'new', 'kill',
          \ 'position', 'send', 'chat',
          \ 'ref', 'refsend', 'refclear', 'reflist', 'model',
          \ 'version', 'undo', 'redo', 'export', 'stats',
          \ 'sessions', 'prompt', 'ping', 'serve', 'pick', 'models']
    return filter(copy(l:subs), 'v:val =~# "^" . a:arglead')
  endif

  let l:sub = l:parts[1]
  let l:cur = circuit#providers#current()
  if l:sub ==# 'model'
    let l:models = empty(l:cur) ? [] : l:cur.models
    return filter(copy(l:models), 'v:val =~# "^" . a:arglead')
  elseif l:sub ==# 'position'
    let l:positions = ['right', 'left', 'top', 'bottom']
    return filter(copy(l:positions), 'v:val =~# "^" . a:arglead')
  endif

  return []
endfunction

function! circuit#prompt() abort
  call circuit#prompt#open()
endfunction
