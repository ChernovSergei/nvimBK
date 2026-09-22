local languages={'lua','java','html','css','javascript','typescript','tsx','json','bash','yaml','markdown','markdown_inline'}
local group=vim.api.nvim_create_augroup('WordVimTreesitter',{clear=true})
local function warn(message)
  vim.schedule(function() vim.notify('WordVim Tree-sitter: '..message,vim.log.levels.WARN) end)
end
local function native_highlighting()
  local function start(buf)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype~='' then
      pcall(vim.treesitter.start,buf)
    end
  end
  vim.api.nvim_create_autocmd({'FileType','BufWinEnter'}, {group=group,callback=function(args) start(args.buf) end})
  start(vim.api.nvim_get_current_buf())
end
-- Installed plugin code can lag behind the branch selected by lazy.nvim.
-- Inspect its API before using it; version checks alone cannot identify it.
local ok,ts=pcall(require,'nvim-treesitter')
if ok and type(ts.install)=='function' and type(ts.setup)=='function' then
  native_highlighting()
  local configured,err=pcall(ts.setup,{})
  if configured then
    local installed,install_err=pcall(ts.install,languages)
    if not installed then warn(tostring(install_err)..'; run :checkhealth nvim-treesitter and :TSUpdate') end
  else warn(tostring(err)..'; run :Lazy sync and restart Neovim') end
elseif vim.fn.has('nvim-0.12')==0 then
  local legacy,configs=pcall(require,'nvim-treesitter.configs')
  local configured,err=false,'Compatible plugin not installed'
  if legacy and type(configs.setup)=='function' then
    configured,err=pcall(configs.setup,{
      ensure_installed=languages,sync_install=false,auto_install=true,highlight={enable=true},
    })
  end
  if not configured then native_highlighting(); warn(tostring(err)..'; run :Lazy sync and restart Neovim') end
else
  -- Old master modules are not supported by Neovim 0.12. Keep startup working
  -- while lazy.nvim updates the checkout; use already available native parsers.
  native_highlighting()
  warn('Installed plugin has no modern install API. Run :Lazy sync, restart Neovim, then :TSUpdate. Using available native parsers meanwhile.')
end
