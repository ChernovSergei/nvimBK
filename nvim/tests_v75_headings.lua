vim.o.swapfile=false
vim.opt.rtp:prepend(vim.fn.getcwd());vim.g.mapleader=' '
vim.cmd('syntax on');vim.cmd('filetype plugin on')
require('wordvim').setup()
vim.b.wordvim_docx=true;vim.b.docx_original_file='test.docx';vim.bo.filetype='markdown';vim.bo.syntax='markdown'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'# Before','','paragraph','','## After','','tail'})
local b=vim.api.nvim_get_current_buf()
local function hl(row) return vim.fn.synIDattr(vim.fn.synID(row,4,1),'name') end
local before,after=hl(1),hl(5);assert(before~='' and after~='')
vim.api.nvim_win_set_cursor(0,{3,0})
local t=require('wordvim.tables');t.open(2,2)
vim.fn.maparg('W','n',false,true).callback()
local function headingrow()for i,line in ipairs(vim.api.nvim_buf_get_lines(b,0,-1,false)) do if line=='## After' then return i end end end
assert(hl(1)==before and hl(headingrow())==after,vim.inspect({before,after,hl(1),hl(headingrow())}))
vim.api.nvim_win_set_cursor(0,{4,0});t.cut();vim.api.nvim_win_set_cursor(0,{2,0});t.paste()
assert(hl(headingrow())==after,hl(headingrow()))
vim.fn.maparg(' wt','n',false,true).callback()
vim.fn.maparg('q','n',false,true).callback()
assert(vim.api.nvim_get_current_buf()==b)
assert(hl(headingrow())==after)
print('PASS Markdown heading syntax survives table Apply, Cut/Paste and Cancel')
vim.cmd('qa!')
