vim.o.swapfile=false;vim.opt.rtp:prepend(vim.fn.getcwd());require('wordvim').setup()
vim.b.wordvim_docx=true;vim.b.docx_original_file='test.docx';vim.bo.filetype='markdown'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'Global Shortcuts','','# PowerShell','','# Linux terminal','# maven','command','# git','## roll back','git status','# nvim','# nvimWord','# Notes','## global','## nvim java','','tail'})
vim.treesitter.start(0,'markdown')
local b=vim.api.nvim_get_current_buf();local t=require('wordvim.tables')
vim.api.nvim_win_set_cursor(0,{17,0});t.open(5,4);vim.fn.maparg('W','n',false,true).callback()
local function dump(label)
 local parser=vim.treesitter.get_parser(b,'markdown');parser:parse(true)
 local query=vim.treesitter.query.get('markdown','highlights');local results={}
 for _,tree in ipairs(parser:trees())do for id,node in query:iter_captures(tree:root(),b)do if query.captures[id]:find('heading')then results[#results+1]={query.captures[id],node:range()}end end end
 return #results
end
local n=dump('before');vim.api.nvim_win_set_cursor(0,{18,0});t.cut();vim.api.nvim_win_set_cursor(0,{4,0});t.paste();local m=dump('after');assert(n==m,'headings missing')
assert(not vim.treesitter.get_parser(b,'markdown'):parse(true)[1]:root():has_error())
for row=0,vim.api.nvim_buf_line_count(b)-1 do
 local lines=t.lines_at(b,row)
 if lines then
  local hex=lines[1]:match('META_(%x+)')
  local model=vim.json.decode((hex:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)))
  assert(model.cells[2][1].text=='','placeholder leaked into data')
  assert(not table.concat(lines,'\n'):find('\194\160',1,true),'placeholder leaked into export')
 end
end
assert(t.validate(b))
print('PASS Tree-sitter: all headings survive move of 5x4 table with empty rows; no parse error or placeholder in export')
vim.cmd('qa!')
