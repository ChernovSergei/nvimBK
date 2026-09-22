-- Shared external-process boundary for Windows, Linux and glibc proot guests.
local M = {}
function M.windows() return vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 end
function M.powershell()
  if vim.g.wordvim_powershell then return vim.g.wordvim_powershell end
  for _,name in ipairs(M.windows() and {'powershell','pwsh'} or {'pwsh'}) do
    if vim.fn.executable(name)==1 then return vim.fn.exepath(name) end
  end
end
function M.run_powershell(script, sta)
  local shell=M.powershell()
  if not shell or vim.fn.executable(shell)~=1 then
    return false,'DOCX requires '..(M.windows() and 'Windows PowerShell or PowerShell 7' or 'PowerShell 7 (pwsh) inside this Linux/proot distribution')..'. Run :WordHealth.'
  end
  -- -File avoids Windows command-line limits and shell quoting of document text.
  local file=vim.fn.tempname()..'.ps1'
  local preamble="$ErrorActionPreference = 'Stop'\n[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)\n$OutputEncoding = [Console]::OutputEncoding\n"
  local lines=vim.split('\239\187\191'..preamble..script,'\n',{plain=true})
  local wrote,err=pcall(vim.fn.writefile,lines,file)
  if not wrote or err~=0 then vim.fn.delete(file);return false,'Cannot write PowerShell script: '..tostring(err) end
  local args={shell,'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass'}
  if sta and M.windows() then args[#args+1]='-STA' end
  vim.list_extend(args,{'-File',file})
  local ok,out=pcall(vim.fn.system,args)
  local status=vim.v.shell_error
  vim.fn.delete(file)
  return ok and status==0,tostring(out)
end
function M.python()
  if vim.g.wordvim_python then return vim.g.wordvim_python end
  for _,name in ipairs({'python3','python'}) do
    if vim.fn.executable(name)==1 then return vim.fn.exepath(name) end
  end
end
function M.rotate_image(source,target,angle)
  if M.windows() and not vim.g.wordvim_python then
    local rotation=({[90]='Rotate90FlipNone',[180]='Rotate180FlipNone',[270]='Rotate270FlipNone'})[angle]
    if not rotation then return false,'Rotation must be 90, 180 or 270' end
    local function quote(v) return "'"..v:gsub("'","''").."'" end
    return M.run_powershell("Add-Type -AssemblyName System.Drawing\n"
      .. "$image=[System.Drawing.Image]::FromFile("..quote(source)..")\n"
      .. "try {$image.RotateFlip([System.Drawing.RotateFlipType]::"..rotation.."); $image.Save("..quote(target)..")} finally {$image.Dispose()}")
  end
  local python=M.python()
  if not python then return false,'Image rotation requires Python 3 and Pillow. Run :WordHealth.' end
  local code='import sys; from PIL import Image; im=Image.open(sys.argv[1]); im.rotate(-int(sys.argv[3]), expand=True).save(sys.argv[2]); im.close()'
  local ok,out=pcall(vim.fn.system,{python,'-c',code,source,target,tostring(angle)})
  return ok and vim.v.shell_error==0,tostring(out)
end
function M.docx_ready()
  if vim.fn.executable('pandoc')~=1 then return false,'Pandoc is missing in this environment. Run :WordHealth.' end
  local shell=M.powershell()
  if not shell or vim.fn.executable(shell)~=1 then return false,'DOCX XML processing requires PowerShell (Windows) or pwsh (Linux/proot). Run :WordHealth.' end
  return true
end
function M.health()
  local lines={'WordVim environment', 'OS: '..(vim.uv or vim.loop).os_uname().sysname..' / '..(vim.uv or vim.loop).os_uname().machine}
  for _,name in ipairs({'nvim','git','pandoc','java','node','npm','rg','cc','termux-clipboard-get','termux-clipboard-set','wl-copy','xclip'}) do
    lines[#lines+1]=name..': '..(vim.fn.executable(name)==1 and vim.fn.exepath(name) or 'not found')
  end
  lines[#lines+1]='DOCX PowerShell: '..(M.powershell() or 'not found (install pwsh in Linux/proot)')
  local python=M.python()
  lines[#lines+1]='Image Python: '..(python or 'not found')
  if python then
    local out=vim.fn.system({python,'-c','import PIL; print(PIL.__version__)'})
    lines[#lines+1]='Pillow: '..(vim.v.shell_error==0 and vim.trim(out) or 'not available')
  end
  lines[#lines+1]='Clipboard: '..tostring(vim.fn['provider#clipboard#Executable']())
  lines[#lines+1]='JDTLS: '..vim.fn.stdpath('data')..'/mason/packages/jdtls'
  vim.cmd('new')
  vim.bo.buftype='nofile';vim.bo.bufhidden='wipe';vim.bo.swapfile=false
  vim.api.nvim_buf_set_lines(0,0,-1,false,lines);vim.bo.modifiable=false
end
return M

