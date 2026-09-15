vim.opt.rtp:prepend(vim.fn.getcwd())
local M=require('plugins.java_launch')
local root=vim.fn.getcwd()..'/work/shared-mason'
vim.fn.mkdir(root..'/share/jdtls/config','p')
vim.fn.mkdir(root..'/share/jdtls/plugins','p')
vim.fn.writefile({},root..'/share/jdtls/plugins/org.eclipse.equinox.launcher.jar')
local function arg(c,k) for i,v in ipairs(c.cmd) do if v==k then return c.cmd[i+1] end end end
for _,os in ipairs({'Windows_NT','Linux'}) do
 local c,e=M.build('project',{mason_root=root,os=os,java=vim.v.progpath})
 assert(c,e)
 assert(arg(c,'-configuration')==root..'/share/jdtls/config')
 assert(arg(c,'-jar')==root..'/share/jdtls/plugins/org.eclipse.equinox.launcher.jar')
end
package.loaded['mason.settings']={current={install_root_dir=root}}
assert(M.build('project',{java=vim.v.progpath}))
local c,e=M.build('project',{mason_root=root..'/absent',java=vim.v.progpath})
assert(not c and e:find('MasonInstall jdtls'))
-- Reproduce FileType -> error notification propagation while opening a file.
package.loaded['jdtls.setup']={find_root=function() return 'project' end}
package.loaded['plugins.java_launch']={build=function() return nil,'missing config' end}
local notified=false
vim.notify=function(msg,level) assert(level~=vim.log.levels.ERROR); notified=true end
vim.api.nvim_create_autocmd('BufReadPost',{pattern='*.java',callback=function() dofile('ftplugin/java.lua') end})
vim.fn.writefile({'class Test {}'},root..'/Test.java')
assert(pcall(vim.cmd,'edit '..vim.fn.fnameescape(root..'/Test.java')))
assert(vim.fn.maparg('\\jr','n')~='')
assert(vim.wait(500,function() return notified end))
print('PASS shared Mason layout, custom root, missing install, file opening despite Java failure')
vim.cmd('qa!')
