vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile=false
vim.g.mapleader=' '
vim.g.wordvim_switch_windows_layout=false
require('wordvim').setup()
local source=vim.fn.getcwd()..'/work/paste-roundtrip.docx'
vim.fn.writefile({'Before'},'work/paste-base.md')
vim.fn.system({'pandoc','work/paste-base.md','-o',source});assert(vim.v.shell_error==0)
vim.cmd.edit(source)
local clip=require('wordvim.clipboard')
vim.fn.writefile({'<p>External text</p><table><tr><th>A</th><th>B</th></tr><tr><td>one</td><td>two</td></tr></table>'},'work/paste.html')
clip.file('work/paste.html')
clip.file('tests629/img.png')
vim.fn.writefile({'Machinery management'},'work/paste-external.md')
vim.fn.system({'pandoc','work/paste-external.md','-o','work/paste-external.docx'});assert(vim.v.shell_error==0)
clip.file('work/paste-external.docx')
local t=require('wordvim.tables')
local function count()
 local n=0
 for i=0,vim.api.nvim_buf_line_count(0)-1 do if t.lines_at(vim.api.nvim_get_current_buf(),i) then n=n+1 end end
 return n
end
assert(count()==1,'external table not registered')
for i,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do
 if line:find('[WordVim table]',1,true) then vim.api.nvim_win_set_cursor(0,{i,0});break end
end
t.open();vim.fn.maparg('5','n',false,true).callback();vim.fn.maparg('W','n',false,true).callback()
t.copy();t.paste();assert(count()==2,'internal copy not registered')
vim.cmd.write();assert(not vim.bo.modified)
vim.cmd('bdelete!');vim.cmd.edit(source)
assert(count()==2,'copied table lost on reopening')
local text=table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n')
assert(text:find('External text',1,true) and text:find('Machinery management',1,true))
assert(text:find('![',1,true),'picture lost')
for i=0,vim.api.nvim_buf_line_count(0)-1 do
 local block=t.lines_at(vim.api.nvim_get_current_buf(),i)
 if block then
  local hex=block[1]:match('WORDVIM_TABLE_META_(%x+)')
  local json=hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end)
  assert(vim.json.decode(json).cells[1][1].word_style=='Body Text','numeric style lost')
 end
end
print('PASS HTML table/text, image, external DOCX, internal styled table copy: save/reopen')
vim.cmd('qa!')
