vim.opt.rtp:prepend(vim.fn.getcwd())
vim.g.mapleader = ' '
local connected, calls, notice = false, 0, ''
vim.lsp.get_clients = function() return connected and {{name='jdtls'}} or {} end
vim.notify = function(msg) notice=msg end
vim.lsp.buf.rename = function() calls=calls+1 end
package.loaded['jdtls.setup'] = {find_root=function() return 'project' end}
package.loaded['plugins.java_launch'] = {build=function() return nil, 'missing launcher' end}
dofile('ftplugin/java.lua')
local b=vim.api.nvim_get_current_buf()
local m=vim.fn.maparg(' jr','n',false,true)
assert(type(m.callback)=='function','Java map missing after failed launch')
m.callback(); assert(calls==0 and notice:find('missing launcher',1,true))
assert(vim.fn.exists(':WordJavaStatus')==2)
connected=true
require('plugins.java').on_attach({},b)
vim.fn.maparg(' jr','n',false,true).callback(); assert(calls==1)
assert(vim.b.wordvim_java_error==nil)
for _,key in ipairs({' ja',' jc',' je',' jt',' jm',' ji',' jg','gi','gt',' ju',' tt',' tn'}) do
 assert(vim.fn.maparg(key,'n',false,true).buffer==1,key)
end
vim.cmd('enew')
assert(vim.fn.maparg(' jr','n')=='','Java map leaked')
package.loaded['jdtls.setup'] = {find_root=function() return nil end}
local fallback
package.loaded['plugins.java_launch']={build=function(root) fallback=root; return {} end}
package.loaded['cmp_nvim_lsp']={default_capabilities=function() return {} end}
package.loaded['jdtls']={start_or_attach=function() error('startup failure') end}
vim.api.nvim_buf_set_name(0,vim.fn.getcwd()..'/work/Standalone.java')
dofile('ftplugin/java.lua')
assert(fallback and fallback:find('work'))
assert(vim.fn.maparg(' jr','n',false,true).buffer==1)
assert(vim.b.wordvim_java_error:find('startup failure'))
print('Java mappings: PASS (failed launch, attach, buffer isolation, standalone file)')
vim.cmd('qa!')
