local languages={'lua','java','html','css','javascript','typescript','tsx','json','bash','yaml','markdown','markdown_inline'}
if vim.fn.has('nvim-0.12')==1 then
  local ts=require('nvim-treesitter')
  ts.setup({})
  ts.install(languages)
  local group=vim.api.nvim_create_augroup('WordVimTreesitter',{clear=true})
  vim.api.nvim_create_autocmd('FileType',{group=group,callback=function(args)
    -- Parsers may still be downloading on the first launch.
    pcall(vim.treesitter.start,args.buf)
  end})
else
  require('nvim-treesitter.configs').setup({
    ensure_installed=languages,sync_install=false,auto_install=true,
    highlight={enable=true},
  })
end
