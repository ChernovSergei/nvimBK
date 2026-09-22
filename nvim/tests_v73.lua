vim.opt.rtp:prepend(vim.fn.getcwd())
for _,path in ipairs(vim.fn.glob('lua/**/*.lua',false,true)) do assert(loadfile(path),path) end
local e=require('plugins.java_edit')
vim.o.swapfile=false;vim.o.hidden=true
local dir=vim.fn.getcwd()..'/work/rename-'..vim.fn.getpid()..'/src/main/java/demo'
vim.fn.mkdir(dir,'p')
local old,new=dir..'/Old.java',dir..'/New.java'
vim.fn.writefile({'public class Old {}'},old)
vim.cmd.edit(old)
local b=vim.api.nvim_get_current_buf()
local function te(uri,from,to) return {textDocument={uri=vim.uri_from_fname(uri),version=vim.NIL},edits={{range={start={line=0,character=13},['end']={line=0,character=16}},newText=to}}} end
e.apply({documentChanges={te(old,'Old','New'),{kind='rename',oldUri=vim.uri_from_fname(old),newUri=vim.uri_from_fname(new)}}},'utf-16')
assert(not vim.uv.fs_stat(old) and vim.uv.fs_stat(new))
assert(vim.api.nvim_buf_get_name(b):gsub('\\','/')==new:gsub('\\','/'))
vim.cmd('wall')
assert(vim.fn.readfile(new)[1]=='public class New {}')
assert(not vim.uv.fs_stat(old),'old file recreated')
local bad=pcall(e.apply,{documentChanges={{kind='rename',oldUri=vim.uri_from_fname(new),newUri=vim.uri_from_fname(vim.fn.getcwd()..'/Wrong.java')}}},'utf-16')
assert(not bad and vim.uv.fs_stat(new),'invalid destination changed file')
vim.cmd.enew();vim.api.nvim_buf_set_name(0,dir..'/Created.java');vim.bo.filetype='java';e.template()
assert(vim.api.nvim_buf_get_lines(0,0,1,false)[1]=='package demo;')
assert(vim.api.nvim_buf_get_lines(0,2,3,false)[1]=='public class Created {')
print('PASS Java rename filesystem+buffer+save, wrong-directory rejection and package skeleton')
vim.cmd('enew!');vim.b.wordvim_docx=true;vim.b.docx_original_file='test.docx'
local lists=require('wordvim.lists');lists.setup()
vim.api.nvim_buf_set_lines(0,0,-1,false,{'1 first','3 third','4 fourth','tail'})
local ns=vim.api.nvim_create_namespace('test');local mark=vim.api.nvim_buf_set_extmark(0,ns,3,0,{})
lists.renumber_buffer(0)
assert(vim.api.nvim_buf_get_lines(0,1,2,false)[1]=='2 third')
assert(vim.api.nvim_buf_get_extmark_by_id(0,ns,mark,{})[1]==3,'metadata moved')
vim.api.nvim_win_set_cursor(0,{2,0});vim.cmd('WordListMoveUp')
assert(vim.api.nvim_buf_get_lines(0,0,1,false)[1]=='1 third')
vim.cmd('WordListMoveDown')
assert(vim.api.nvim_buf_get_lines(0,0,1,false)[1]=='1 first')
vim.api.nvim_buf_set_lines(0,0,-1,false,{'1 Parent A','    1.1 Child A','2 Parent B','    2.1 Child B'})
vim.api.nvim_win_set_cursor(0,{1,0});vim.cmd('WordListMoveDown')
assert(vim.api.nvim_buf_get_lines(0,0,1,false)[1]=='1 Parent B')
assert(vim.api.nvim_buf_get_lines(0,3,4,false)[1]=='    2.1 Child A')
vim.api.nvim_buf_set_lines(0,0,2,false,{})
vim.api.nvim_exec_autocmds('TextChanged',{buffer=0})
vim.wait(30)
assert(vim.api.nvim_buf_get_lines(0,0,1,false)[1]=='1 Parent A')
print('PASS list automatic renumber after deletion, metadata anchors and subtree move')
local t=require('wordvim.tables');t.setup()
t.insert_fragment({'| A | B |','|---|---|','| C | D |'})
local lines=vim.api.nvim_buf_get_lines(0,0,-1,false)
local row
for i,line in ipairs(lines)do if line:find('[WordVim table]',1,true) then row=i;break end end
vim.api.nvim_win_set_cursor(0,{row,0});t.copy();t.paste()
assert(t.validate(vim.api.nvim_get_current_buf()))
local count=0
for i=0,vim.api.nvim_buf_line_count(0)-1 do if t.lines_at(vim.api.nvim_get_current_buf(),i) then count=count+1 end end
assert(count==2,'table paste lost anchors')
t.open();local editor=vim.api.nvim_get_current_buf()
vim.fn.maparg('5','n',false,true).callback()
vim.fn.maparg('W','n',false,true).callback()
assert(t.validate(vim.api.nvim_get_current_buf()))
print('PASS table copy/paste, numeric style edit and structure validation')
vim.cmd('qa!')


