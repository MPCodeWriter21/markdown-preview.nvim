let s:mkdp_root_dir = expand('<sfile>:h:h:h')

function! health#mkdp#check() abort
  lua vim.health.info("Platform: " .. vim.fn['mkdp#util#get_platform']())
  lua vim.health.info('Nvim Version: ' .. string.gsub(vim.fn.system('nvim --version'), '^%s*(.-)%s*$', '%1'))
  let l:mkdp_server_script = s:mkdp_root_dir .. '/app/bin/markdown-preview-' .. mkdp#util#get_platform()
  if executable(l:mkdp_server_script)
    lua vim.health.info('Pre build: ' .. vim.api.nvim_eval('l:mkdp_server_script'))
    lua vim.health.info('Pre build version: ' .. vim.fn['mkdp#util#pre_build_version']())
    lua vim.health.ok('Using pre build')
    return
  endif
  lua vim.health.info('Pre build: not found')
  if mkdp#util#get_runtime() ==# ''
    lua vim.health.warn('Neither node nor bun found, run ":call mkdp#util#install()" to download the pre built binary or install bun from https://bun.sh')
    return
  endif
  lua vim.health.info('Runtime: ' .. vim.fn['mkdp#util#get_runtime']())
  lua vim.health.info('Runtime version: ' .. vim.fn['mkdp#util#runtime_version']())
  lua vim.health.info('Script: ' .. vim.fn['mkdp#util#get_source_script']())
  lua vim.health.info('Script exists: ' .. vim.fn.filereadable(vim.fn['mkdp#util#get_source_script']()))
  if !mkdp#util#has_dependencies()
    lua vim.health.warn('Dependencies are not installed, run ":call mkdp#util#install_deps()"')
    return
  endif
  lua vim.health.ok('Using ' .. vim.fn['mkdp#util#get_runtime']())
endfunction
