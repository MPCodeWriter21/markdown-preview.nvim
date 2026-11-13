let s:mkdp_root_dir = expand('<sfile>:h:h:h')
let s:pre_build = s:mkdp_root_dir . '/app/bin/markdown-preview-'
let s:package_file = s:mkdp_root_dir . '/package.json'

" echo message
function! mkdp#util#echo_messages(hl, msgs)
  if empty(a:msgs) | return | endif
  execute 'echohl '.a:hl
  if type(a:msgs) ==# 1
    echomsg a:msgs
  else
    for msg in a:msgs
      echom msg
    endfor
  endif
  echohl None
endfunction

" echo url
function! mkdp#util#echo_url(url)
  let l:url = 'Preview page: ' . a:url
  call mkdp#util#echo_messages('Type', l:url)
endfunction

" try open preview page
function! s:try_open_preview_page(timer_id) abort
  let l:server_status = mkdp#rpc#get_server_status()
  if l:server_status !=# 1
    let s:try_id = ''
    call mkdp#rpc#stop_server()
    call mkdp#rpc#start_server()
  endif
endfunction

" open preview page
function! mkdp#util#open_preview_page() abort
  if get(s:, 'try_id', '') !=# ''
    return
  endif
  let l:server_status = mkdp#rpc#get_server_status()
  if l:server_status ==# -1
    call mkdp#rpc#start_server()
  elseif l:server_status ==# 0
    let s:try_id = timer_start(1000, function('s:try_open_preview_page'))
  else
    call mkdp#util#open_browser()
  endif
endfunction

" auto refetch combine preview
function! mkdp#util#combine_preview_refresh() abort
  if g:mkdp_clients_active && !g:mkdp_auto_start
    call mkdp#util#open_browser()
  endif
endfunction

" open browser
function! mkdp#util#open_browser() abort
  call mkdp#rpc#open_browser()
  call mkdp#autocmd#init()
endfunction

function! mkdp#util#stop_preview() abort
  let g:mkdp_clients_active = 0
  " TODO: delete autocmd
  call mkdp#rpc#stop_server()
endfunction

function! mkdp#util#get_platform() abort
  if has('win32') || has('win64')
    return 'win'
  elseif has('mac') || has('macvim')
    if system('arch') =~? 'arm64'
      return 'macos-arm64'
    endif
    return 'macos'
  endif
  return 'linux'
endfunction

" javascript runtime used to run the server from source
" returns 'bun', 'node' or an empty string when no runtime is available
" the pre built binary does not need any javascript runtime
function! mkdp#util#get_runtime() abort
  let l:prefer = get(g:, 'mkdp_runtime', 'auto')
  if type(l:prefer) !=# v:t_string || l:prefer ==# ''
    let l:prefer = 'auto'
  endif
  let l:prefer = tolower(l:prefer)
  " a preferred runtime wins when it is installed
  if (l:prefer ==# 'bun' || l:prefer ==# 'node') && executable(l:prefer)
    return l:prefer
  endif
  " keep using node when it is available and fall back to bun
  if executable('node')
    return 'node'
  elseif executable('bun')
    return 'bun'
  endif
  return ''
endfunction

" version of the javascript runtime used to run the server from source
function! mkdp#util#runtime_version() abort
  let l:runtime = mkdp#util#get_runtime()
  if l:runtime ==# ''
    return ''
  endif
  return s:trim(system(l:runtime . ' --version'))
endfunction

" entry script used to run the server from source
function! mkdp#util#get_source_script() abort
  " bun can not run the vm based loader of app/index.js, it uses its own entry
  " point (app/bun.js) which requires the server directly
  if mkdp#util#get_runtime() ==# 'bun'
    return s:mkdp_root_dir . '/app/bun.js'
  endif
  return s:mkdp_root_dir . '/app/index.js'
endfunction

" the command used to run the server from source
" returns an empty list when no javascript runtime is available
function! mkdp#util#get_source_command() abort
  let l:runtime = mkdp#util#get_runtime()
  if l:runtime ==# ''
    return []
  endif
  return [l:runtime, mkdp#util#get_source_script(), '--path', s:mkdp_root_dir . '/app/server.js']
endfunction

" whether the dependencies needed to run the server from source are installed
" the modules can live in app/node_modules or in the node_modules of the plugin
function! mkdp#util#has_dependencies() abort
  let l:modules = ['@chemzqm/neovim', 'log4js', 'msgpack-lite', 'socket.io', 'tslib']
  for l:dir in ['/app/node_modules', '/node_modules']
    let l:missing = 0
    for l:module in l:modules
      if !isdirectory(s:mkdp_root_dir . l:dir . '/' . l:module)
        let l:missing = 1
        break
      endif
    endfor
    if !l:missing
      return 1
    endif
  endfor
  return 0
endfunction

" command used to install the dependencies needed to run the server from source
" bun is used when it is the selected runtime, otherwise yarn, npm and finally
" bun when it is the only package manager available
function! mkdp#util#get_install_command() abort
  if mkdp#util#get_runtime() ==# 'bun'
    return 'bun install'
  elseif executable('yarn')
    return 'yarn install'
  elseif executable('npm')
    return 'npm install'
  elseif executable('bun')
    return 'bun install'
  endif
  return ''
endfunction

function! s:on_exit(autoclose, bufnr, Callback, job_id, status, ...)
  let content = join(getbufline(a:bufnr, 1, '$'), "\n")
  if a:status == 0 && a:autoclose == 1
    execute 'silent! bd! '.a:bufnr
  endif
  if !empty(a:Callback)
    call call(a:Callback, [a:status, a:bufnr, content])
  endif
endfunction

function! mkdp#util#open_terminal(opts) abort
  if get(a:opts, 'position', 'bottom') ==# 'bottom'
    let p = '5new'
  else
    let p = 'vnew'
  endif
  execute 'belowright '.p.' +setl\ buftype=nofile '
  setl buftype=nofile
  setl winfixheight
  setl norelativenumber
  setl nonumber
  setl bufhidden=wipe
  let cmd = get(a:opts, 'cmd', '')
  let autoclose = get(a:opts, 'autoclose', 1)
  if empty(cmd)
    throw 'command required!'
  endif
  let cwd = get(a:opts, 'cwd', '')
  if !empty(cwd) | execute 'lcd '.cwd | endif
  let keepfocus = get(a:opts, 'keepfocus', 0)
  let bufnr = bufnr('%')
  let Callback = get(a:opts, 'Callback', v:null)
  if has('nvim')
    call termopen(cmd, {
          \ 'on_exit': function('s:on_exit', [autoclose, bufnr, Callback]),
          \})
  else
    call term_start(cmd, {
          \ 'exit_cb': function('s:on_exit', [autoclose, bufnr, Callback]),
          \ 'curwin': 1,
          \})
  endif
  if keepfocus
    wincmd p
  endif
  return bufnr
endfunction

function! s:markdown_preview_installed(status, ...) abort
  if a:status != 0
    call mkdp#util#echo_messages('Error', [
          \ '[markdown-preview]: install fail',
          \ 'when there is no pre built binary for your platform, install the dependencies and run the server from source:',
          \ '  :call mkdp#util#install_deps()',
          \ ])
    return
  endif
  echo '[markdown-preview.nvim]: install completed'
endfunction

function! s:trim(str) abort
  return substitute(a:str, '\v^(\s|\\n)*|(\s|\\n)*$', '', 'g')
endfunction

function! mkdp#util#install(...)
  let l:version = mkdp#util#pre_build_version()
  let l:info = json_decode(join(readfile(s:mkdp_root_dir . '/package.json'), ''))
  if s:trim(l:version) ==# s:trim(l:info.version)
    return
  endif
  let obj = json_decode(join(readfile(s:package_file)))
  let cmd = (mkdp#util#get_platform() ==# 'win' ? 'install.cmd' : './install.sh') . ' v'.obj['version']
  if get(a:, '1', v:false) ==# v:true
    execute 'lcd ' . s:mkdp_root_dir . '/app'
    execute '!' . cmd
  else
    call mkdp#util#open_terminal({
          \ 'cmd': cmd,
          \ 'cwd': s:mkdp_root_dir . '/app',
          \ 'Callback': function('s:markdown_preview_installed')
          \})
    wincmd p
  endif
endfunction

function! mkdp#util#install_sync(...)
  if get(a:, '1', v:false) ==# v:true
    silent call mkdp#util#install(v:true)
  else
    call mkdp#util#install(v:true)
  endif
endfunction

function! s:markdown_preview_deps_installed(status, ...) abort
  if a:status != 0
    call mkdp#util#echo_messages('Error', '[markdown-preview]: install dependencies fail')
    return
  endif
  echo '[markdown-preview.nvim]: install dependencies completed'
endfunction

" install the dependencies needed to run the server from source
" useful when no pre built binary is available for your platform, bun is used
" when it is the selected javascript runtime
function! mkdp#util#install_deps(...) abort
  let l:cmd = mkdp#util#get_install_command()
  if l:cmd ==# ''
    call mkdp#util#echo_messages('Error', [
          \ '[markdown-preview]: no javascript runtime or package manager found (bun, node, yarn, npm)',
          \ 'install bun from https://bun.sh or run :call mkdp#util#install() to download the pre built binary',
          \ ])
    return
  endif
  if get(a:, '1', v:false) ==# v:true
    execute 'lcd ' . s:mkdp_root_dir . '/app'
    execute '!' . l:cmd
  else
    call mkdp#util#open_terminal({
          \ 'cmd': l:cmd,
          \ 'cwd': s:mkdp_root_dir . '/app',
          \ 'Callback': function('s:markdown_preview_deps_installed')
          \})
    wincmd p
  endif
endfunction

function! mkdp#util#pre_build_version() abort
  let l:pre_build = s:pre_build . mkdp#util#get_platform()
  if has('win32') || has('win64')
    let l:pre_build .= '.exe'
  endif
  if filereadable(l:pre_build)
    let l:info = system(l:pre_build . ' --version')
    if l:info ==# ''
      call mkdp#util#echo_messages('Type', "[markdown-preview.nvim]: Can not execute pre build binary bundle to get version, will download latest pre build binary bundle")
      return ''
    endif
    let l:info = split(l:info, '\n')
    return l:info[0]
  endif
  return ''
endfunction

function! mkdp#util#toggle_preview() abort
    if !get(b:, 'MarkdownPreviewToggleBool')
        call mkdp#util#open_preview_page()
        let b:MarkdownPreviewToggleBool=1
    else
        call mkdp#util#stop_preview()
        let b:MarkdownPreviewToggleBool=0
    endif
endfunction

