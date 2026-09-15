vim.opt.rtp:prepend(vim.fn.getcwd())
local nav=require('plugins.java_navigation')
local uri='jdt://contents/spring.jar/org.example/Main.class?x=C%5CUsers%5CLeo#part|x'
local loc={uri=uri,range={start={line=0,character=0},['end']={line=0,character=1}}}
local results={[1]={result={loc}}}
vim.lsp.get_client_by_id=function() return {offset_encoding='utf-16'} end
vim.lsp.buf_request_all=function(_,method,_,cb) cb(results) end
vim.api.nvim_create_autocmd('BufReadCmd',{pattern='jdt://*',callback=function(a)
 assert(vim.api.nvim_buf_get_name(a.buf)==uri)
 vim.api.nvim_buf_set_lines(a.buf,0,-1,false,{'class Main {}'})
end})
vim.api.nvim_buf_set_lines(0,0,-1,false,{"Main"})
local source=vim.api.nvim_get_current_win()
nav.implementation()
assert(#vim.api.nvim_list_tabpages()==2)
assert(vim.api.nvim_get_current_win()~=source)
assert(vim.api.nvim_buf_get_name(0)==uri)
vim.cmd('tabclose')
results={[1]={result={loc,loc}}}
vim.ui.select=function(items,_,cb) cb(nil) end
nav.implementation(); assert(#vim.api.nvim_list_tabpages()==1)
vim.ui.select=function(items,_,cb) cb(items[2]) end
nav.implementation(); assert(#vim.api.nvim_list_tabpages()==2)
vim.cmd('tabclose')
results={[1]={result={loc}}}
local picked=false
vim.ui.select=function(items,_,cb) picked=true; cb(items[1]) end
package.loaded['plugins.java_usages']={open=function(items,_,cb) picked=true; cb(items[1]) end}
nav.references(); assert(picked and #vim.api.nvim_list_tabpages()==2)
print('PASS real URI buffer opening, special characters, split, multiple results and cancel')
vim.cmd('qa!')



