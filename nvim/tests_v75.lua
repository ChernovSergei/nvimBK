local ch=vim.fn.jobstart({vim.v.progpath,'--headless','-u','NONE','-i','NONE','--embed'},{rpc=true})
local function lua(code,...)return vim.rpcrequest(ch,'nvim_exec_lua',code,{...})end
lua([=[
vim.o.swapfile=false;vim.opt.rtp:prepend(...);vim.g.mapleader=' ';vim.o.timeoutlen=300;vim.o.columns=140;vim.o.lines=45
vim.b.wordvim_docx=true;vim.b.docx_original_file='test.docx';vim.bo.filetype='markdown'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'# Before','','after'})
_G.source=vim.api.nvim_get_current_buf();_G.sourcewin=vim.api.nvim_get_current_win()
require('wordvim.styleui').setup();require('wordvim.styleui').open(source,'both')
for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype=='wordvimstyles' then _G.right=w;_G.rightbuf=vim.api.nvim_win_get_buf(w) end end
require('wordvim.tables').open(3,2)
_G.editor=vim.api.nvim_get_current_buf()
assert(vim.api.nvim_win_get_config(sourcewin).relative=='')
assert(vim.api.nvim_win_get_buf(right)==rightbuf,'existing styles window not reused')
assert(vim.api.nvim_win_get_config(right).relative=='')
]=],vim.fn.getcwd())
local function input(keys)vim.rpcrequest(ch,'nvim_input',keys);vim.wait(150)end
input('5j.')
lua([[local lines=vim.api.nvim_buf_get_lines(editor,0,-1,false);assert(lines[4]:find('5',1,true) and lines[6]:find('5',1,true),vim.inspect(lines));assert(vim.v.errmsg=='',vim.v.errmsg)]])
input(' ');vim.wait(30);input('wr')
lua([[assert(not vim.api.nvim_win_is_valid(right),'wr did not close panel')]])
input(' wr')
lua([[for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype=='wordvimstyles' then _G.right=w end end;assert(vim.api.nvim_win_is_valid(right))]])
input('<C-w>l');input('jj<CR>')
lua([[assert(vim.api.nvim_get_current_buf()==editor);local line=vim.api.nvim_get_current_line();local col=vim.api.nvim_win_get_cursor(0)[2];assert(line:sub(col+1,col+1):match('%d'))]])
input('<C-w>l');input(' wr')
lua([[assert(vim.api.nvim_get_current_buf()==editor)]]);input(' wr')
lua([[vim.api.nvim_win_set_cursor(sourcewin,{5,10})]])
vim.wait(150)
lua([[local p=vim.api.nvim_win_get_cursor(sourcewin);assert(p[1]==4 or p[1]==6,vim.inspect(p))]])
input('W')
lua([[assert(vim.api.nvim_get_current_buf()==source);assert(vim.bo.filetype=='markdown');assert(vim.api.nvim_buf_get_lines(source,0,1,false)[1]=='# Before');assert(vim.v.errmsg=='',vim.v.errmsg)]])
print('PASS actual keys: reused normal style window, dot repeat, delayed Space wr from both windows, cursor snap, Apply restores document')
vim.fn.jobstop(ch);vim.cmd('qa!')
