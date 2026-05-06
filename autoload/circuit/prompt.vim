" vim-circuit: floating command palette (popup-based fuzzy prompt)
" Maintainer: inknos
" License: GPL-3.0

" ---------------------------------------------------------------------------
" Internal state
" ---------------------------------------------------------------------------
let s:prompt_winid = -1
let s:prompt_text = ''
let s:prompt_matches = []
let s:prompt_selected = 0
let s:prompt_prefix = ''
let s:prompt_props = []
let s:prompt_needs_arg = ['mode', 'model', 'position']

" ---------------------------------------------------------------------------
" Helpers
" ---------------------------------------------------------------------------

function! s:get_items(prefix) abort
  if empty(a:prefix)
    return circuit#complete('', 'CTerm ', 6)
  endif
  return circuit#complete('', 'CTerm ' . a:prefix . ' ', 6 + len(a:prefix) + 1)
endfunction

function! s:render() abort
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

function! s:apply_props() abort
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

function! s:clear_props() abort
  if s:prompt_winid < 1
    return
  endif
  let l:bufnr = winbufnr(s:prompt_winid)
  if l:bufnr < 1
    return
  endif
  silent! call prop_type_delete('CircuitSel', #{bufnr: l:bufnr})
endfunction

" Re-render the floating prompt popup: clear highlight props, update
" the popup text, and re-apply selection highlighting.
function! s:refresh() abort
  call s:clear_props()
  call popup_settext(s:prompt_winid, s:render())
  call s:apply_props()
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

function! s:update() abort
  let s:prompt_matches = s:get_items(s:prompt_prefix)
  if !empty(s:prompt_text)
    call filter(s:prompt_matches, 's:fuzzy_match(v:val, s:prompt_text)')
  endif
  if s:prompt_selected >= len(s:prompt_matches)
    let s:prompt_selected = max([0, len(s:prompt_matches) - 1])
  endif
  call s:refresh()
endfunction

" ---------------------------------------------------------------------------
" Popup filter and callback
" ---------------------------------------------------------------------------

function! s:filter(winid, key) abort
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
      call s:refresh()
    endif
    return 1
  endif
  if a:key ==# "\<S-Tab>" || a:key ==# "\<Up>" || a:key ==# "\<C-p>"
    if !empty(s:prompt_matches)
      let s:prompt_selected = (s:prompt_selected - 1 + len(s:prompt_matches))
            \ % len(s:prompt_matches)
      call s:refresh()
    endif
    return 1
  endif
  if a:key ==# "\<BS>"
    if !empty(s:prompt_text)
      let s:prompt_text = s:prompt_text[:-2]
      let s:prompt_selected = 0
      call s:update()
    endif
    return 1
  endif
  if a:key ==# "\<C-u>"
    let s:prompt_text = ''
    let s:prompt_selected = 0
    call s:update()
    return 1
  endif
  if a:key =~# '^[[:print:]]$'
    let s:prompt_text .= a:key
    let s:prompt_selected = 0
    call s:update()
    return 1
  endif
  return 1
endfunction

function! s:callback(winid, result) abort
  let s:prompt_winid = -1
  if a:result <= 0 || empty(s:prompt_matches)
    return
  endif
  let l:cmd = s:prompt_matches[a:result - 1]
  if empty(s:prompt_prefix) && index(s:prompt_needs_arg, l:cmd) >= 0
    call s:popup_open(l:cmd)
    return
  endif
  if !empty(s:prompt_prefix)
    execute 'CTerm ' . s:prompt_prefix . ' ' . l:cmd
  else
    execute 'CTerm ' . l:cmd
  endif
endfunction

" ---------------------------------------------------------------------------
" Public API
" ---------------------------------------------------------------------------

function! s:popup_open(prefix) abort
  let s:prompt_text = ''
  let s:prompt_selected = 0
  let s:prompt_prefix = a:prefix
  let s:prompt_matches = s:get_items(a:prefix)
  let s:prompt_winid = popup_create(s:render(), {
        \ 'filter': function('s:filter'),
        \ 'callback': function('s:callback'),
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
  call s:apply_props()
endfunction

" Open the floating command palette, or fall back to input() when
" Vim lacks +popupwin.
function! circuit#prompt#open() abort
  if !has('popupwin')
    let l:cmd = input('CTerm> ', '', 'customlist,circuit#complete')
    if !empty(l:cmd)
      execute 'CTerm ' . l:cmd
    endif
    return
  endif
  call s:popup_open('')
endfunction
