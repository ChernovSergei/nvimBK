local M={}
function M.setup()
  local windows=vim.fn.has('win32')==1
  if windows then
    local shell=vim.fn.executable('pwsh')==1 and vim.fn.exepath('pwsh') or vim.fn.exepath('powershell')
    if shell~='' then
      vim.o.shell=shell
      vim.o.shellcmdflag='-NoLogo -NoProfile -NonInteractive -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();'
      vim.o.shellredir='2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode'
      vim.o.shellpipe='2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode'
      vim.o.shellquote='';vim.o.shellxquote=''
    end
  else
    -- Resolve the executable actually installed inside this distribution.
    local preferred=vim.env.SHELL
    if preferred and preferred~='' and vim.fn.executable(preferred)==1 then vim.o.shell=preferred
    else
      for _,name in ipairs({'bash','sh'}) do
        if vim.fn.executable(name)==1 then vim.o.shell=vim.fn.exepath(name);break end
      end
    end
    vim.o.shellcmdflag='-c';vim.o.shellredir='>%s 2>&1';vim.o.shellpipe='2>&1| tee %s'
    vim.o.shellquote='';vim.o.shellxquote=''
  end
  -- Neovim handles desktop clipboard providers. Prefer the Android API when
  -- proot exposes Termux executables and no user clipboard is configured.
  if not windows and vim.g.clipboard==nil and vim.fn.executable('termux-clipboard-set')==1 and vim.fn.executable('termux-clipboard-get')==1 then
    vim.g.clipboard={name='WordVim Termux',copy={['+']={'termux-clipboard-set'},['*']={'termux-clipboard-set'}},paste={['+']={'termux-clipboard-get'},['*']={'termux-clipboard-get'}},cache_enabled=0}
  end
  vim.api.nvim_create_user_command('WordHealth',function() require('wordvim.runtime').health() end,{desc='Check platform and WordVim dependencies'})
end
return M
