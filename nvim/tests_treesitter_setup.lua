vim.opt.rtp:prepend(vim.fn.getcwd())
local original=vim.fn.has
for _,modern in ipairs({true,false}) do
 vim.fn.has=function(name) if name=='nvim-0.12' then return modern and 1 or 0 end return original(name) end
 local configured,installed=false,false
 package.loaded['nvim-treesitter']={setup=function() configured=true end,install=function(l) installed=vim.tbl_contains(l,'java') end}
 package.loaded['nvim-treesitter.configs']={setup=function(c) configured=c.highlight.enable and c.auto_install end}
 dofile('lua/plugins/treesitter.lua')
 assert(configured and (not modern or installed))
end
print('PASS Tree-sitter 0.11 and 0.12 API selection')
vim.cmd('qa!')
