vim.opt.rtp:prepend(vim.fn.getcwd())
local M=require('plugins.java_launch')
local data=vim.fn.getcwd()..'/work/java-fixture'
local base=data..'/mason/packages/jdtls'
for _,p in ipairs({'plugins','config_win','config_linux','config_mac','config_linux_arm'}) do vim.fn.mkdir(base..'/'..p,'p') end
local jar=base..'/plugins/org.eclipse.equinox.launcher_1.jar'
vim.fn.writefile({},jar)
local function build(root,os,arch)
  local c,e=M.build(root,{data=data,os=os,arch=arch or 'x86_64',java=vim.v.progpath});assert(c,e);return c
end
local function arg(c,key) for i,v in ipairs(c.cmd) do if v==key then return c.cmd[i+1] end end end
local w=build('C:/projects/app','Windows_NT')
assert(arg(w,'-configuration')==base..'/config_win')
assert(arg(build('/projects/app','Linux'),'-configuration')==base..'/config_linux')
assert(arg(build('/projects/app','Darwin'),'-configuration')==base..'/config_mac')
assert(arg(build('/projects/app','Linux','aarch64'),'-configuration')==base..'/config_linux_arm')
assert(arg(w,'-data')~=arg(build('C:/other/app','Windows_NT'),'-data'),'workspace collision')
assert(arg(w,'-data')==arg(build('c:/PROJECTS/APP/','Windows_NT'),'-data'),'unstable Windows workspace')
assert(#w.init_options.bundles==0,'empty bundle entries')
assert(vim.fs.normalize(arg(w,'-jar'))==vim.fs.normalize(jar),'launcher path')
vim.fn.delete(jar)
local c,e=M.build('C:/projects/app',{data=data,os='Windows_NT',java=vim.v.progpath})
assert(not c and e:find('launcher'),'missing launcher must fail clearly')
print('PASS Windows/Linux/macOS/ARM config, isolated workspaces, valid launcher and no empty bundles')
vim.cmd('qa!')

