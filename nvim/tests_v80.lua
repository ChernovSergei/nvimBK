vim.opt.rtp:prepend(vim.fn.getcwd());vim.o.swapfile=false
vim.o.columns=140;vim.o.lines=45;vim.o.winwidth=20;vim.o.equalalways=true
vim.b.wordvim_docx=true;vim.b.docx_original_file='test.docx';vim.bo.filetype='markdown'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'Title','','Text'})
local doc=vim.api.nvim_get_current_buf();local dw=vim.api.nvim_get_current_win()
local ui=require('wordvim.styleui');ui.setup();ui.open(doc,'both')
local function side(ft)for _,w in ipairs(vim.api.nvim_list_wins())do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype==ft then return w end end end
local l=side('wordvimstylegutter');local r=side('wordvimstyles')
local lw=vim.api.nvim_win_get_width(l);local rw=vim.api.nvim_win_get_width(r)
for _,w in ipairs({l,dw,r,dw,l,dw})do vim.api.nvim_set_current_win(w);vim.wait(50);assert(vim.api.nvim_win_get_width(l)==lw,'left width changed');assert(vim.api.nvim_win_get_width(r)==rw,'right width changed')end
require('wordvim.tables').open(3,2)
assert(vim.api.nvim_win_get_width(r)==rw,'table changed right width')
vim.fn.maparg('q','n',false,true).callback()
l=side('wordvimstylegutter')
assert(vim.api.nvim_win_get_width(l)==lw and vim.api.nvim_win_get_width(r)==rw,'return changed widths')
print('PASS panel focus, table entry/cancel preserve widths')
vim.cmd('qa!')
