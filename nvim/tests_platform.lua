vim.opt.rtp:prepend(vim.fn.getcwd())
local runtime=require('wordvim.runtime')
for _,engine in ipairs({'powershell','pwsh'}) do
  if vim.fn.executable(engine)==1 then
    vim.g.wordvim_powershell=vim.fn.exepath(engine)
    local ok,out=runtime.run_powershell("[Console]::WriteLine('Привет / quoted '' value')\n#"..string.rep('x',50000))
    assert(ok and out:find("Привет / quoted ' value",1,true),out)
    local success,err=runtime.run_powershell("throw 'expected test error'")
    assert(not success and err:find('expected test error',1,true),'error swallowed')
    print('PASS '..engine..': UTF-8, long scripts, failure propagation')
  end
end
vim.g.wordvim_powershell=nil
require('core.platform').setup()
if runtime.windows() then
  local out=vim.fn.system('Write-Output "WordVim shell OK"')
  assert(vim.v.shell_error==0 and out:find('WordVim shell OK',1,true),'Windows shell configuration')
end
local p=require('wordvim.paragraphs')
local slash=string.char(92)
local input={'one'..slash,'two'..slash..slash,'```','code'..slash,'```','three  '}
local expected={'one  ','two'..slash..slash,'```','code'..slash,'```','three  '}
assert(vim.deep_equal(p.normalize_import(input),expected),'hard-break normalizer changed literals or code')
local has,executable,exepath=vim.fn.has,vim.fn.executable,vim.fn.exepath
vim.fn.has=function(name) if name=='win32' or name=='win64' then return 0 end;return has(name) end
vim.fn.executable=function(name) return ({pwsh=1,['termux-clipboard-set']=1,['termux-clipboard-get']=1,bash=1})[name] or 0 end
vim.fn.exepath=function(name) return '/usr/bin/'..name end
assert(runtime.powershell()=='/usr/bin/pwsh','Linux must use pwsh')
vim.g.clipboard=nil
require('core.platform').setup()
assert(vim.o.shell=='/usr/bin/bash','Linux shell must be available inside guest')
assert(vim.g.clipboard.name=='WordVim Termux','Termux API clipboard')
vim.fn.executable=function() return 0 end
assert(runtime.powershell()==nil,'missing pwsh should be detected')
local ok,msg=runtime.docx_ready();assert(not ok and msg:find('Pandoc'),'missing dependencies')
vim.fn.has,vim.fn.executable,vim.fn.exepath=has,executable,exepath
print('PASS simulated Linux/proot shell, pwsh selection, Termux provider and preflight')
vim.cmd('qa!')
