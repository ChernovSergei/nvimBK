-- Exercise the terminal decoder with raw bytes, not nvim_input('<S-CR>').
local pipe=vim.fn.has('win32')==1 and ('\\\\.\\pipe\\wordvim-key-test-'..vim.fn.getpid()) or vim.fn.tempname()
vim.fn.mkdir('work','p');vim.env.NVIM_LOG_FILE=vim.fn.getcwd()..'/work/terminal-keys.log'
local job=vim.fn.termopen({'nvim','-n','-u','NONE','-i','NONE','--listen',pipe})
local channel
assert(vim.wait(5000,function()
  local ok,id=pcall(vim.fn.sockconnect,'pipe',pipe,{rpc=true})
  if ok and id>0 then channel=id;return true end
end,100),'Child terminal did not start')
local function lua(code) return vim.rpcrequest(channel,'nvim_exec_lua',code,{}) end
local function send(bytes) vim.fn.chansend(job,bytes);vim.wait(200) end
local ok,err=pcall(function()
  -- Initialize TUI logging before measuring keys (restricted test accounts
  -- can display a one-time log-path warning).
  send('\27[13;2u');send('\r');send('\27')
  lua('vim.opt.rtp:prepend('..vim.inspect(vim.fn.getcwd())..');vim.b.docx_original_file="test.docx";vim.b.wordvim_docx=true;require("wordvim.paragraphs").attach(0);vim.bo.autoindent=true;vim.cmd("startinsert")')
  send('First line')
  send('\27[13;2u') -- CSI-u: Shift+Enter; sent by the Windows Terminal patch.
  send('Second line')
  send('\r')
  send('New real paragraph.')
  send('\27')
  local lines=lua('return vim.api.nvim_buf_get_lines(0,0,-1,false)')
  assert(vim.deep_equal(lines,{'First line  ','Second line','New real paragraph.'}),vim.inspect(lines))
  local styles=lua('local s=require("wordvim.styles");s.ensure_explicit_styles(0);return {s.get_paragraph_style(0,0),s.get_paragraph_style(0,1)==nil,s.get_paragraph_style(0,2)}')
  assert(styles[1]=='Normal' and styles[2] and styles[3]=='Normal',vim.inspect(styles))
  print('PASS raw terminal CSI-u Shift+Enter vs ordinary Enter; separate paragraph metadata')
end)
vim.fn.jobstop(job)
assert(ok,err)
vim.cmd('qa!')


