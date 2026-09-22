vim.opt.rtp:prepend(vim.fn.getcwd())
local original=vim.fn.has
local notices={}
vim.notify=function(msg) notices[#notices+1]=msg end
for _,case in ipairs({{true,true},{false,false},{true,false},{false,true}}) do
 local nvim12,modern=case[1],case[2]
 vim.fn.has=function(name) if name=='nvim-0.12' then return nvim12 and 1 or 0 end return original(name) end
 local configured,installed,legacy=false,false,false
 package.loaded['nvim-treesitter']={setup=function() configured=true end}
 if modern then package.loaded['nvim-treesitter'].install=function(l) installed=vim.tbl_contains(l,'java') end end
 package.loaded['nvim-treesitter.configs']={setup=function(c) legacy=c.highlight.enable end}
 assert(pcall(dofile,'lua/plugins/treesitter.lua'))
 if modern then assert(configured and installed)
 elseif not nvim12 then assert(legacy)
 else assert(not legacy and not configured) end
end
package.loaded['nvim-treesitter']={setup=function() end,install=function() error('compiler missing') end}
assert(pcall(dofile,'lua/plugins/treesitter.lua'))
vim.wait(100,function() return #notices>=2 end)
assert(#notices>=2)
print('PASS matched/mismatched plugin APIs and failed installer do not abort startup')
vim.cmd('qa!')
