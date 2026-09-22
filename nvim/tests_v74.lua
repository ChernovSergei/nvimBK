vim.opt.rtp:prepend(vim.fn.getcwd())
vim.g.mapleader=' '
vim.o.columns=140;vim.o.lines=45
vim.b.wordvim_docx=true;vim.b.docx_original_file='test.docx'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'before','after'})
local source=vim.api.nvim_get_current_buf()
local t=require('wordvim.tables');t.setup()
local function key(k) local m=vim.fn.maparg(k,'n',false,true);assert(m.callback,k);m.callback() end
local function panel() for _,w in ipairs(vim.api.nvim_list_wins()) do local b=vim.api.nvim_win_get_buf(w);if vim.bo[b].filetype=='wordvimstyles' then return w,b end end end
t.open(2,2)
local editor,win=vim.api.nvim_get_current_buf(),vim.api.nvim_get_current_win()
local right,rb=panel();assert(right and vim.api.nvim_win_get_width(win)>vim.api.nvim_win_get_width(right))
local cat=require('wordvim.styleui').catalog(source)
assert(vim.api.nvim_buf_get_lines(rb,0,1,false)[1]:find(cat.style_order[1],1,true))
key(' wr');assert(not panel());assert(vim.api.nvim_win_get_width(win)>=138)
key(' wr');assert(panel())
vim.ui.input=function(_,cb)cb('10')end
key('<CR>');key('W');assert(panel())
local function first()for i=0,vim.api.nvim_buf_line_count(source)-1 do local lines=t.lines_at(source,i);if lines then return i,lines end end end
local row,lines=first();assert(row)
local hex=lines[1]:match('META_(%x+)');local model=vim.json.decode((hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end)))
assert(model.cells[1][1].word_style==cat.style_order[10])
assert(model.cells[1][1].word_style_id)
vim.api.nvim_win_set_cursor(0,{row+1,0});t.cut();assert(not first())
vim.api.nvim_win_set_cursor(0,{vim.api.nvim_buf_line_count(0),0});t.paste()
assert(first() and t.validate(source))
print('PASS separate shared style panel, toggle, multidigit style, cleanup, styled cut/paste')
vim.cmd('qa!')
